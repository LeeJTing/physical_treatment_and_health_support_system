"""Picks each posture rule's limit from labelled repetitions (data-driven rule tuning).

For every exercise and mistake rule, the rule's measurement is taken on
  * repetitions from CORRECT clips (the mistake should NOT fire), and
  * repetitions from clips recorded WITH THAT MISTAKE (it should fire).
The limit is moved to the value that best separates the two groups (highest balanced
accuracy = mean of the hit rate on mistake reps and on correct reps), keeping the rule's
direction. Rules with fewer than MIN_PER_CLASS repetitions on either side are left alone.

    ai_server\\.venv\\Scripts\\python training\\tune_rules.py              (report only)
    ai_server\\.venv\\Scripts\\python training\\tune_rules.py --write      (save thresholds.json)
    ai_server\\.venv\\Scripts\\python training\\tune_rules.py --rehab      (also REHAB24-6: hip_abduction,
                                                                           all incorrect reps as positives)

thresholds.json (ai_server/app/pose/) is read by the server at start-up. Report:
training/reports/rule_tuning.json (for Chapter 5).
"""
import json
import sys
from collections import defaultdict
from datetime import datetime

import numpy as np

from common import REPORTS, cached_sequence, own_clips
from app.pose.analyse import detect_reps
from app.pose.exercises import EXERCISES, THRESHOLDS_FILE
from app.pose.geometry import Features
from app.pose.reps import Rep

MIN_PER_CLASS = 5
# A tuned limit replaces the physiotherapy default only if it gains this much balanced accuracy:
# with clips from one person, a default that already scores 96-100% is safer for other people.
MIN_GAIN = 0.05
# Limits reviewed by hand after tuning on Elwin's clips (7 Oct): the tuned value sat at the edge
# of the correct reps, so a value with more margin and nearly the same score is used.
REVIEWED = {
    "shoulder_abduction.bent_elbow": (165, "classes overlap (some 'bent elbow' reps reach 172 deg); 170 would flag "
                                           "normal arms; 165 scores 85%, the trained model handles the rest"),
    "shoulder_flexion.bent_elbow": (160, "94%, same as the tuned 162, rounder and with more margin"),
    "sit_to_stand.incomplete_stand": (170, "98% vs 100% at 174, which is 2 deg below Elwin's own correct reps"),
}


def balanced_accuracy(ok: np.ndarray, bad: np.ndarray, limit: float, above: bool) -> float:
    fire = (lambda v: v > limit) if above else (lambda v: v < limit)
    tpr = float(np.mean(fire(bad))) if len(bad) else 0.0
    tnr = float(np.mean(~fire(ok))) if len(ok) else 0.0
    return (tpr + tnr) / 2


def best_limit(ok: np.ndarray, bad: np.ndarray, above: bool, slack: float = 0.01) -> tuple[float, float]:
    """The limit in the MIDDLE of the best-scoring range (within `slack` of the top score):
    a limit right at the edge of the training reps would fire on the next person's normal
    movement, so keep the widest margin to both groups."""
    values = np.unique(np.concatenate([ok, bad]))
    candidates = (values[:-1] + values[1:]) / 2 if len(values) > 1 else values
    scores = np.array([balanced_accuracy(ok, bad, c, above) for c in candidates])
    i = int(np.argmax(scores))
    lo = hi = i
    while lo > 0 and scores[lo - 1] >= scores[i] - slack:
        lo -= 1
    while hi < len(scores) - 1 and scores[hi + 1] >= scores[i] - slack:
        hi += 1
    limit = (candidates[lo] + candidates[hi]) / 2
    return float(limit), balanced_accuracy(ok, bad, limit, above)


def own_samples():
    """{pose_key: [(features, rep, clip_label, clip_mistake)]}"""
    out = defaultdict(list)
    for clip in own_clips():
        if not clip.name_ok or clip.problems:
            continue
        seq = cached_sequence(clip)
        if seq.detected_ratio < 0.5:
            continue
        spec = EXERCISES[clip.key]
        f = Features(seq)
        reps = [Rep(0, len(f.t) // 2, len(f.t) - 1)] if spec.kind == "hold" else detect_reps(spec, f)
        for r in reps:
            out[clip.key].append((f, r, clip.is_correct, clip.mistake))
    return out


def rehab_samples():
    """REHAB24-6 leg abduction as hip_abduction: correct vs (any) incorrect repetitions."""
    from evaluate_rehab import labelled_reps
    return {"hip_abduction": [(f, r, ok, "*") for f, r, ok in labelled_reps(4)]}


def main():
    samples = own_samples()
    if "--rehab" in sys.argv:
        for k, v in rehab_samples().items():
            samples[k].extend(v)
    if not samples:
        print("No labelled clips yet (training/data/<exercise>/<correct|incorrect>/).")
        return
    report, limits = {}, {}
    for key, items in sorted(samples.items()):
        spec = EXERCISES[key]
        print(f"\n{key}: {sum(1 for i in items if i[2])} correct reps, {sum(1 for i in items if not i[2])} incorrect reps")
        for m in spec.mistakes:
            ok = np.array([m.value(f, r) for f, r, good, _ in items if good])
            bad = np.array([m.value(f, r) for f, r, good, mis in items if not good and mis in (m.label, "*")])
            row = {"rule": m.describe(), "n_correct": len(ok), "n_mistake": len(bad)}
            if len(ok) < MIN_PER_CLASS or len(bad) < MIN_PER_CLASS:
                row["status"] = f"skipped (needs {MIN_PER_CLASS} reps on each side)"
                print(f"   {m.label:22s} skipped: {len(ok)} correct / {len(bad)} mistake reps")
            else:
                before = balanced_accuracy(ok, bad, m.limit, m.above)
                limit, after = best_limit(ok, bad, m.above)
                row.update(current_limit=m.limit, current_balanced_accuracy=round(before, 3),
                           tuned_limit=round(limit, 3), tuned_balanced_accuracy=round(after, 3),
                           median_correct=round(float(np.median(ok)), 3), median_mistake=round(float(np.median(bad)), 3),
                           unit=m.unit)
                name = f"{key}.{m.label}"
                if name in REVIEWED:
                    limits[name] = REVIEWED[name][0]
                    row.update(status="reviewed", used_limit=REVIEWED[name][0], reason=REVIEWED[name][1],
                               used_balanced_accuracy=round(balanced_accuracy(ok, bad, REVIEWED[name][0], m.above), 3))
                elif after >= before + MIN_GAIN:
                    limits[name] = round(limit, 3)
                    row["status"] = "tuned"
                else:
                    row["status"] = "kept"
                print(f"   {m.label:22s} {m.limit:>7g} -> {limit:>7.3g} {m.unit:13s} balanced accuracy "
                      f"{before:.0%} -> {after:.0%}   (median correct {np.median(ok):.3g}, mistake {np.median(bad):.3g})")
            report[f"{key}.{m.label}"] = row
    REPORTS.mkdir(exist_ok=True)
    (REPORTS / "rule_tuning.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"\nReport: {REPORTS / 'rule_tuning.json'}")
    if "--only" in sys.argv:
        keep = set(sys.argv[sys.argv.index("--only") + 1].split(","))
        limits = {k: v for k, v in limits.items() if k in keep}
    if "--write" in sys.argv:
        old = json.loads(THRESHOLDS_FILE.read_text(encoding="utf-8")) if THRESHOLDS_FILE.exists() else {"limits": {}}
        merged = {**old.get("limits", {}), **limits}
        THRESHOLDS_FILE.write_text(json.dumps({
            "limits": merged,
            "tuned_at": datetime.now().isoformat(timespec="seconds"),
            "sources": {**(old.get("sources") if isinstance(old.get("sources"), dict) else
                           {k: old["sources"] for k in old.get("limits", {})} if old.get("sources") else {}),
                        **{k: ("own clips" + (" + REHAB24-6" if "--rehab" in sys.argv else "")
                               + (f"; reviewed: {REVIEWED[k][1]}" if k in REVIEWED else "")) for k in limits}},
        }, indent=2), encoding="utf-8")
        print(f"Wrote {len(limits)} tuned limits to {THRESHOLDS_FILE} (restart the AI server to use them)")
    else:
        print(f"{len(limits)} limits would change. Run with --write to save them.")


if __name__ == "__main__":
    main()
