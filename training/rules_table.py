"""Accuracy of the angle rules on the labelled clips, default limits vs tuned limits (Chapter 5).

Per rule (repetition level): detection rate = share of reps recorded WITH that mistake on which
the rule fires; false-alarm rate = share of reps from CORRECT clips on which it fires.
Per clip (what the patient sees): a mistake clip is "caught" when /pose lists the recorded
mistake; a correct clip is "clean" when /pose lists no mistake at all.

    ai_server\.venv\Scripts\python training\rules_table.py

Writes training/reports/rules_table.csv and rules_table.json.
"""
import csv
import json
from collections import defaultdict

import numpy as np

from common import REPORTS, cached_sequence, own_clips
from app.pose.analyse import analyse
from app.pose.exercises import DEFAULT_LIMITS, EXERCISES
from tune_rules import own_samples


def fires(values: np.ndarray, limit: float, above: bool) -> np.ndarray:
    return values > limit if above else values < limit


def rep_level():
    rows = []
    for key, items in sorted(own_samples().items()):
        for m in EXERCISES[key].mistakes:
            ok = np.array([m.value(f, r) for f, r, good, _ in items if good])
            bad = np.array([m.value(f, r) for f, r, good, mis in items if not good and mis == m.label])
            name = f"{key}.{m.label}"
            row = {"exercise": key, "rule": m.label, "unit": m.unit, "correct_reps": len(ok), "mistake_reps": len(bad),
                   "default_limit": DEFAULT_LIMITS[name], "tuned_limit": m.limit}
            for tag, lim in (("default", DEFAULT_LIMITS[name]), ("tuned", m.limit)):
                row[f"{tag}_detection"] = round(float(fires(bad, lim, m.above).mean()), 3) if len(bad) else None
                row[f"{tag}_false_alarm"] = round(float(fires(ok, lim, m.above).mean()), 3) if len(ok) else None
            rows.append(row)
    return rows


def clip_level():
    out = defaultdict(lambda: {"mistake_clips": 0, "caught": 0, "correct_clips": 0, "clean": 0, "rep_count_5": 0, "clips": 0})
    for clip in own_clips():
        if not clip.name_ok or clip.problems:
            continue
        try:
            res = analyse(clip.key, cached_sequence(clip), use_model=False)
        except Exception:
            continue
        o = out[clip.key]
        o["clips"] += 1
        o["rep_count_5"] += int(res.get("repetitions") == 5)
        if clip.is_correct:
            o["correct_clips"] += 1
            o["clean"] += int(not res["mistakes"])
        else:
            o["mistake_clips"] += 1
            o["caught"] += int(clip.mistake in res["mistakes"])
    return dict(out)


def main():
    reps = rep_level()
    clips = clip_level()
    REPORTS.mkdir(exist_ok=True)
    with (REPORTS / "rules_table.csv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(reps[0]))
        w.writeheader()
        w.writerows(reps)
    (REPORTS / "rules_table.json").write_text(json.dumps({"repetitions": reps, "clips": clips}, indent=2), encoding="utf-8")
    pct = lambda v: "  -  " if v is None else f"{v:5.0%}"
    print(f"{'rule':38s} {'reps ok/bad':>11s} | {'default':>7s} {'detect':>6s} {'false':>6s} | {'tuned':>7s} {'detect':>6s} {'false':>6s}")
    for r in reps:
        print(f"{r['exercise'] + '.' + r['rule']:38s} {r['correct_reps']:>5d}/{r['mistake_reps']:<5d} | {r['default_limit']:>7.4g} "
              f"{pct(r['default_detection']):>6s} {pct(r['default_false_alarm']):>6s} | {r['tuned_limit']:>7.4g} "
              f"{pct(r['tuned_detection']):>6s} {pct(r['tuned_false_alarm']):>6s}")
    print()
    for key, o in sorted(clips.items()):
        print(f"{key:20s} mistake clips caught {o['caught']}/{o['mistake_clips']}   correct clips with no flag "
              f"{o['clean']}/{o['correct_clips']}   exactly 5 reps counted {o['rep_count_5']}/{o['clips']}")


if __name__ == "__main__":
    main()
