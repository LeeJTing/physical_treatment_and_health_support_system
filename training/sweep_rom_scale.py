"""How strict should the range-of-motion targets be? (11 Oct, Elwin: "85% is still too high for a normal user,
as our model and angle rules might not be accurate enough".)

rom_scale multiplies only the range-of-motion limits (the mistakes with a rom_base: low_range, low_raise, ...);
form checks (bent elbow, trunk lean, ...) and the 80 % pass mark do not change. Today: 1.0 low risk,
0.85 medium, 0.7 high. This sweeps the scale and reports, at each value:

  own       Elwin's and p02's labelled clips (15 exercises, rules + trained models, as the app scores them):
            correct clips passed, incorrect clips failed, and incorrect clips failed by kind of mistake
            (range vs form) - only range mistakes can be let through by a lower scale
  weaker    the correct clips with the movement shrunk to 85 % / 70 % / 55 % of the person's own range
            (audit_conditions.weaker): how much smaller a movement still passes
  irds      IntelliRehabDS (other people, physiotherapist labels; rules only, as evaluate_irds.py):
            correct repetitions passed, incorrect caught
  stroke    Upper Limb Stroke dataset (10 volunteers; rules only): complete cycles passed, incomplete failed

    ai_server\\.venv\\Scripts\\python training\\sweep_rom_scale.py

Writes training/reports/rom_scale_sweep.json.
"""
import json
from collections import defaultdict

import numpy as np

import evaluate_irds as IR
import evaluate_wrist_hand as WH
from audit_conditions import PASS, run, weaker
from common import REPORTS, cached_sequence, own_clips
from app.pose import exercises as X
from app.pose import landmarks
from app.pose.analyse import PoseError, analyse, check_rep
from app.pose.geometry import Features
from app.pose.reps import find_reps

SCALES = [1.0, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7, 0.65, 0.6]
WEAK = [0.85, 0.7, 0.55]
RANGE_LABELS = {f"{k}.{m.label}" for k, s in X.EXERCISES.items() for m in s.mistakes if m.rom_base is not None}


def passed(r):
    return r is not None and "error" not in r and r["acc"] >= PASS


def own():
    clips = [c for c in own_clips() if c.name_ok and not c.problems and c.cache_path.exists()]
    seqs = {c.path.stem: cached_sequence(c) for c in clips}
    out = {}
    for scale in SCALES:
        ok, bad, rng, form = [], [], [], []
        weak = defaultdict(list)
        for c in clips:
            r = run(c.key, seqs[c.path.stem], scale)
            if c.is_correct:
                ok.append(passed(r))
                for a in WEAK:
                    weak[a].append(passed(run(c.key, weaker(seqs[c.path.stem], a), scale)))
            else:
                bad.append(not passed(r))
                (rng if f"{c.key}.{c.mistake}" in RANGE_LABELS else form).append(not passed(r))
        out[scale] = {"correct_passed": round(float(np.mean(ok)), 3), "incorrect_failed": round(float(np.mean(bad)), 3),
                      "range_mistake_clips_failed": round(float(np.mean(rng)), 3) if rng else None,
                      "form_mistake_clips_failed": round(float(np.mean(form)), 3) if form else None,
                      "n_correct": len(ok), "n_incorrect": len(bad), "n_range": len(rng), "n_form": len(form),
                      "weak_movement_passed": {f"{int(a * 100)}pct": round(float(np.mean(v)), 3)
                                               for a, v in weak.items()}}
        print(f"own  x{scale:4.2f}: correct passed {out[scale]['correct_passed']:.1%}  incorrect failed "
              f"{out[scale]['incorrect_failed']:.1%} (range {out[scale]['range_mistake_clips_failed']:.1%}, form "
              f"{out[scale]['form_mistake_clips_failed']:.1%})  weak 85/70/55 % passed "
              + " / ".join(f"{v:.0%}" for v in out[scale]["weak_movement_passed"].values()), flush=True)
    return out


def irds():
    specs = {"elbow_flexion": X.EXERCISES["elbow_flexion"], "shoulder_flexion": X.EXERCISES["shoulder_flexion"],
             "shoulder_abduction_1arm": IR.single_arm_abduction()}
    data = []
    for p in sorted(IR.ROOT.glob("*.txt")):
        parts = p.stem.split("_")
        if len(parts) < 6 or parts[4] not in ("1", "2"):
            continue
        for name, (gestures, view) in IR.TESTS.items():
            if parts[2] in gestures:
                pos, vis = IR.read(p)
                if len(pos) >= 10:
                    data.append((name, "correct" if parts[4] == "1" else "incorrect", Features(IR.to_sequence(pos, vis, view))))
    out = {}
    for scale in SCALES:
        res = defaultdict(lambda: {"correct": [], "incorrect": []})
        for name, truth, f in data:
            spec = specs[name]
            reps = find_reps(spec.signal(f), f.t, spec.rest, spec.active)
            if not reps:
                res[name][truth].append(False)                      # nothing counted = not passed
                continue
            r = max(reps, key=lambda x: x.end - x.start)
            ms = [m for m in check_rep(spec, f, r, scale) if m not in IR.NOT_COMPARABLE]
            res[name][truth].append(not ms)
        out[scale] = {n: {"correct_passed": round(float(np.mean(v["correct"])), 3),
                          "incorrect_caught": round(1 - float(np.mean(v["incorrect"])), 3)} for n, v in res.items()}
        print(f"irds x{scale:4.2f}: " + "  ".join(f"{n} passed {v['correct_passed']:.0%} caught {v['incorrect_caught']:.0%}"
                                                  for n, v in out[scale].items()), flush=True)
    return out


def stroke():
    seqs = [(k, label, landmarks.load(WH.cache_of(k, p))) for k, label, p in WH.videos()
            if WH.cache_of(k, p).exists()]
    out = {}
    for scale in SCALES:
        res = defaultdict(lambda: {"Complete": [], "Incomplete": []})
        for kind, label, seq in seqs:
            key = "wrist_extension" if kind == "wrist" else "hand_open_close"
            try:
                r = analyse(key, seq, use_model=False, rom_scale=scale)
                res[key][label].append(r["accuracy"] >= PASS)
            except PoseError:
                res[key][label].append(False)
        out[scale] = {k: {"complete_passed": round(float(np.mean(v["Complete"])), 3),
                          "incomplete_failed": round(1 - float(np.mean(v["Incomplete"])), 3)} for k, v in res.items()}
        print(f"strk x{scale:4.2f}: " + "  ".join(f"{k} complete passed {v['complete_passed']:.0%} incomplete failed "
                                                  f"{v['incomplete_failed']:.0%}" for k, v in out[scale].items()), flush=True)
    return out


def main():
    report = {"scales": SCALES, "range_labels": sorted(RANGE_LABELS), "pass_mark": PASS,
              "own": own(), "irds": irds(), "stroke": stroke()}
    REPORTS.mkdir(exist_ok=True)
    (REPORTS / "rom_scale_sweep.json").write_text(json.dumps(report, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
