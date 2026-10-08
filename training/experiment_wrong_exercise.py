"""Wrong-exercise check (8 Oct, bug from Elwin: a video of a different exercise came back as a pass for
shoulder abduction). Every labelled clip is scored as every one of the 15 exercises, with full
targets (rom_scale 1.0) and frail targets (0.7, the High-risk / 75+ setting, where the trained model is
not used). A wrong exercise should never pass (accuracy >= 80) and ideally should not even yield
repetitions.

    ai_server\\.venv\\Scripts\\python training\\experiment_wrong_exercise.py

Writes training/reports/wrong_exercise_matrix.json.
"""
import json
from collections import defaultdict

from common import REPORTS, cached_sequence, own_clips
from app.pose import exercises
from app.pose.analyse import PoseError, analyse

PASS = 80.0


def main():
    keys = list(exercises.EXERCISES)
    clips = [c for c in own_clips() if c.name_ok and not c.problems]
    seqs = {c.path: cached_sequence(c) for c in clips}
    out = {}
    for scale in (1.0, 0.7):
        passed = defaultdict(lambda: defaultdict(int))
        reps = defaultdict(lambda: defaultdict(int))
        total = defaultdict(int)
        for c in clips:
            total[c.key] += 1
            for as_key in keys:
                try:
                    res = analyse(as_key, seqs[c.path], use_model=True, rom_scale=scale)
                except PoseError:
                    continue
                reps[c.key][as_key] += 1
                if res["accuracy"] >= PASS and "safety_alert" not in res:
                    passed[c.key][as_key] += 1
        out[str(scale)] = {"total": dict(total), "passed": {k: dict(v) for k, v in passed.items()},
                           "reps_found": {k: dict(v) for k, v in reps.items()}}
        print(f"\n== rom_scale {scale}: clips of row-exercise that PASS when scored as column-exercise (wrong ones only)")
        bad = 0
        for k in keys:
            wrong = {a: n for a, n in passed[k].items() if a != k and n}
            bad += sum(wrong.values())
            own = passed[k].get(k, 0)
            print(f"  {k:18s} own pass {own:2d}/{total[k]:2d} | wrong passes: "
                  + (", ".join(f"{a} {n}" for a, n in sorted(wrong.items(), key=lambda x: -x[1])) or "-"))
        n_wrong = sum(total.values()) * (len(keys) - 1)
        print(f"  wrong-exercise passes: {bad} of {n_wrong} clip x exercise pairs")
    (REPORTS / "wrong_exercise_matrix.json").write_text(json.dumps(out, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
