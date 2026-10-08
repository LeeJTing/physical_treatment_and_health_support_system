"""Outside test on IntelliRehabDS (Miron et al., Data 2021; Zenodo 4610859, CC BY 4.0): 29 people,
15 of them rehabilitation patients (some seated or in a wheelchair), Kinect v2 skeletons, every
repetition marked correct or incorrect by two raters. No ordinary video is released, so each 3D
skeleton is turned into our 33 landmarks and seen from a virtual camera: from the side for elbow
flexion and shoulder flexion (our camera position), from the front for shoulder abduction.

Gestures (read from the joint motion, see the 8 Oct log): 0 / 1 elbow flexion right / left,
2 / 3 shoulder flexion right / left, 4 / 5 shoulder abduction right / left, 6 both arms raised
forwards, 7 / 8 side taps. Tested: 0+1 -> elbow_flexion, 6 -> shoulder_flexion (both arms, as ours),
4+5 -> shoulder abduction with one arm (the REHAB24-6 variant: uneven_arms dropped).

Each file is one repetition. It is called incorrect when a rule fires, or when no repetition is
found (the app then says it saw no full repetition).

    ai_server\\.venv\\Scripts\\python training\\evaluate_irds.py

Writes training/reports/irds_eval.json.
"""
import json
import re
from collections import defaultdict

import numpy as np

from common import DATA, REPORTS
from app.pose import exercises
from app.pose.analyse import check_rep
from app.pose.geometry import Features
from app.pose.landmarks import PoseSequence, VideoInfo
from app.pose.reps import find_reps
from evaluate_rehab import single_arm_abduction

ROOT = DATA / "public" / "irds" / "SkeletonData" / "RawData"
JOINT = re.compile(r"\((\w+),(\w+),([-\d.eE]+),([-\d.eE]+),([-\d.eE]+),[-\d.eE]+,[-\d.eE]+\)")
# MediaPipe index -> Kinect joint
MAP = {0: "Head", **{i: "Head" for i in range(1, 11)}, 11: "ShoulderLeft", 12: "ShoulderRight",
       13: "ElbowLeft", 14: "ElbowRight", 15: "WristLeft", 16: "WristRight", 17: "HandLeft", 18: "HandRight",
       19: "HandTipLeft", 20: "HandTipRight", 21: "ThumbLeft", 22: "ThumbRight", 23: "HipLeft", 24: "HipRight",
       25: "KneeLeft", 26: "KneeRight", 27: "AnkleLeft", 28: "AnkleRight", 29: "AnkleLeft", 30: "AnkleRight",
       31: "FootLeft", 32: "FootRight"}
TRACKED = {"Tracked": 1.0, "Inferred": 0.6, "NotTracked": 0.1}
SCALE = 400.0          # pixels per metre on the virtual camera
TESTS = {"elbow_flexion": ({"0", "1"}, "side"), "shoulder_flexion": ({"6"}, "side"),
         "shoulder_abduction_1arm": ({"4", "5"}, "front")}


def read(path) -> tuple[np.ndarray, np.ndarray]:
    pos, vis = [], []
    for line in path.open():
        m = JOINT.findall(line)
        if len(m) != 25:
            continue
        j = {n: (np.array([float(x), float(y), float(z)]), TRACKED.get(s, 0.5)) for n, s, x, y, z in m}
        pos.append([j[MAP[i]][0] for i in range(33)])
        vis.append([j[MAP[i]][1] for i in range(33)])
    return np.asarray(pos), np.asarray(vis)


def to_sequence(pos: np.ndarray, vis: np.ndarray, view: str) -> PoseSequence:
    """Virtual camera: side view looks along the person's left-right axis (image x = depth),
    front view looks at them (image x = Kinect x). Image y points down."""
    u = pos[..., 2] if view == "side" else -pos[..., 0]
    v = -pos[..., 1]
    u = (u - np.nanmin(u)) * SCALE + 100
    v = (v - np.nanmin(v)) * SCALE + 100
    xy = np.stack([u, v], axis=-1).astype(np.float32)
    w, h = int(np.nanmax(u)) + 100, int(np.nanmax(v)) + 100
    t = np.arange(len(pos), dtype=np.float32) / 30.0
    return PoseSequence(xy=xy, vis=vis.astype(np.float32), t=t, info=VideoInfo(30.0, len(pos), w, h))


def main():
    specs = {"elbow_flexion": exercises.EXERCISES["elbow_flexion"],
             "shoulder_flexion": exercises.EXERCISES["shoulder_flexion"],
             "shoulder_abduction_1arm": single_arm_abduction()}
    files = sorted(ROOT.glob("*.txt"))
    report = {}
    for name, (gestures, view) in TESTS.items():
        spec = specs[name]
        labels = [m.label for m in spec.mistakes]
        conf = [[0, 0], [0, 0]]                     # rows true incorrect/correct, cols called incorrect/correct
        fires = {"correct": defaultdict(int), "incorrect": defaultdict(int)}
        measures = {"correct": defaultdict(list), "incorrect": defaultdict(list)}
        counts = {"correct": 0, "incorrect": 0}
        no_rep = {"correct": 0, "incorrect": 0}
        for scale_name, scale in (("full", 1.0),):
            for p in files:
                parts = p.stem.split("_")
                if len(parts) < 6 or parts[2] not in gestures or parts[4] not in ("1", "2"):
                    continue
                truth = "correct" if parts[4] == "1" else "incorrect"
                pos, vis = read(p)
                if len(pos) < 10:
                    continue
                f = Features(to_sequence(pos, vis, view))
                counts[truth] += 1
                reps = find_reps(spec.signal(f), f.t, spec.rest, spec.active)
                if not reps:
                    no_rep[truth] += 1
                    conf[0 if truth == "incorrect" else 1][0] += 1
                    continue
                r = max(reps, key=lambda x: x.end - x.start)
                ms = check_rep(spec, f, r, scale)
                for m in ms:
                    fires[truth][m] += 1
                for m in spec.mistakes:
                    measures[truth][m.label].append(m.value(f, r))
                conf[0 if truth == "incorrect" else 1][0 if ms else 1] += 1
        n = sum(map(sum, conf))
        sens = conf[0][0] / max(sum(conf[0]), 1)
        spec_ = conf[1][1] / max(sum(conf[1]), 1)
        report[name] = {
            "gestures": sorted(gestures), "view": view, "repetitions": counts, "no_repetition_found": no_rep,
            "confusion_rows_true_incorrect_correct_cols_called_incorrect_correct": conf,
            "accuracy": round((conf[0][0] + conf[1][1]) / n, 3) if n else None,
            "incorrect_caught": round(sens, 3), "correct_passed": round(spec_, 3),
            "balanced_accuracy": round((sens + spec_) / 2, 3),
            "rule_fires_correct_vs_incorrect": {k: [fires["correct"][k], fires["incorrect"][k]] for k in labels},
            "measure_p10_p50_p90_correct_vs_incorrect": {
                k: [[round(float(x), 3) for x in np.percentile(measures[q][k], [10, 50, 90])] if measures[q][k] else None
                    for q in ("correct", "incorrect")] for k in labels},
            "limits": {m.label: m.limit for m in spec.mistakes},
        }
        r = report[name]
        print(f"== {name} (gestures {sorted(gestures)}, {view} view): correct {counts['correct']}, incorrect {counts['incorrect']}")
        print(f"   no rep found: correct {no_rep['correct']}, incorrect {no_rep['incorrect']}")
        print(f"   incorrect caught {sens:.0%}, correct passed {spec_:.0%}, balanced {r['balanced_accuracy']:.0%}")
        for k in labels:
            c, i = r["rule_fires_correct_vs_incorrect"][k]
            mc, mi = r["measure_p10_p50_p90_correct_vs_incorrect"][k]
            print(f"   {k:16s} fires correct {c:3d} incorrect {i:3d}  limit {r['limits'][k]}  measure correct {mc}  incorrect {mi}")
    (REPORTS / "irds_eval.json").write_text(json.dumps(report, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
