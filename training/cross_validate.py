"""Leave-one-person-out cross-validation (or, with fewer than 3 people, 5-fold leave-clips-out:
each clip and its augmented variants are held out together, and only original footage is
scored): a fairer score than a single train/test split when
there are only a few people. Each person is held out once; the model is trained on everyone
else and tested on that person. Compares

  * the angle rules (no training; current limits in ai_server/app/pose),
  * logistic regression on summary features of each repetition (min, max, mean, range of
    every angle; a classic small-data baseline),
  * the GRU sequence model used by the server.

    ai_server\\.venv\\Scripts\\python training\\cross_validate.py hip_abduction [--rules-only]

Needs training/data/datasets/<key>.npz from build_dataset.py. Writes training/reports/cv_<key>.json.
"""
import json
import sys

import numpy as np

from common import DATA, REPORTS
from train import metrics


def summary_features(X: np.ndarray) -> np.ndarray:
    return np.concatenate([X.min(1), X.max(1), X.mean(1), X.max(1) - X.min(1)], axis=1)


def folds(y, groups, clips, aug, k=5, seed=0):
    """(train, test) masks. Units are people, or clips when there are fewer than 3 people."""
    people = np.unique(groups)
    if len(people) >= 3:
        return [(groups != g, (groups == g) & (aug == 0)) for g in people], "leave-one-person-out"
    rng = np.random.default_rng(seed)
    names = np.unique(clips)
    fold_of = {}
    for cls in (0, 1):                       # stratified: each fold gets its share of each label
        cs = rng.permutation([c for c in names if round(y[clips == c].mean()) == cls])
        fold_of.update({c: i % k for i, c in enumerate(cs)})
    f = np.array([fold_of[c] for c in clips])
    return [(f != i, (f == i) & (aug == 0)) for i in range(k)], f"{k}-fold, whole clips held out (fewer than 3 people)"


def logistic_cv(X, y, splits):
    from sklearn.linear_model import LogisticRegression
    from sklearn.pipeline import make_pipeline
    from sklearn.preprocessing import StandardScaler

    F = summary_features(X)
    p = np.full(len(y), np.nan)
    for train, test in splits:
        if len(np.unique(y[train])) < 2:
            p[test] = y[train].mean()
            continue
        clf = make_pipeline(StandardScaler(), LogisticRegression(C=0.5, max_iter=2000, class_weight="balanced"))
        clf.fit(F[train], y[train])
        p[test] = clf.predict_proba(F[test])[:, 1]
    return p


def gru_cv(X, y, ym, splits, mistakes, epochs=150):
    import torch
    from app.pose.classifier import build_model

    dev = "cuda" if torch.cuda.is_available() else "cpu"
    p = np.full(len(y), np.nan)
    for train, test in splits:
        torch.manual_seed(0)
        model = build_model(X.shape[2], len(mistakes)).to(dev)
        opt = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-3)
        Xtr = torch.as_tensor(X[train], device=dev)
        ytr = torch.as_tensor(y[train], dtype=torch.float32, device=dev)
        pos = float(ytr.mean())
        loss_fn = torch.nn.BCEWithLogitsLoss(pos_weight=torch.tensor((1 - pos) / max(pos, 1e-3), device=dev))
        for _ in range(epochs):                      # fixed epochs: no validation set to spare
            model.train()
            perm = torch.randperm(len(Xtr), device=dev)
            for i in range(0, len(perm), 16):
                b = perm[i:i + 16]
                opt.zero_grad()
                c, _ = model(Xtr[b])
                loss_fn(c, ytr[b]).backward()
                opt.step()
        model.eval()
        with torch.no_grad():
            c, _ = model(torch.as_tensor(X[test], device=dev))
            p[test] = torch.sigmoid(c).cpu().numpy()
    return p


def main():
    key = sys.argv[1]
    d = np.load(DATA / "datasets" / f"{key}.npz")
    X, y, ym, groups = d["X"], d["y_correct"], d["y_mistake"], d["groups"]
    clips = d["clip"] if "clip" in d else np.arange(len(y)).astype(str)
    aug = d["aug"] if "aug" in d else np.zeros(len(y), int)
    if "--own-only" in sys.argv:             # only Elwin's recordings (drops REHAB24-6 people)
        keep = np.char.startswith(groups.astype(str), "own")
        X, y, ym, groups, clips, aug = X[keep], y[keep], ym[keep], groups[keep], clips[keep], aug[keep]
    if "--rule-inputs" in sys.argv:          # the model reads only what the exercise's rules look at
        from app.pose.classifier import INPUTS, columns
        X = X[:, :, columns(INPUTS[key])]
    if "--no-aug" in sys.argv:               # same folds, augmented copies left out of training
        keep = aug == 0
        X, y, ym, groups, clips, aug = X[keep], y[keep], ym[keep], groups[keep], clips[keep], aug[keep]
    if "--no-landmark-aug" in sys.argv:      # same folds, the slower / tilted copies (codes >= 100) left out
        keep = aug < 100
        X, y, ym, groups, clips, aug = X[keep], y[keep], ym[keep], groups[keep], clips[keep], aug[keep]
    orig = aug == 0
    splits, method = folds(y, groups, clips, aug)
    print(f"{key}: {int(orig.sum())} original reps (+{int((~orig).sum())} augmented), {len(np.unique(groups))} people, "
          f"{len(np.unique(clips))} clips, {int(y[orig].sum())} correct / {int((1 - y[orig]).sum())} incorrect; {method}")
    results = {}
    results["logistic regression"] = metrics(y[orig], logistic_cv(X, y, splits)[orig])
    if "--rules-only" not in sys.argv:
        results["GRU"] = metrics(y[orig], gru_cv(X, y, ym, splits, d["mistakes"].tolist())[orig])
    for name, m in results.items():
        print(f"  {name:20s} accuracy {m['accuracy']:.0%}  precision {m['precision']:.2f}  recall {m['recall']:.2f}  "
              f"F1 {m['f1']:.2f}  confusion {m['confusion_matrix']['rows_true_cols_pred']}")
    REPORTS.mkdir(exist_ok=True)
    tag = ("_own" if "--own-only" in sys.argv else "") + ("_noaug" if "--no-aug" in sys.argv else "") +         ("_ruleinputs" if "--rule-inputs" in sys.argv else "") + ("_nolmaug" if "--no-landmark-aug" in sys.argv else "")
    (REPORTS / f"cv_{key}{tag}.json").write_text(json.dumps(
        {"method": method, "reps_scored": int(orig.sum()), "reps_augmented_in_training": int((~orig).sum()),
         "people": int(len(np.unique(groups))), "clips": int(len(np.unique(clips))), "results": results},
        indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
