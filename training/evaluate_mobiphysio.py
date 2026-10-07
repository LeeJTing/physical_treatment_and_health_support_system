"""Outside test on MobiPhysio (Harvard Dataverse, CC0, doi:10.7910/DVN/XSI0QN): exercise E01
(shoulder abduction, ONE arm raised overhead), front camera, 51 people, recorded in full / medium /
low light, low / high camera jitter, partial occlusion and low resolution. Three physiotherapists
scored every video (0-100).

Their protocol differs from ours (one arm, raised overhead instead of both arms to shoulder
height), so this checks what carries over:
  * does the pose detector keep track of the person in every recording condition, and are the
    repetitions found;
  * the rules that mean the same in both protocols (elbow straight, no trunk lean, no shoulder
    shrug) on the single-arm variant used for REHAB24-6;
  * does our rules-only score go up and down with the physiotherapists' score (Spearman).

    ai_server\\.venv\\Scripts\\python training\\evaluate_mobiphysio.py [--extract-only]

Landmarks are cached in training/data/cache/mobiphysio. Writes training/reports/mobiphysio_eval.json.
"""
import csv
import json
import sys
from collections import defaultdict

import numpy as np

from common import CACHE, DATA, REPORTS
from app.pose import landmarks
from app.pose.analyse import check_rep
from app.pose.geometry import Features
from app.pose.reps import find_reps
from evaluate_rehab import single_arm_abduction

ROOT = DATA / "public" / "mobiphysio"
VARIATIONS = {"VFL": "full light", "VML": "medium light", "VLL": "low light", "VLJ": "low jitter",
              "VHJ": "high jitter", "VO": "occlusion", "VLR": "low resolution"}
SHARED = ("bent_elbow", "trunk_lean", "shoulder_shrug")   # mean the same with one arm overhead


def physio_scores():
    """{video stem: (average 0-100, [per-judge factor rows])} from the marking sheet."""
    rows = list(csv.reader((ROOT / "Physiotherapist Exercise Marking .csv").open(encoding="utf-8-sig",
                                                                               errors="replace")))
    out, current = {}, None
    for r in rows[2:]:
        if r and r[0].strip():
            current = r[0].strip()
            out[current] = [None, []]
        if current is None or len(r) < 12:
            continue
        try:
            out[current][1].append([float(x) for x in r[2:9]])
        except ValueError:
            pass
        if r[11].strip():
            out[current][0] = float(r[11])
    return {k: (v[0], v[1]) for k, v in out.items() if v[0] is not None}


def load(path):
    cp = CACHE / "mobiphysio" / f"{path.stem}.npz"
    if cp.exists():
        return landmarks.load(cp)
    seq = landmarks.extract(path)
    cp.parent.mkdir(parents=True, exist_ok=True)
    landmarks.save(seq, cp)
    return seq


def spearman(a, b):
    ra, rb = np.argsort(np.argsort(a)), np.argsort(np.argsort(b))
    return float(np.corrcoef(ra, rb)[0, 1]) if len(a) > 2 else float("nan")


def main():
    scores = physio_scores()
    spec = single_arm_abduction()
    videos = sorted((ROOT / "videos").glob("E01_*_AF_*.mp4"))
    if "--cached-only" in sys.argv:          # while the download / extraction is still running
        videos = [v for v in videos if (CACHE / "mobiphysio" / f"{v.stem}.npz").exists()]
    print(f"{len(videos)} videos, {len(scores)} scored")
    per_var = defaultdict(lambda: {"videos": 0, "detected": [], "reps": [], "rule_score": [], "physio": []})
    fired = defaultdict(lambda: [0, 0])
    measures = defaultdict(list)
    rows = []
    for i, path in enumerate(videos, 1):
        var = path.stem.split("_")[3]
        seq = load(path)
        if "--extract-only" in sys.argv:
            print(f"[{i}/{len(videos)}] {path.stem}: person found in {seq.detected_ratio:.0%}", flush=True)
            continue
        v = per_var[var]
        v["videos"] += 1
        v["detected"].append(seq.detected_ratio)
        if seq.detected_ratio < 0.5:
            v["reps"].append(0)
            continue
        f = Features(seq)
        reps = find_reps(spec.signal(f), f.t, spec.rest, spec.active)
        v["reps"].append(len(reps))
        if not reps:
            continue
        rep_scores = []
        for r in reps:
            ms = [m for m in check_rep(spec, f, r) if m in SHARED]
            rep_scores.append(100 - 30 * len(ms))
            for m in spec.mistakes:
                if m.label in SHARED:
                    measures[m.label].append(m.value(f, r))
        score = float(np.mean(rep_scores))
        physio = scores.get(path.stem, (None,))[0]
        if physio is not None:
            v["rule_score"].append(score)
            v["physio"].append(physio)
            rows.append((path.stem, var, len(reps), score, physio))
    if "--extract-only" in sys.argv:
        return
    report = {"videos": len(videos), "per_variation": {}, "shared_rule_measures_p10_p50_p90": {}}
    all_rule, all_phys = [], []
    for var, v in sorted(per_var.items(), key=lambda kv: list(VARIATIONS).index(kv[0])):
        all_rule += v["rule_score"]; all_phys += v["physio"]
        report["per_variation"][VARIATIONS[var]] = {
            "videos": v["videos"],
            "person_found_median": round(float(np.median(v["detected"])), 3) if v["detected"] else None,
            "videos_with_reps": int(sum(1 for n in v["reps"] if n > 0)),
            "reps_median": float(np.median(v["reps"])) if v["reps"] else None,
            "spearman_rule_vs_physio": round(spearman(v["rule_score"], v["physio"]), 3) if len(v["physio"]) > 2 else None,
        }
        r = report["per_variation"][VARIATIONS[var]]
        print(f"{VARIATIONS[var]:15s} {v['videos']:3d} videos  person found {r['person_found_median']}  "
              f"reps found in {r['videos_with_reps']}/{v['videos']} (median {r['reps_median']})  "
              f"Spearman vs physio {r['spearman_rule_vs_physio']}")
    report["spearman_all"] = round(spearman(all_rule, all_phys), 3) if len(all_phys) > 2 else None
    for k, vals in measures.items():
        report["shared_rule_measures_p10_p50_p90"][k] = [round(float(x), 3) for x in np.percentile(vals, [10, 50, 90])]
    print("Spearman (all):", report["spearman_all"])
    print("shared measures p10/p50/p90:", report["shared_rule_measures_p10_p50_p90"])
    report["videos_scored"] = [dict(zip(("video", "variation", "reps", "rule_score", "physio"), r)) for r in rows]
    (REPORTS / "mobiphysio_eval.json").write_text(json.dumps(report, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
