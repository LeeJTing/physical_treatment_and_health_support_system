"""Do the angle rules give the same verdict when only the camera changes?

For the trained-model exercises every clip has 8 augmented copies (other outfits and rooms, low
light, tilt, zoom in/out, crop, low resolution; augment.py). The movement is identical, so a
robust rule fires on the same share of repetitions in the copies as in the original footage.
Per rule: detection on mistake reps and false alarms on correct reps, originals vs copies.

    ai_server\\.venv\\Scripts\\python training\\evaluate_rules_robustness.py

Writes training/reports/rules_robustness_camera.json.
"""
import json
from collections import defaultdict

import numpy as np

from common import CACHE, REPORTS, cached_sequence, own_clips
from app.pose import landmarks
from app.pose.analyse import detect_reps
from app.pose.exercises import EXERCISES
from app.pose.geometry import Features

KEYS = ["sit_to_stand", "shoulder_abduction", "shoulder_flexion", "hip_abduction", "knee_extension"]


def main():
    report = {}
    for key in KEYS:
        spec = EXERCISES[key]
        # rule -> {"orig"/"aug": {"hit": [...], "fa": [...]}}
        r = defaultdict(lambda: {"orig": {"hit": [], "fa": []}, "aug": {"hit": [], "fa": []}})
        reps_count = {"orig": [], "aug": []}
        for clip in own_clips([key]):
            if not clip.name_ok:
                continue
            versions = [("orig", cached_sequence(clip))] + [
                ("aug", landmarks.load(p)) for p in sorted((CACHE / key / "aug").glob(f"{clip.path.stem}__aug*.npz"))]
            n_orig = None
            for kind, seq in versions:
                if seq.detected_ratio < 0.5:
                    continue
                f = Features(seq)
                reps = detect_reps(spec, f)
                if kind == "orig":
                    n_orig = len(reps)
                elif n_orig is not None:
                    reps_count["aug"].append(len(reps) - n_orig)
                for rep in reps:
                    for m in spec.mistakes:
                        try:
                            fired = m.check(f, rep)
                        except (KeyError, IndexError, ValueError):
                            continue
                        if clip.is_correct:
                            r[m.label][kind]["fa"].append(fired)
                        elif clip.mistake == m.label:
                            r[m.label][kind]["hit"].append(fired)
        rows = {}
        print(f"\n{key}: rep count change in copies (copy - original): "
              f"same {np.mean(np.array(reps_count['aug']) == 0):.0%}, within 1 {np.mean(np.abs(reps_count['aug']) <= 1):.0%}")
        for label, d in r.items():
            row = {k: {"detection": round(float(np.mean(v["hit"])), 3) if v["hit"] else None,
                       "false_alarm": round(float(np.mean(v["fa"])), 3) if v["fa"] else None,
                       "n_mistake": len(v["hit"]), "n_correct": len(v["fa"])} for k, v in d.items()}
            rows[label] = row
            o, a = row["orig"], row["aug"]
            print(f"  {label:22s} detection {o['detection'] if o['detection'] is not None else '-':>5} -> "
                  f"{a['detection'] if a['detection'] is not None else '-':>5}   false alarm "
                  f"{o['false_alarm']:>5} -> {a['false_alarm']:>5}")
        report[key] = {"rules": rows, "rep_count_same_share": float(np.mean(np.array(reps_count["aug"]) == 0))}
    (REPORTS / "rules_robustness_camera.json").write_text(json.dumps(report, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
