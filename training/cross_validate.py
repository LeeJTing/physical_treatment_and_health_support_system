"""Leave-one-person-out cross-validation: a fairer score than a single train/test split when
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


def logistic_cv(X, y, groups):
    from sklearn.linear_model import LogisticRegression
    from sklearn.pipeline import make_pipeline
    from sklearn.preprocessing import StandardScaler

    F = summary_features(X)
    p = np.zeros(len(y))
    for person in np.unique(groups):
        test = groups == person
        if len(np.unique(y[~test])) < 2:
            p[test] = y[~test].mean()
            continue
        clf = make_pipeline(StandardScaler(), LogisticRegression(C=0.5, max_iter=2000, class_weight="balanced"))
        clf.fit(F[~test], y[~test])
        p[test] = clf.predict_proba(F[test])[:, 1]
    return p


def gru_cv(X, y, ym, groups, mistakes, epochs=150):
    import torch
    from app.pose.classifier import build_model

    dev = "cuda" if torch.cuda.is_available() else "cpu"
    p = np.zeros(len(y))
    for person in np.unique(groups):
        test = groups == person
        torch.manual_seed(0)
        model = build_model(X.shape[2], len(mistakes)).to(dev)
        opt = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-3)
        Xtr = torch.as_tensor(X[~test], device=dev)
        ytr = torch.as_tensor(y[~test], dtype=torch.float32, device=dev)
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
    print(f"{key}: {len(y)} reps, {len(np.unique(groups))} people, {int(y.sum())} correct / {int(len(y) - y.sum())} incorrect")
    results = {}
    results["logistic regression"] = metrics(y, logistic_cv(X, y, groups))
    if "--rules-only" not in sys.argv:
        results["GRU"] = metrics(y, gru_cv(X, y, ym, groups, d["mistakes"].tolist()))
    for name, m in results.items():
        print(f"  {name:20s} accuracy {m['accuracy']:.0%}  precision {m['precision']:.2f}  recall {m['recall']:.2f}  "
              f"F1 {m['f1']:.2f}  confusion {m['confusion_matrix']['rows_true_cols_pred']}")
    REPORTS.mkdir(exist_ok=True)
    (REPORTS / f"cv_{key}.json").write_text(json.dumps(
        {"method": "leave-one-person-out", "reps": int(len(y)), "people": int(len(np.unique(groups))), "results": results},
        indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
