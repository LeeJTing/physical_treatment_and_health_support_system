"""Outside test on "A Multi-View Raw Video Dataset of Seven Fitness Exercises with Good/Bad Form
Labels" (Mendeley Data kgbb3yn47p v3, CC BY 4.0): 25 people, each exercise once with good and once
with bad form, filmed from the front, side and a diagonal in real gyms.

Three exercises are close to ours, side view (our camera position):
  * bicep_curl -> elbow_flexion: all rules apply (upper arm moving, small range, body swing);
    the bad clips swing the upper arm forward and stop short (checked on sample frames);
  * squat      -> mini_squat: full-depth squats, so only trunk_forward and heels_lift are tested
    (too_deep fires on every full squat by design); the bad clips lean the trunk far forward;
  * push_up    -> wall_push_up: floor push-ups, so only hips_sag and hips_back (the body line).

A clip is called "bad" when a tested rule fires on at least half of its repetitions.

    ai_server\\.venv\\Scripts\\python training\\evaluate_fitness7.py [--workers 3] [--extract-only]

Landmarks are cached in training/data/cache/fitness7. Writes training/reports/fitness7_eval.json.
"""
import argparse
import json
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor, as_completed

import numpy as np

from common import CACHE, DATA, REPORTS
from app.pose import exercises, landmarks
from app.pose.analyse import check_rep
from app.pose.geometry import Features
from app.pose.reps import find_reps

ROOT = DATA / "public" / "fitness7" / "Dataset Exercise Quality-wise"
OUT = CACHE / "fitness7"
TESTS = {"bicep_curl": ("elbow_flexion", None),
         "squat": ("mini_squat", {"trunk_forward", "heels_lift"}),
         "push_up": ("wall_push_up", {"hips_sag", "hips_back"})}


def clips():
    for ex in TESTS:
        for q in ("good", "bad"):
            for p in sorted((ROOT / ex / q / "side").glob("*.mp4")):
                yield ex, q, p


def extract_one(path_str: str) -> str:
    from pathlib import Path
    path = Path(path_str)
    cp = OUT / f"{path.stem}.npz"
    if not cp.exists():
        seq = landmarks.extract(path)
        cp.parent.mkdir(parents=True, exist_ok=True)
        landmarks.save(seq, cp)
    return path.stem


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--extract-only", action="store_true")
    a = ap.parse_args()
    todo = [p for _, _, p in clips() if not (OUT / f"{p.stem}.npz").exists()]
    print(f"{len(todo)} clips to extract", flush=True)
    if todo:
        with ProcessPoolExecutor(a.workers) as pool:
            for i, fut in enumerate(as_completed([pool.submit(extract_one, str(p)) for p in todo]), 1):
                try:
                    print(f"[{i}/{len(todo)}] {fut.result()}", flush=True)
                except Exception as e:
                    print(f"[{i}/{len(todo)}] failed: {e}", flush=True)
    if a.extract_only:
        return
    report = {}
    for ex, (key, tested) in TESTS.items():
        spec = exercises.EXERCISES[key]
        labels = [m.label for m in spec.mistakes if tested is None or m.label in tested]
        conf = [[0, 0], [0, 0]]          # rows true bad/good, cols called bad/good
        fired = {q: defaultdict(list) for q in ("good", "bad")}
        measures = {q: defaultdict(list) for q in ("good", "bad")}
        reps_found, no_reps = [], 0
        for e2, q, p in clips():
            if e2 != ex or not (OUT / f"{p.stem}.npz").exists():
                continue
            seq = landmarks.load(OUT / f"{p.stem}.npz")
            if seq.detected_ratio < 0.5:
                no_reps += 1
                continue
            f = Features(seq)
            if spec.side_signals:
                reps = []
                for side, sig in spec.side_signals(f).items():
                    reps += [r.__class__(r.start, r.peak, r.end, side) for r in find_reps(sig, f.t, spec.rest, spec.active)]
            else:
                reps = find_reps(spec.signal(f), f.t, spec.rest, spec.active)
            reps_found.append(len(reps))
            if not reps:
                no_reps += 1
                continue
            per_rule = {k: 0 for k in labels}
            for r in reps:
                for m in check_rep(spec, f, r):
                    if m in per_rule:
                        per_rule[m] += 1
                for m in spec.mistakes:
                    if m.label in labels:
                        measures[q][m.label].append(m.value(f, r))
            for k in labels:
                fired[q][k].append(per_rule[k] / len(reps))
            called_bad = any(per_rule[k] >= len(reps) / 2 for k in labels)
            conf[0 if q == "bad" else 1][0 if called_bad else 1] += 1
        n = sum(map(sum, conf))
        acc = (conf[0][0] + conf[1][1]) / n if n else float("nan")
        bal = np.mean([conf[0][0] / max(sum(conf[0]), 1), conf[1][1] / max(sum(conf[1]), 1)])
        report[ex] = {
            "our_exercise": key, "rules_tested": labels, "clips_scored": n, "clips_without_reps": no_reps,
            "reps_median": float(np.median(reps_found)) if reps_found else None,
            "confusion_rows_true_bad_good_cols_called_bad_good": conf,
            "accuracy": round(acc, 3), "balanced_accuracy": round(float(bal), 3),
            "rule_fires_share_of_reps_good_vs_bad": {
                k: [round(float(np.mean(fired["good"][k])), 3) if fired["good"][k] else None,
                    round(float(np.mean(fired["bad"][k])), 3) if fired["bad"][k] else None] for k in labels},
            "measure_p10_p50_p90_good_vs_bad": {
                k: [[round(float(x), 3) for x in np.percentile(measures[q][k], [10, 50, 90])] if measures[q][k] else None
                    for q in ("good", "bad")] for k in labels},
            "limits": {m.label: m.limit for m in spec.mistakes if m.label in labels},
        }
        r = report[ex]
        print(f"== {ex} -> {key}: {n} clips, no reps {no_reps}, reps median {r['reps_median']}")
        print(f"   called bad/good: true bad {conf[0]}  true good {conf[1]}  accuracy {acc:.0%}  balanced {bal:.0%}")
        for k in labels:
            g, b = r["rule_fires_share_of_reps_good_vs_bad"][k]
            print(f"   {k:16s} fires on good {g}  bad {b}  limit {r['limits'][k]}  "
                  f"measure good {r['measure_p10_p50_p90_good_vs_bad'][k][0]}  bad {r['measure_p10_p50_p90_good_vs_bad'][k][1]}")
    (REPORTS / "fitness7_eval.json").write_text(json.dumps(report, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
