"""Checks the posture rules on real people: REHAB24-6, where a physiotherapist labelled every
repetition correct or incorrect.

  Ex1 arm abduction (ONE arm)  -> shoulder_abduction rules, single-arm variant (no uneven_arms)
  Ex4 leg abduction            -> hip_abduction rules

For each video seen from the front: are the repetitions counted correctly, and does the rules'
verdict on each labelled repetition agree with the physiotherapist? Also prints the measured
angles of correct vs incorrect repetitions, which is where the thresholds should sit.

    ai_server\\.venv\\Scripts\\python training\\evaluate_rehab.py [--extract-only]

Writes training/reports/rehab24_rules.json. Landmarks are cached in training/data/cache/rehab24_6.
"""
import csv
import json
import sys
from collections import defaultdict
from dataclasses import replace

import numpy as np

from common import CACHE, DATA, REPORTS
from app.pose import landmarks
from app.pose.analyse import check_rep
from app.pose.exercises import EXERCISES, arm_elev_max, peak_of
from app.pose.geometry import Features
from app.pose.reps import Rep, find_reps
from train import metrics

REHAB = DATA / "public" / "rehab24_6"


def single_arm_abduction():
    """REHAB24-6 raises one arm: measure the moving arm, and drop the both-arms rule."""
    spec = EXERCISES["shoulder_abduction"]
    keep = []
    for m in spec.mistakes:
        if m.label == "uneven_arms":
            continue
        if m.label == "low_range":
            m = replace(m, measure=peak_of(arm_elev_max))
        keep.append(m)
    return replace(spec, key="shoulder_abduction_1arm", signal=arm_elev_max, mistakes=keep)


SPECS = {1: single_arm_abduction(), 4: EXERCISES["hip_abduction"]}


def front_camera(orientation: str) -> str | None:
    # cam18 is at 90 degrees to cam17: cam17 "front" => use Camera17; cam17 "side" => Camera18 sees the front.
    return {"front": "Camera17", "side": "Camera18"}.get(orientation)


def video_path(vid: str, cam: str, ex: int):
    hits = sorted((REHAB / "videos" / f"Ex{ex}").glob(f"{vid}-{cam}*.mp4"))
    return hits[0] if hits else None


def load(vid, cam, ex):
    cp = CACHE / "rehab24_6" / f"{vid}_{cam}.npz"
    if cp.exists():
        return landmarks.load(cp)
    path = video_path(vid, cam, ex)
    if path is None:
        return None
    seq = landmarks.extract(path)
    cp.parent.mkdir(parents=True, exist_ok=True)
    landmarks.save(seq, cp)
    return seq


def labelled_reps(ex: int):
    """[(features, rep, correct)] for every front-view labelled repetition of REHAB24-6 exercise `ex`."""
    rows = list(csv.DictReader((REHAB / "Segmentation.csv").open(encoding="utf-8"), delimiter=";"))
    spec = SPECS[ex]
    by_video = defaultdict(list)
    for r in rows:
        cam = front_camera(r["cam17_orientation"])
        if int(r["exercise_id"]) == ex and cam:
            by_video[(r["video_id"], cam)].append(r)
    out = []
    for (vid, cam), reps in sorted(by_video.items()):
        seq = load(vid, cam, ex)
        if seq is None or seq.detected_ratio < 0.5:
            continue
        f = Features(seq)
        fps = seq.info.fps or 30.0
        sig = spec.signal(f)
        for r in reps:
            idx = np.where((f.t >= int(r["first_frame"]) / fps) & (f.t <= int(r["last_frame"]) / fps))[0]
            if len(idx) >= 4:
                out.append((f, Rep(int(idx[0]), int(idx[np.argmax(sig[idx])]), int(idx[-1])), r["correctness"] == "1"))
    return out


def main():
    rows = list(csv.DictReader((REHAB / "Segmentation.csv").open(encoding="utf-8"), delimiter=";"))
    videos = defaultdict(list)
    for r in rows:
        ex = int(r["exercise_id"])
        cam = front_camera(r["cam17_orientation"])
        if ex in SPECS and cam:
            videos[(ex, r["video_id"], cam)].append(r)
    print(f"{len(videos)} front-view videos, {sum(map(len, videos.values()))} labelled repetitions")

    report = {}
    for ex, spec in SPECS.items():
        y, p, counts, angles = [], [], [], {"correct": [], "incorrect": []}
        fired = defaultdict(lambda: [0, 0])          # label -> [on correct reps, on incorrect reps]
        n_label = {"correct": 0, "incorrect": 0}
        items = sorted(k for k in videos if k[0] == ex)
        for i, (_, vid, cam) in enumerate(items, 1):
            print(f"  Ex{ex} [{i}/{len(items)}] {vid} {cam}", flush=True)
            seq = load(vid, cam, ex)
            if "--extract-only" in sys.argv or seq is None or seq.detected_ratio < 0.5:
                continue
            f = Features(seq)
            fps = seq.info.fps or 30.0
            labelled = videos[(ex, vid, cam)]
            counts.append((len(find_reps(spec.signal(f), f.t, spec.rest, spec.active)), len(labelled)))
            sig = spec.signal(f)
            for r in labelled:
                t0, t1 = int(r["first_frame"]) / fps, int(r["last_frame"]) / fps
                idx = np.where((f.t >= t0) & (f.t <= t1))[0]
                if len(idx) < 4:
                    continue
                peak = int(idx[np.argmax(sig[idx])])
                rep = Rep(start=int(idx[0]), peak=peak, end=int(idx[-1]))
                mistakes = check_rep(spec, f, rep)
                correct = r["correctness"] == "1"
                kind = "correct" if correct else "incorrect"
                n_label[kind] += 1
                y.append(int(correct))
                p.append(float(not mistakes))
                angles[kind].append(float(sig[peak]))
                for m in mistakes:
                    fired[m][0 if correct else 1] += 1
        if "--extract-only" in sys.argv or not y:
            continue
        m = metrics(np.array(y), np.array(p))
        exact = sum(1 for a, b in counts if a == b)
        within1 = sum(1 for a, b in counts if abs(a - b) <= 1)
        q = lambda v: [round(float(x), 1) for x in np.percentile(v, [10, 50, 90])] if v else []  # noqa: E731
        m.update({
            "exercise": spec.key, "videos": len(counts), "labelled_reps": len(y),
            "rep_count_exact": f"{exact}/{len(counts)}", "rep_count_within_1": f"{within1}/{len(counts)}",
            "peak_signal_p10_p50_p90": {"correct": q(angles["correct"]), "incorrect": q(angles["incorrect"])},
            "mistake_fired_on": {k: {"correct_reps": f"{v[0]}/{n_label['correct']}",
                                     "incorrect_reps": f"{v[1]}/{n_label['incorrect']}"} for k, v in fired.items()},
        })
        report[f"Ex{ex}"] = m
        print(f"\nEx{ex} -> {spec.key}: {len(y)} reps, rules agree with physiotherapist {m['accuracy']:.0%} "
              f"(precision {m['precision']:.2f}, recall {m['recall']:.2f}, F1 {m['f1']:.2f})")
        print(f"   confusion [true incorrect, true correct] x [pred incorrect, pred correct]: "
              f"{m['confusion_matrix']['rows_true_cols_pred']}")
        print(f"   rep count exact {m['rep_count_exact']}, within 1: {m['rep_count_within_1']}")
        print(f"   peak signal p10/p50/p90: correct {q(angles['correct'])}, incorrect {q(angles['incorrect'])}")
        for k, v in m["mistake_fired_on"].items():
            print(f"   {k:20s} fired on correct {v['correct_reps']:>8s}   on incorrect {v['incorrect_reps']:>8s}")
        reps_ = labelled_reps(ex)
        for mk in spec.mistakes:
            ok = [mk.value(f, r) for f, r, c in reps_ if c]
            bad = [mk.value(f, r) for f, r, c in reps_ if not c]
            print(f"   {mk.label:20s} measured p10/p50/p90  correct {q(ok)}  incorrect {q(bad)}  ({mk.describe()})")
    if report:
        REPORTS.mkdir(exist_ok=True)
        (REPORTS / "rehab24_rules.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(f"\nWritten {REPORTS / 'rehab24_rules.json'}")


if __name__ == "__main__":
    main()
