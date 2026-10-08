"""Tests the wrong-exercise check (app/pose/identity.py).

  1. Elwin's and p02's labelled clips: every clip checked against its own exercise (must be accepted)
     and against the 14 others (should be refused). The 5 "shoulder_flexion ... shoulder_shrug" clips
     actually show arms raised sideways (abduction, checked on frames, 8 Oct) and are reported apart.
  2. Outside data of the right exercise must be accepted (evidence for other people):
     sit2stand.ai home sit-to-stand videos, MobiPhysio one-arm raises (as shoulder abduction),
     IntelliRehabDS Kinect patients (elbow flexion and both-arm forward raises, virtual side camera;
     one-arm abduction, virtual front camera).

    ai_server\\.venv\\Scripts\\python training\\evaluate_identity.py
"""
import json
import re
from collections import Counter, defaultdict

import numpy as np

from common import CACHE, DATA, REPORTS, cached_sequence, own_clips
from app.pose import exercises, landmarks
from app.pose.geometry import Features
from app.pose.identity import check, signature
from evaluate_irds import ROOT as IRDS, read, to_sequence

MISLABELLED = re.compile(r"shoulder_flexion__incorrect__shoulder_shrug")


def main():
    keys = list(exercises.EXERCISES)
    clips = [c for c in own_clips() if c.name_ok and not c.problems]
    own_ok, own_n, wrong_ok, wrong_n = Counter(), Counter(), Counter(), Counter()
    refused_why = defaultdict(Counter)
    leaks = defaultdict(Counter)
    mislabelled = []
    for c in clips:
        sig = signature(Features(cached_sequence(c)))
        if MISLABELLED.search(c.path.name):
            mislabelled.append((c.path.name, check("shoulder_flexion", sig), check("shoulder_abduction", sig)))
            continue
        for k in keys:
            why = check(k, sig)
            if k == c.key:
                own_n[k] += 1
                own_ok[k] += why is None
                if why:
                    refused_why[k][why] += 1
            else:
                wrong_n[c.key] += 1
                if why is None:
                    wrong_ok[c.key] += 1
                    leaks[c.key][k] += 1
    print("== own clips: right exercise accepted | wrong exercises still accepted")
    for k in keys:
        lk = ", ".join(f"{a} {n}" for a, n in leaks[k].most_common()) or "-"
        print(f"  {k:18s} accepted {own_ok[k]:2d}/{own_n[k]:2d}  {dict(refused_why[k]) or ''} | wrong accepted {wrong_ok[k]}/{wrong_n[k]}: {lk}")
    print(f"  total wrong accepted: {sum(wrong_ok.values())}/{sum(wrong_n.values())}")
    print("  mislabelled flexion-shrug clips (really abduction): as flexion / as abduction ->",
          [(a or "accepted", b or "accepted") for _, a, b in mislabelled])

    print("\n== outside data, right exercise (must be accepted)")
    out = {}
    s = json.load(open(REPORTS / "sit2stand_eval.json"))
    res = Counter(check("sit_to_stand", signature(Features(landmarks.load(CACHE / "sit2stand" / f"{r['video']}.npz"))))
                  for r in s["rows"])
    out["sit2stand.ai (sit_to_stand)"] = res
    mob = sorted((CACHE / "mobiphysio").glob("*.npz"))
    res = Counter()
    for p in mob:
        seq = landmarks.load(p)
        if seq.detected_ratio > 0.5:
            res[check("shoulder_abduction", signature(Features(seq)))] += 1
    out["MobiPhysio one-arm raise (shoulder_abduction)"] = res
    for name, gestures, view, key in (("IRDS elbow flexion", {"0", "1"}, "side", "elbow_flexion"),
                                      ("IRDS both arms forward", {"6"}, "side", "shoulder_flexion"),
                                      ("IRDS one-arm abduction", {"4", "5"}, "front", "shoulder_abduction")):
        res = Counter()
        for p in sorted(IRDS.glob("*.txt")):
            parts = p.stem.split("_")
            if len(parts) < 6 or parts[2] not in gestures or parts[4] != "1":
                continue
            pos, vis = read(p)
            if len(pos) >= 10:
                res[check(key, signature(Features(to_sequence(pos, vis, view))))] += 1
        out[f"{name} ({key}, correct reps)"] = res
    for name, res in out.items():
        n = sum(res.values())
        print(f"  {name:48s} accepted {res[None]}/{n}  refused: {dict((k, v) for k, v in res.items() if k)}")
    (REPORTS / "identity_eval.json").write_text(json.dumps(
        {"own_accepted": dict(own_ok), "own_total": dict(own_n), "wrong_accepted": dict(wrong_ok),
         "wrong_total": dict(wrong_n), "leaks": {k: dict(v) for k, v in leaks.items()},
         "outside": {k: {str(a): b for a, b in v.items()} for k, v in out.items()}}, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
