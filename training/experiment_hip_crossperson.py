"""Hip abduction: which model inputs carry over to other people? Train on Elwin's clips only
(person p01, with augmented copies) and score the 10 REHAB24-6 people doing the same side leg
raise, every repetition labelled by a physiotherapist. Several seeds.

    ai_server\\.venv\\Scripts\\python training\\experiment_hip_crossperson.py
"""
import json

import numpy as np

from common import DATA, REPORTS
from app.pose.classifier import FEATURES, INPUTS, columns
from experiment_features import fit

SETS = {
    "all inputs": FEATURES,
    "rule inputs + thigh (current)": INPUTS["hip_abduction"],
    "rule inputs + thigh + hip + trunk": INPUTS["hip_abduction"] + ["hip_L", "hip_R", "lean_sagittal"],
}


def main():
    d = np.load(DATA / "datasets" / "hip_abduction.npz")
    g = d["groups"].astype(str)
    own, pub = np.char.startswith(g, "own"), np.char.startswith(g, "rehab")
    print(f"train: {own.sum()} own reps; test: {pub.sum()} REHAB24-6 reps from {len(np.unique(g[pub]))} people")
    out = {}
    for name, names in SETS.items():
        cols = columns(names)
        accs, bals = [], []
        for seed in range(3):
            pred = fit(d["X"][own][:, :, cols], d["y_correct"][own], d["y_mistake"][own], len(d["mistakes"]), seed, 120)
            p = pred(d["X"][pub][:, :, cols]) >= 0.5
            y = d["y_correct"][pub].astype(bool)
            accs.append(float((p == y).mean()))
            bals.append(float((np.mean(p[y]) + np.mean(~p[~y])) / 2))
        out[name] = {"accuracy": round(float(np.mean(accs)), 3), "balanced_accuracy": round(float(np.mean(bals)), 3)}
        print(f"{name:36s} other people: accuracy {np.mean(accs):.1%}  balanced {np.mean(bals):.1%}", flush=True)
    (REPORTS / "experiment_hip_crossperson.json").write_text(json.dumps(out, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
