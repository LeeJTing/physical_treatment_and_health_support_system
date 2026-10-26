"""Camera angle on real people: REHAB26-ViewAngles (Zenodo, CC BY-NC 4.0; MediaPipe joints only, no
video). 5 people, 3 synchronized portrait cameras, each person turned through 11 orientations, so every
block of repetitions is seen from 3 angles between -90 (profile) and +90; a physiotherapist marked
every repetition correct (1) or incorrect (5).

  ex1 arm abduction (right arm)  -> shoulder_abduction (front view in the app)
  ex6 squat                      -> mini_squat (side view in the app)
  ex7 shoulder extension         -> not in the app: should NOT pass as shoulder_flexion / abduction

For every block (person x orientation) and camera: the app's analysis (reps found, error code, the
side-view tip), and per labelled repetition whether the rules agree with the physiotherapist, grouped
by viewing angle (0 = facing the camera, 90 = profile).

    ai_server\\.venv\\Scripts\\python training\\evaluate_rehab26.py

Needs the *_2d.npy files unzipped from jointSequences-mediapipe.zip into
training/data/public/rehab26_viewangles/mediapipe/. Writes training/reports/rehab26_eval.json.
"""
import csv
import json
from collections import Counter, defaultdict

import numpy as np

from common import DATA, REPORTS
from app.pose.analyse import PoseError, analyse, check_rep, side_view_ratio
from app.pose.exercises import EXERCISES
from app.pose.geometry import Features
from app.pose.landmarks import PoseSequence, VideoInfo
from app.pose.reps import Rep
from evaluate_rehab import single_arm_abduction

ROOT = DATA / "public" / "rehab26_viewangles"
W, H = 1080, 1920          # portrait: arm length stays constant at 9:16 (checked on ex1 frontal reps)
FPS, STEP = 30.0, 3        # the app samples 10 fps
MARGIN = 1.5               # seconds kept before the first and after the last repetition of a block
CAM_OFFSET = {1: 0, 2: 45, 3: 90}      # viewing angle = offset - orientation

APP_KEY = {1: "shoulder_abduction", 6: "mini_squat"}
RULE_SPEC = {1: single_arm_abduction(), 6: EXERCISES["mini_squat"]}
NEGATIVE_KEYS = {7: ["shoulder_flexion", "shoulder_abduction"]}

_arrays = {}


def joints(ex: int, person: str, cam: int) -> np.ndarray:
    k = (ex, person, cam)
    if k not in _arrays:
        _arrays.clear()                 # one recording at a time (each is 10-20 MB)
        _arrays[k] = np.load(ROOT / "mediapipe" / f"ex{ex}" / f"ex{ex}_{person}_cam{cam}_2d.npy")
    return _arrays[k]


def clip(a: np.ndarray, first: int, last: int) -> tuple[PoseSequence, int]:
    """10 fps PoseSequence in pixels for frames first..last (plus margins); returns it and its first frame."""
    lo = max(0, first - int(MARGIN * FPS))
    hi = min(len(a) - 1, last + int(MARGIN * FPS))
    idx = np.arange(lo, hi + 1, STEP)
    p = a[idx]
    xy = p[:, :, :2] * np.array([W, H], dtype=float)
    vis = p[:, :, 3].astype(float)
    missing = np.all(p[:, :, :2] == 0, axis=(1, 2)) | np.isnan(p[:, 0, 0])
    xy[missing] = np.nan
    vis[missing] = 0.0
    t = (idx - lo) / FPS
    return PoseSequence(xy=xy, vis=vis, t=t, info=VideoInfo(fps=FPS / STEP, frame_count=len(idx), width=W, height=H)), lo


def blocks():
    rows = list(csv.DictReader((ROOT / "Segmentation.csv").open(encoding="utf-8"), delimiter=";"))
    out = defaultdict(list)
    for r in rows:
        out[(int(r["exercise_id"]), r["person"], int(r["person_orientation"]))].append(r)
    return out


def bucket(angle: int) -> str:
    a = abs(angle)
    return "0-20" if a <= 20 else "25-40" if a <= 40 else "45-60" if a <= 60 else "65-90"


def main():
    groups = blocks()
    print(f"{len(groups)} blocks, {sum(map(len, groups.values()))} labelled repetitions")
    runs, rules = [], []
    for (ex, person, o), reps in sorted(groups.items()):
        first = min(int(r["first_frame"]) for r in reps)
        last = max(int(r["last_frame"]) for r in reps)
        for cam, off in CAM_OFFSET.items():
            angle = off - o
            seq, lo = clip(joints(ex, person, cam), first, last)
            if seq.detected_ratio < 0.5:
                continue
            ratio = side_view_ratio(seq)
            for key in ([APP_KEY[ex]] if ex in APP_KEY else NEGATIVE_KEYS[ex]):
                row = {"ex": ex, "person": person, "orientation": o, "cam": cam, "angle": angle, "key": key,
                       "labelled": len(reps), "correct": sum(r["correctness_score"] == "1" for r in reps),
                       "view_ratio": round(ratio, 3)}
                try:
                    res = analyse(key, seq, use_model=False)
                    row.update(reps=res["repetitions"], accuracy=res["accuracy"], mistakes=res["mistakes"],
                               partial=bool(res.get("partial_repetitions")),
                               side_tip="camera_not_at_side" in res, fall="safety_alert" in res)
                except PoseError as e:
                    row.update(error=e.code, why=e.message)
                runs.append(row)
            if ex in RULE_SPEC:
                spec = RULE_SPEC[ex]
                f = Features(seq)
                sig = spec.signal(f)
                for r in reps:
                    t0, t1 = (int(r["first_frame"]) - lo) / FPS, (int(r["last_frame"]) - lo) / FPS
                    idx = np.where((f.t >= t0) & (f.t <= t1))[0]
                    if len(idx) < 4 or not np.isfinite(sig[idx]).any():
                        continue
                    rep = Rep(int(idx[0]), int(idx[np.nanargmax(sig[idx])]), int(idx[-1]))
                    m = check_rep(spec, f, rep)
                    rules.append({"ex": ex, "angle": angle, "correct": r["correctness_score"] == "1",
                                  "error": r["error_description"], "mistakes": m,
                                  "peak": round(float(np.nanmax(sig[idx])), 1)})
        print(f"  ex{ex} {person:6s} o={o:2d}: {len(reps)} reps", flush=True)

    report = {"runs": runs, "rules": rules}
    print("\n== The app's analysis by viewing angle (|angle|) ==")
    for ex, keys in ((1, ["shoulder_abduction"]), (6, ["mini_squat"]), (7, NEGATIVE_KEYS[7])):
        for key in keys:
            print(f"\nex{ex} as {key}")
            summ = {}
            for b in ("0-20", "25-40", "45-60", "65-90"):
                sel = [r for r in runs if r["ex"] == ex and r["key"] == key and bucket(r["angle"]) == b]
                if not sel:
                    continue
                ok = [r for r in sel if "error" not in r]
                errs = Counter(r["error"] for r in sel if "error" in r)
                within1 = sum(abs(r["reps"] - r["labelled"]) <= 1 for r in ok)
                ratios = [r["view_ratio"] for r in sel]
                s = {"blocks": len(sel), "analysed": len(ok), "errors": dict(errs),
                     "reps_within_1": within1, "side_tip": sum(r["side_tip"] for r in ok),
                     "view_ratio_p10_p50_p90": [round(float(x), 2) for x in np.percentile(ratios, [10, 50, 90])],
                     "mean_accuracy": round(float(np.mean([r["accuracy"] for r in ok])), 1) if ok else None}
                summ[b] = s
                print(f"  |angle| {b:5s}: {len(sel):3d} blocks | analysed {len(ok):3d} | errors {dict(errs)} | "
                      f"reps within 1 {within1} | side tip {s['side_tip']} | view ratio {s['view_ratio_p10_p50_p90']}"
                      f" | mean accuracy {s['mean_accuracy']}")
            report[f"ex{ex}_{key}"] = summ

    print("\n== Rules vs physiotherapist by viewing angle ==")
    for ex in RULE_SPEC:
        print(f"\nex{ex} rules ({RULE_SPEC[ex].key})")
        for b in ("0-20", "25-40", "45-60", "65-90"):
            sel = [r for r in rules if r["ex"] == ex and bucket(r["angle"]) == b]
            if not sel:
                continue
            agree = sum((not r["mistakes"]) == r["correct"] for r in sel)
            fired = Counter(m for r in sel if r["correct"] for m in r["mistakes"])
            caught = Counter(r["error"] for r in sel if not r["correct"] and r["mistakes"])
            missed = Counter(r["error"] for r in sel if not r["correct"] and not r["mistakes"])
            n_ok = sum(r["correct"] for r in sel)
            print(f"  |angle| {b:5s}: {len(sel):3d} reps | agree {agree / len(sel):.0%} | correct passed "
                  f"{sum(r['correct'] and not r['mistakes'] for r in sel)}/{n_ok} | false flags {dict(fired)}")
            print(f"           caught {dict(caught)} | missed {dict(missed)}")
    REPORTS.mkdir(exist_ok=True)
    (REPORTS / "rehab26_eval.json").write_text(json.dumps(report, indent=1), encoding="utf-8")
    print(f"\nWritten {REPORTS / 'rehab26_eval.json'}")


if __name__ == "__main__":
    main()
