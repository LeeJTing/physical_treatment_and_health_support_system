"""Condition audit of the posture check (9 Oct, Elwin: "ensure the posture check is done well and check
whether it is really reasonable"). Every labelled clip (Elwin's and p02's, 15 exercises) is scored by the
app's full analysis (rules + trained models) again under changed conditions:

  recording  mirrored (front camera), phone tilted 5 / 10 deg, far from the phone, 5 fps, shaky landmarks
             (low light / low resolution), 15 % of frames lost, camera turned 30 deg round the person,
             feet out of the picture
  movement   1.5x / 2x slower, faster (0.6x), started mid-repetition, only the first 45 % of the clip,
             a weak movement (60 % and 35 % of the person's own range), no movement at all
  patient    the frail targets: rom_scale 0.85 (65+ or moderate risk) and 0.7 (75+ or high risk)

Landmark-level changes (no new video): they isolate the posture check's own behaviour from MediaPipe's.
For each condition: evidence (at least one repetition and no error) and pass rate (accuracy >= 80) on the
correct clips, fail rate on the incorrect clips, repetitions against the original, errors and fall alerts.

    ai_server\\.venv\\Scripts\\python training\\audit_conditions.py

Writes training/reports/condition_audit.json.
"""
import json
from collections import Counter, defaultdict

import numpy as np

from common import CACHE, REPORTS, cached_sequence, own_clips
from app.pose.analyse import PoseError, analyse
from app.pose.landmarks import PoseSequence, VideoInfo
from experiment_camera_angle import render
from landmark_aug import retimed, tilted

PASS = 80.0
SWAP = [(1, 4), (2, 5), (3, 6), (7, 8), (9, 10), (11, 12), (13, 14), (15, 16), (17, 18), (19, 20), (21, 22),
        (23, 24), (25, 26), (27, 28), (29, 30), (31, 32)]
FEET = [27, 28, 29, 30, 31, 32]
RNG = np.random.default_rng(0)


def _seq(s: PoseSequence, xy=None, vis=None, t=None, w=None, h=None) -> PoseSequence:
    xy = s.xy if xy is None else xy
    t = s.t if t is None else t
    return PoseSequence(xy=xy.astype(np.float32), vis=(s.vis if vis is None else vis).astype(np.float32),
                        t=t.astype(np.float32),
                        info=VideoInfo(s.info.fps, len(t), w or s.info.width, h or s.info.height))


def mirrored(s):
    xy = s.xy.copy()
    xy[..., 0] = s.info.width - xy[..., 0]
    vis = s.vis.copy()
    for a, b in SWAP:
        xy[:, [a, b]] = xy[:, [b, a]]
        vis[:, [a, b]] = vis[:, [b, a]]
    return _seq(s, xy, vis)


def far(s, k=0.5):
    c = np.array([s.info.width / 2, s.info.height / 2])
    return _seq(s, (s.xy - c) * k + c)


def every_other(s):
    i = np.arange(0, len(s.t), 2)
    return _seq(s, s.xy[i], s.vis[i], s.t[i])


def body_height(s):
    y = s.xy[..., 1]
    ok = np.isfinite(y).all(axis=1)
    return float(np.median(y[ok].max(axis=1) - y[ok].min(axis=1))) if ok.any() else 500.0


def shaky(s, share=0.01):
    return _seq(s, s.xy + RNG.normal(0, share * body_height(s), s.xy.shape))


def dropped(s, share=0.15, burst=3):
    xy, vis = s.xy.copy(), s.vis.copy()
    n = len(s.t)
    for start in RNG.choice(n, size=max(1, int(n * share / burst)), replace=False):
        xy[start:start + burst] = np.nan
        vis[start:start + burst] = 0
    return _seq(s, xy, vis)


def feet_hidden(s):
    xy, vis = s.xy.copy(), s.vis.copy()
    xy[:, FEET] = np.nan
    vis[:, FEET] = 0
    return _seq(s, xy, vis)


def cut(s, start_sec=0.0, keep=1.0):
    i0 = int(np.searchsorted(s.t, s.t[0] + start_sec))
    i1 = i0 + max(5, int((len(s.t) - i0) * keep))
    i = np.arange(i0, min(i1, len(s.t)))
    return _seq(s, s.xy[i], s.vis[i], s.t[i] - s.t[i[0]])


def weaker(s, alpha):
    """The movement shrunk towards the starting pose (median of the first half second): alpha 1 = as
    recorded, 0 = standing or sitting still."""
    n0 = max(1, int(0.5 / np.median(np.diff(s.t))))
    rest = np.nanmedian(s.xy[:n0], axis=0)
    return _seq(s, rest + alpha * (s.xy - rest))


def turned(clip, yaw):
    p = CACHE / "world" / clip.key / f"{clip.path.stem}.npz"
    if not p.exists():
        return None
    return render(dict(np.load(p, allow_pickle=True)), yaw, 0.0)


CONDITIONS = {
    "original": lambda c, s: s,
    "mirrored": lambda c, s: mirrored(s),
    "tilted_5": lambda c, s: tilted(s, 5.0),
    "tilted_10": lambda c, s: tilted(s, 10.0),
    "far_away": lambda c, s: far(s),
    "fps_5": lambda c, s: every_other(s),
    "shaky_landmarks": lambda c, s: shaky(s),
    "frames_lost_15pct": lambda c, s: dropped(s),
    "camera_turned_30": lambda c, s: turned(c, 30),
    "feet_out_of_picture": lambda c, s: feet_hidden(s),
    "slow_1.5x": lambda c, s: retimed(s, 1.5),
    "slow_2x": lambda c, s: retimed(s, 2.0),
    "fast_0.6x": lambda c, s: retimed(s, 0.6),
    "started_mid_rep": lambda c, s: cut(s, start_sec=1.5),
    "first_45pct_only": lambda c, s: cut(s, keep=0.45),
    "weak_60pct": lambda c, s: weaker(s, 0.6),
    "weak_35pct": lambda c, s: weaker(s, 0.35),
    "no_movement": lambda c, s: weaker(s, 0.0),
}
PATIENT = {"rom_0.85 (65+ / moderate)": 0.85, "rom_0.7 (75+ / high)": 0.7}


def run(key, seq, rom=1.0):
    if seq is None:
        return None
    try:
        r = analyse(key, seq, use_model=True, rom_scale=rom)
        return {"reps": r["repetitions"], "acc": r["accuracy"], "mistakes": sorted(r["mistakes"]),
                "partial": bool(r.get("partial_repetitions")), "fall": "safety_alert" in r,
                "tips": len(r.get("quality_tips", []))}
    except PoseError as e:
        return {"error": e.code}


def summarise(rows):
    ok = [r for r in rows if r["correct"]]
    bad = [r for r in rows if not r["correct"]]
    good = lambda r: "error" not in r["res"]  # noqa: E731
    s = {
        "correct_clips": len(ok),
        "evidence_on_correct": round(np.mean([good(r) and r["res"]["reps"] >= 1 for r in ok]), 3) if ok else None,
        "pass_on_correct": round(np.mean([good(r) and r["res"]["acc"] >= PASS for r in ok]), 3) if ok else None,
        "fail_on_incorrect": round(np.mean([not good(r) or r["res"]["acc"] < PASS for r in bad]), 3) if bad else None,
        "reps_within_1_of_original": round(np.mean([good(r) and abs(r["res"]["reps"] - r["base_reps"]) <= 1
                                                    for r in rows if r["base_reps"] is not None]), 3),
        "partial_flag": int(sum(good(r) and r["res"]["partial"] for r in rows)),
        "fall_alerts": int(sum(good(r) and r["res"]["fall"] for r in rows)),
        "errors": dict(Counter(r["res"]["error"] for r in rows if not good(r))),
    }
    return s


def main():
    clips = [c for c in own_clips() if c.name_ok and not c.problems]
    rows = defaultdict(list)
    per_key = defaultdict(lambda: defaultdict(list))
    for n, c in enumerate(clips, 1):
        s = cached_sequence(c)
        base = run(c.key, s)
        base_reps = base["reps"] if base and "error" not in base else None
        for name, make in CONDITIONS.items():
            res = run(c.key, make(c, s))
            if res is None:
                continue
            row = {"clip": c.path.stem, "key": c.key, "correct": c.is_correct, "mistake": c.mistake,
                   "base_reps": base_reps, "res": res}
            rows[name].append(row)
            per_key[c.key][name].append(row)
        for name, rom in PATIENT.items():
            for cond in ("original", "weak_60pct"):
                seq = s if cond == "original" else weaker(s, 0.6)
                row = {"clip": c.path.stem, "key": c.key, "correct": c.is_correct, "mistake": c.mistake,
                       "base_reps": base_reps, "res": run(c.key, seq, rom)}
                rows[f"{name} {cond}"].append(row)
        if n % 25 == 0:
            print(f"  {n}/{len(clips)}", flush=True)

    report = {"conditions": {k: summarise(v) for k, v in rows.items()},
              "per_exercise": {k: {c: summarise(v) for c, v in d.items()} for k, d in per_key.items()}}
    # Which mistakes the frail targets let through (should be range-of-movement ones only).
    relaxed = defaultdict(lambda: [0, 0])
    for full, frail in zip(rows["original"], rows["rom_0.7 (75+ / high) original"]):
        if full["correct"] or "error" in full["res"] or "error" in frail["res"]:
            continue
        relaxed[f"{full['key']}.{full['mistake']}"][1] += 1
        if full["res"]["acc"] < PASS <= frail["res"]["acc"]:
            relaxed[f"{full['key']}.{full['mistake']}"][0] += 1
    report["incorrect_clips_passing_only_with_frail_targets"] = {k: f"{a}/{b}" for k, (a, b) in sorted(relaxed.items())}

    print(f"\n{'condition':40s} {'evidence':>9s} {'pass ok':>8s} {'fail bad':>9s} {'reps±1':>7s} {'partial':>7s} "
          f"{'falls':>5s}  errors")
    for name, s in report["conditions"].items():
        print(f"{name:40s} {s['evidence_on_correct']:9.0%} {s['pass_on_correct']:8.0%} {s['fail_on_incorrect']:9.0%} "
              f"{s['reps_within_1_of_original']:7.0%} {s['partial_flag']:7d} {s['fall_alerts']:5d}  {s['errors']}")
    print("\nincorrect clips that pass only with the 0.7 frail targets:")
    for k, v in report["incorrect_clips_passing_only_with_frail_targets"].items():
        print(f"  {k:45s} {v}")
    (REPORTS / "condition_audit.json").write_text(json.dumps(report, indent=1), encoding="utf-8")
    full = {k: v for k, v in rows.items()}
    (REPORTS / "condition_audit_rows.json").write_text(json.dumps(full), encoding="utf-8")
    print(f"\nWritten {REPORTS / 'condition_audit.json'}")


if __name__ == "__main__":
    main()
