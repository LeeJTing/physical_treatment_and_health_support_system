"""Cross-validated GRU accuracy (own clips, whole clips held out, original footage scored) for
different input sets of one exercise. Used to choose classifier.INPUTS where the second person
has no clips (hip abduction, knee extension).

    ai_server\\.venv\\Scripts\\python training\\experiment_inputs_cv.py hip_abduction knee_extension
"""
import json
import sys

import numpy as np

from common import DATA, REPORTS
from app.pose.classifier import FEATURES, INPUTS, columns
from cross_validate import folds, gru_cv
from train import metrics

EXTRA = {
    "hip_abduction": {
        "rule inputs + hip and trunk": INPUTS["hip_abduction"] + ["hip_L", "hip_R", "lean_sagittal"],
        "rule inputs + thigh": INPUTS["hip_abduction"] + ["thigh_from_down_L", "thigh_from_down_R"],
    },
    "knee_extension": {
        "rule inputs + shin": INPUTS["knee_extension"] + ["shin_forward_L", "shin_forward_R"],
        "rule inputs + legs": INPUTS["knee_extension"] + ["leg_from_down_L", "leg_from_down_R", "leg_len_L",
                                                         "leg_len_R"],
    },
}


def main():
    out = {}
    for key in sys.argv[1:]:
        d = np.load(DATA / "datasets" / f"{key}.npz")
        own = np.char.startswith(d["groups"].astype(str), "own")
        X, y, ym, groups = d["X"][own], d["y_correct"][own], d["y_mistake"][own], d["groups"][own]
        clips, aug = d["clip"][own], d["aug"][own]
        splits, method = folds(y, groups, clips, aug)
        orig = aug == 0
        variants = {"all inputs": FEATURES, "rule inputs": INPUTS[key], **EXTRA.get(key, {})}
        out[key] = {}
        for name, names in variants.items():
            p = gru_cv(X[:, :, columns(names)], y, ym, splits, d["mistakes"].tolist())
            m = metrics(y[orig], p[orig])
            out[key][name] = {"accuracy": round(m["accuracy"], 3), "f1": round(m["f1"], 3), "inputs": names}
            print(f"{key:15s} {name:30s} accuracy {m['accuracy']:.1%}  F1 {m['f1']:.3f}  ({method})", flush=True)
    (REPORTS / "experiment_inputs_cv.json").write_text(json.dumps(out, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
