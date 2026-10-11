"""Adds the training repetitions' duration range to model checkpoints trained before 9 Oct, so the server
can leave much slower or quicker repetitions to the rules (classifier.predict; condition audit).

The range is the 1st-99th percentile of the original (not augmented) repetitions of Elwin's and p02's
clips in the exercise's current dataset: the two-arm, two-leg movement the app asks for (REHAB24-6's
one-arm raises last up to 8 s and would hide a slowed own repetition).

    ai_server\\.venv\\Scripts\\python training\\add_duration_range.py [pose_key ...]
"""
import sys

import numpy as np
import torch

from common import DATA
from app.pose.classifier import WEIGHTS_DIR, latest_weights


def main():
    keys = sys.argv[1:] or ["sit_to_stand", "shoulder_abduction", "shoulder_flexion", "hip_abduction",
                            "knee_extension"]
    for key in keys:
        path = latest_weights(key)
        if path is None:
            continue
        ckpt = torch.load(path, map_location="cpu", weights_only=False)
        if ckpt.get("duration_range"):
            print(f"{path.name}: already has {ckpt['duration_range']}")
            continue
        d = np.load(DATA / "datasets" / f"{key}.npz")
        own = (d["aug"] == 0) & np.char.startswith(d["groups"].astype(str), "own")
        dur = d["X"][own][:, 0, -1] * 10.0
        ckpt["duration_range"] = [round(float(np.percentile(dur, 1)), 2), round(float(np.percentile(dur, 99)), 2)]
        torch.save(ckpt, WEIGHTS_DIR / path.name)
        print(f"{path.name}: duration range {ckpt['duration_range']} s")


if __name__ == "__main__":
    main()
