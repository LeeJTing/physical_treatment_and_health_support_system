"""Clip-level movement signatures for the wrong-exercise check (8 Oct). Prints, per exercise, the
p5 / p50 / p95 of each signature over Elwin's and p02's labelled clips (correct and incorrect), so the
identity rules in ai_server/app/pose/identity.py can be set from data.

    ai_server\\.venv\\Scripts\\python training\\exercise_signatures.py
"""
from collections import defaultdict

import numpy as np

from common import cached_sequence, own_clips
from app.pose import exercises
from app.pose.geometry import Features
from app.pose.identity import signature


def main():
    by = defaultdict(lambda: defaultdict(list))
    for c in [c for c in own_clips() if c.name_ok and not c.problems]:
        sig = signature(Features(cached_sequence(c)))
        for k, v in sig.items():
            if np.isfinite(v):
                by[c.key][k].append(v)
    names = list(next(iter(by.values())).keys())
    for k in names:
        print(f"\n{k}")
        for ex in exercises.EXERCISES:
            v = by[ex][k]
            if v:
                print(f"   {ex:18s} {np.round(np.percentile(v, [5, 50, 95]), 2)}")


if __name__ == "__main__":
    main()
