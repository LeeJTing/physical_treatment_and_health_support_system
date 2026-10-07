"""Which inputs make the trained models carry over to a new person?

Trains each model on Elwin's clips (person p01) only, with different input sets, and scores
  * held-out p01 clips (whole clips held out, original footage only), and
  * the second person's labelled clips (p02, never used for training or tuning the model),
over several random seeds. Writes training/reports/experiment_features.json.

    ai_server\\.venv\\Scripts\\python training\\experiment_features.py [pose_key ...] [--seeds 3]
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np

from common import DATA, REPORTS
from app.pose import exercises
from app.pose.analyse import detect_reps
from app.pose.classifier import FEATURES, build_model, rep_tensor
from app.pose.geometry import Features
from app.pose import landmarks
from train import person_split

# Inputs each exercise's rules actually look at (+ the rep duration, always last).
SUBSETS = {
    "sit_to_stand": ["knee_L", "knee_R", "hip_L", "hip_R", "lean_sagittal", "shin_forward_L", "shin_forward_R",
                     "wrist_thigh_L", "wrist_thigh_R"],
    "shoulder_abduction": ["elbow_L", "elbow_R", "shoulder_elev_L", "shoulder_elev_R", "lean_lateral", "shrug"],
    "shoulder_flexion": ["elbow_L", "elbow_R", "shoulder_elev_L", "shoulder_elev_R", "lean_sagittal", "shrug"],
    "hip_abduction": ["leg_from_down_L", "leg_from_down_R", "knee_L", "knee_R", "lean_lateral",
                      "leg_len_L", "leg_len_R"],
    "knee_extension": ["knee_L", "knee_R", "thigh_from_down_L", "thigh_from_down_R", "hip_L", "hip_R",
                       "lean_sagittal"],
}
# Posture channels that differ between people at rest; "rel" variants subtract the rep's first frame.
RELATIVE = {"lean_sagittal", "lean_lateral", "shrug", "hip_L", "hip_R"}

P02 = Path(__file__).resolve().parent / "data" / "test_p02"   # labels.json + <stem>.npz landmark caches


def columns(names):
    return [FEATURES.index(n) for n in names] + [len(FEATURES)]


def transform(X, names, relative):
    X = X.copy()
    if relative:
        for i, n in enumerate(names):
            if n in RELATIVE:
                X[:, :, i] = X[:, :, i] - X[:, :1, i]
    return X


def fit(X, y, ym, n_mistakes, seed, epochs=300):
    import torch
    from torch import nn
    torch.manual_seed(seed)
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    T = lambda a, d=torch.float32: torch.as_tensor(a, dtype=d, device=dev)  # noqa: E731
    model = build_model(X.shape[2], n_mistakes).to(dev)
    opt = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-4)
    pos = float(y.mean())
    bce = nn.BCEWithLogitsLoss(pos_weight=torch.tensor((1 - pos) / max(pos, 1e-3), device=dev))
    ce = nn.CrossEntropyLoss(ignore_index=-1)
    Xt, yt, mt = T(X), T(y), T(ym, torch.long)
    for _ in range(epochs if len(X) < 5000 else 150):
        model.train()
        perm = torch.randperm(len(Xt), device=dev)
        for i in range(0, len(perm), 32):
            b = perm[i:i + 32]
            opt.zero_grad()
            c, m = model(Xt[b])
            loss = bce(c, yt[b])
            if (mt[b] >= 0).any():
                loss = loss + 0.5 * ce(m, mt[b])
            loss.backward()
            opt.step()
    model.eval()

    def predict(Xn):
        with torch.no_grad():
            return torch.sigmoid(model(T(Xn))[0]).cpu().numpy()
    return predict


def p02_set(key):
    labels = json.loads((P02 / "labels.json").read_text(encoding="utf-8"))
    spec = exercises.get(key)
    X, y, clip = [], [], []
    for stem, (k, label) in labels.items():
        if k != key:
            continue
        f = Features(landmarks.load(P02 / f"{stem}.npz"))
        for r in detect_reps(spec, f):
            X.append(rep_tensor(f, r)); y.append(1 if label == "ok" else 0); clip.append(stem)
    return np.array(X, np.float32), np.array(y), np.array(clip)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("keys", nargs="*", default=["sit_to_stand", "shoulder_abduction", "shoulder_flexion"])
    ap.add_argument("--seeds", type=int, default=3)
    ap.add_argument("--epochs", type=int, default=120)
    a = ap.parse_args()
    out = {}
    for key in a.keys:
        d = dict(np.load(DATA / "datasets" / f"{key}.npz"))
        own = np.char.startswith(d["groups"].astype(str), "own")
        X, y, ym, clips, aug = (d[k][own] for k in ("X", "y_correct", "y_mistake", "clip", "aug"))
        Xp, yp, cp = p02_set(key)
        variants = {"all inputs": (FEATURES, False), "rule inputs": (SUBSETS[key], False),
                    "rule inputs, posture relative": (SUBSETS[key], True)}
        out[key] = {}
        for vname, (names, rel) in variants.items():
            cols = columns(names)
            Xs, Xps = transform(X[:, :, cols], names, rel), transform(Xp[:, :, cols], names, rel) if len(Xp) else Xp
            own_acc, p02_acc, p02_clip = [], [], []
            for seed in range(a.seeds):
                tr, te, _ = person_split(d["groups"][own], y, 0.2, seed, clips, aug)
                pred = fit(Xs[tr], y[tr], ym[tr], len(d["mistakes"]), seed, a.epochs)
                own_acc.append(float(((pred(Xs[te]) >= 0.5) == y[te]).mean()))
                full = fit(Xs, y, ym, len(d["mistakes"]), seed, a.epochs)        # all of p01, tested on p02
                if len(Xps):
                    pp = full(Xps)
                    p02_acc.append(float(((pp >= 0.5) == yp).mean()))
                    right = [((pp[cp == c] >= 0.5).mean() >= 0.5) == bool(yp[cp == c][0]) for c in np.unique(cp)]
                    p02_clip.append(float(np.mean(right)))
            out[key][vname] = {"own_heldout_rep_acc": round(float(np.mean(own_acc)), 3),
                               "p02_rep_acc": round(float(np.mean(p02_acc)), 3) if p02_acc else None,
                               "p02_clip_acc": round(float(np.mean(p02_clip)), 3) if p02_clip else None,
                               "p02_reps": int(len(yp)), "seeds": a.seeds}
            print(f"{key:18s} {vname:30s} own held-out {np.mean(own_acc):.0%}   p02 reps {np.mean(p02_acc) if p02_acc else float('nan'):.0%}"
                  f"  p02 clips {np.mean(p02_clip) if p02_clip else float('nan'):.0%}", flush=True)
    (REPORTS / "experiment_features.json").write_text(json.dumps(out, indent=2), encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
