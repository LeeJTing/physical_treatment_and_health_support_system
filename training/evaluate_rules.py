"""Measures how well the angle rules judge the labelled clips (for tuning and for Chapter 5).

For every clip the rules decide "correct" when no mistake is found in at
least half of the repetitions. Per exercise it reports the confusion matrix,
accuracy, precision, recall and F1, and for every mistake label how often the
rule caught it (on clips recorded with that mistake) and how often it fired
falsely (on correct clips). Thresholds to tune are in ai_server/app/pose/exercises.py.

    ai_server\\.venv\\Scripts\\python training\\evaluate_rules.py [pose_key ...]

Writes training/reports/rules_evaluation.json and rules_evaluation.csv.
"""
import csv
import json
import sys
from collections import defaultdict

from common import REPORTS, cached_sequence, own_clips
from app.pose.analyse import PoseError, analyse
from app.pose.exercises import EXERCISES
from train import metrics


def main():
    keys = sys.argv[1:] or None
    clips = [c for c in own_clips(keys) if c.name_ok and not c.problems]
    if not clips:
        print("No correctly named clips found.")
        return
    rows, per_ex = [], defaultdict(lambda: {"y": [], "p": [], "caught": defaultdict(list), "false": defaultdict(list)})
    for clip in clips:
        seq = cached_sequence(clip)
        try:
            res = analyse(clip.key, seq, use_model=False)
        except PoseError as e:
            rows.append({"exercise": clip.key, "file": clip.path.name, "label": clip.label, "error": e.code})
            continue
        reps = res["rep_details"]
        clean = sum(1 for d in reps if not d["mistakes"])
        pred_correct = clean >= len(reps) / 2
        e = per_ex[clip.key]
        e["y"].append(int(clip.is_correct)); e["p"].append(float(pred_correct))
        found = set(res["mistakes"])
        if clip.is_correct:
            for m in EXERCISES[clip.key].mistakes:
                e["false"][m.label].append(m.label in found)
        else:
            e["caught"][clip.mistake].append(clip.mistake in found)
        rows.append({"exercise": clip.key, "file": clip.path.name, "label": clip.label, "mistake": clip.mistake,
                     "reps": res["repetitions"], "accuracy": res["accuracy"],
                     "predicted": "correct" if pred_correct else "incorrect",
                     "rule_mistakes": " ".join(f"{k}x{v}" for k, v in res["mistakes"].items())})

    import numpy as np
    summary = {}
    for key, e in sorted(per_ex.items()):
        m = metrics(np.array(e["y"]), np.array(e["p"]))
        m["n_clips"] = len(e["y"])
        m["mistakes"] = {
            label: {"caught_on_mistake_clips": f"{sum(e['caught'][label])}/{len(e['caught'][label])}",
                    "false_alarms_on_correct_clips": f"{sum(e['false'][label])}/{len(e['false'][label])}"}
            for label in [mm.label for mm in EXERCISES[key].mistakes]}
        summary[key] = m
        print(f"\n{key}: {m['n_clips']} clips, accuracy {m['accuracy']:.0%}, F1 {m['f1']:.2f}, "
              f"confusion {m['confusion_matrix']['rows_true_cols_pred']}")
        for label, v in m["mistakes"].items():
            print(f"   {label:22s} caught {v['caught_on_mistake_clips']:>6s}   false alarms {v['false_alarms_on_correct_clips']:>6s}")
    REPORTS.mkdir(exist_ok=True)
    (REPORTS / "rules_evaluation.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    cols = ["exercise", "file", "label", "mistake", "reps", "accuracy", "predicted", "rule_mistakes", "error"]
    with (REPORTS / "rules_evaluation.csv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader(); w.writerows(rows)
    print(f"\nWritten: {REPORTS / 'rules_evaluation.json'}")


if __name__ == "__main__":
    main()
