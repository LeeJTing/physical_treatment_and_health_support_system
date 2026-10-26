"""Trains the posture classifier for one exercise on the GPU.

    ai_server\\.venv\\Scripts\\python training\\train.py shoulder_abduction
    ai_server\\.venv\\Scripts\\python training\\train.py --synthetic          (pipeline smoke test)

Splits by PERSON (nobody appears in both train and test), so the test score
shows how the model does on people it has never seen. With few people, also run
cross_validate.py: one held-out pair of people is a noisy estimate. Writes
  ai_server/models/weights/<key>_v<N>.pt            (picked up by /pose automatically)
  training/reports/<key>_v<N>/metrics.json, confusion_matrix.png, loss.png   (for Chapter 5)
"""
import argparse
import json
import time
from datetime import datetime

import numpy as np

from common import DATA, REPORTS
from app.pose.classifier import FEATURES, INPUTS, SEQ_LEN, WEIGHTS_DIR, build_model, columns


def person_split(groups: np.ndarray, y: np.ndarray, test_share: float, seed: int,
                 clips: np.ndarray | None = None, aug: np.ndarray | None = None):
    """Hold out whole people. With fewer than 3 people, hold out whole clips instead (stratified
    by label). Either way a clip and its augmented variants stay on one side, and the held-out
    side keeps only original footage, so the score is never inflated by recoloured copies."""
    rng = np.random.default_rng(seed)
    clips = np.arange(len(y)).astype(str) if clips is None else clips
    aug = np.zeros(len(y), int) if aug is None else aug
    people = np.unique(groups)
    held, kind = None, ""
    if len(people) >= 3:
        for _ in range(200):
            test_people = rng.choice(people, size=max(1, round(len(people) * test_share)), replace=False)
            test = np.isin(groups, test_people)
            if 0 < y[test].sum() < test.sum() and 0 < y[~test].sum() < (~test).sum():
                held, kind = test, "person"
                break
    if held is None:
        names = np.unique(clips)
        label = {c: int(round(y[clips == c].mean())) for c in names}
        chosen = []
        for cls in (0, 1):
            c = rng.permutation([n for n in names if label[n] == cls])
            chosen += list(c[: max(1, round(len(c) * test_share))]) if len(c) > 1 else []
        held, kind = np.isin(clips, chosen), "clip (fewer than 3 people; variants stay with their clip)"
    return ~held, held & (aug == 0), kind


def metrics(y_true: np.ndarray, p: np.ndarray) -> dict:
    pred = (p >= 0.5).astype(int)
    tp = int(((pred == 1) & (y_true == 1)).sum()); tn = int(((pred == 0) & (y_true == 0)).sum())
    fp = int(((pred == 1) & (y_true == 0)).sum()); fn = int(((pred == 0) & (y_true == 1)).sum())
    prec = tp / (tp + fp) if tp + fp else 0.0
    rec = tp / (tp + fn) if tp + fn else 0.0
    return {"accuracy": (tp + tn) / max(len(y_true), 1), "precision": prec, "recall": rec,
            "f1": 2 * prec * rec / (prec + rec) if prec + rec else 0.0,
            "confusion_matrix": {"labels": ["incorrect", "correct"], "rows_true_cols_pred": [[tn, fp], [fn, tp]]}}


def synthetic(n=400, seed=0):
    """Random sequences where 'correct' reps reach a higher peak: proves the loop learns."""
    rng = np.random.default_rng(seed)
    F = len(FEATURES) + 1
    y = rng.integers(0, 2, n)
    t = np.linspace(0, np.pi, SEQ_LEN)
    X = rng.normal(0, 0.05, (n, SEQ_LEN, F)).astype(np.float32)
    X[:, :, 2] += (np.sin(t)[None, :] * (0.3 + 0.2 * y[:, None])).astype(np.float32)
    ym = np.where(y == 0, rng.integers(0, 3, n), -1)
    groups = np.array([f"p{i % 8}" for i in range(n)])
    return X, y, ym, groups, ["m0", "m1", "m2"]


def train(key: str, X, y, ym, groups, mistakes, epochs: int, seed: int = 7, out_name: str | None = None,
          clips=None, aug=None, inputs: list[str] | None = None):
    """inputs: the series the model reads (default all FEATURES); X always holds all of them."""
    inputs = list(inputs or FEATURES)
    X = X[:, :, columns(inputs)]
    import torch
    from torch import nn

    torch.manual_seed(seed)
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    clips = np.arange(len(y)).astype(str) if clips is None else clips
    aug = np.zeros(len(y), int) if aug is None else aug
    tr, te, split_kind = person_split(groups, y, 0.2, seed, clips, aug)
    # Validation for early stopping: a further slice of the training people (or clips).
    tr_idx = np.where(tr)[0]
    va_mask = np.zeros(len(y), bool)
    tr2, va, _ = person_split(groups[tr_idx], y[tr_idx], 0.15, seed + 1, clips[tr_idx], aug[tr_idx])
    va_mask[tr_idx[va]] = True
    tr_mask = tr & ~va_mask & np.isin(np.arange(len(y)), tr_idx[tr2])

    def T(a, dtype=torch.float32):
        return torch.as_tensor(a, dtype=dtype, device=dev)

    Xtr, ytr, mtr = T(X[tr_mask]), T(y[tr_mask]), T(ym[tr_mask], torch.long)
    Xva, yva, mva = T(X[va_mask]), T(y[va_mask]), T(ym[va_mask], torch.long)
    model = build_model(X.shape[2], len(mistakes)).to(dev)
    opt = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-4)
    pos = float(ytr.mean().item()) if len(ytr) else 0.5
    bce = nn.BCEWithLogitsLoss(pos_weight=torch.tensor((1 - pos) / max(pos, 1e-3), device=dev))
    ce = nn.CrossEntropyLoss(ignore_index=-1)

    def loss_of(xb, yb, mb):
        c, m = model(xb)
        loss = bce(c, yb)
        if (mb >= 0).any():
            loss = loss + 0.5 * ce(m, mb)
        return loss

    best, best_state, patience, hist = 1e9, None, 0, {"train": [], "val": []}
    # A validation set of only a few reps is too noisy to stop on (it stopped a REHAB24-6
    # model at a useless point). Then train a fixed 150 epochs with stronger weight decay,
    # the setting that scored F1 0.80 in leave-one-person-out cross-validation.
    small = len(Xva) < 30
    if small:
        epochs = min(epochs, 150)
        for g in opt.param_groups:
            g["weight_decay"] = 1e-3
    t0 = time.time()
    for ep in range(epochs):
        model.train()
        perm = torch.randperm(len(Xtr), device=dev)
        tot = 0.0
        for i in range(0, len(perm), 32):
            b = perm[i:i + 32]
            opt.zero_grad()
            loss = loss_of(Xtr[b], ytr[b], mtr[b])
            loss.backward()
            opt.step()
            tot += loss.item() * len(b)
        model.eval()
        with torch.no_grad():
            vl = loss_of(Xva, yva, mva).item() if len(Xva) else tot / len(Xtr)
        hist["train"].append(tot / len(Xtr)); hist["val"].append(vl)
        if small:
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
            continue
        if vl < best - 1e-4:
            best, patience = vl, 0
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
        else:
            patience += 1
            if patience >= 25:
                break
    model.load_state_dict(best_state)
    model.eval()
    with torch.no_grad():
        c, m = model(T(X[te]))
        p = torch.sigmoid(c).cpu().numpy()
        m_pred = m.argmax(1).cpu().numpy()
    res = metrics(y[te], p)
    known = (ym[te] >= 0)
    res["mistake_type_accuracy"] = float((m_pred[known] == ym[te][known]).mean()) if known.any() else None
    res.update(split=split_kind, stopping="fixed 150 epochs (small validation set)" if small else "early stopping", n_train=int(tr_mask.sum()), n_val=int(va_mask.sum()), n_test=int(te.sum()), n_train_augmented=int((tr_mask & (aug > 0)).sum()),
               people_test=sorted(set(groups[te].tolist())), epochs_run=len(hist["train"]),
               train_seconds=round(time.time() - t0, 1), device=dev)

    WEIGHTS_DIR.mkdir(parents=True, exist_ok=True)
    n = 1 + max([int(p.stem.rsplit("_v", 1)[1]) for p in WEIGHTS_DIR.glob(f"{key}_v*.pt")] or [0])
    name = out_name or f"{key}_v{n}"
    res["inputs"] = inputs
    # How long the training repetitions lasted (the last column is duration / 10 s): the server judges
    # reps far outside this with the rules only (9 Oct condition audit: slow reps of older patients).
    dur = X[tr_mask][:, 0, -1] * 10.0
    res["duration_range_sec"] = [round(float(np.percentile(dur, 1)), 2), round(float(np.percentile(dur, 99)), 2)]
    ckpt = {"state": best_state, "mistakes": list(mistakes), "features": inputs, "seq_len": SEQ_LEN,
            "metrics": res, "duration_range": res["duration_range_sec"],
            "trained_at": datetime.now().isoformat(timespec="seconds")}
    torch.save(ckpt, WEIGHTS_DIR / f"{name}.pt")
    rep_dir = REPORTS / name
    rep_dir.mkdir(parents=True, exist_ok=True)
    (rep_dir / "metrics.json").write_text(json.dumps(res, indent=2), encoding="utf-8")
    plot(rep_dir, hist, res, key)
    return name, res


def plot(rep_dir, hist, res, key):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, ax = plt.subplots(figsize=(6, 4))
    ax.plot(hist["train"], label="training"); ax.plot(hist["val"], label="validation")
    ax.set_xlabel("epoch"); ax.set_ylabel("loss"); ax.set_title(f"{key}: training loss"); ax.legend()
    fig.tight_layout(); fig.savefig(rep_dir / "loss.png", dpi=150); plt.close(fig)

    cm = np.array(res["confusion_matrix"]["rows_true_cols_pred"])
    fig, ax = plt.subplots(figsize=(4.2, 3.8))
    ax.imshow(cm, cmap="Greens")
    for i in range(2):
        for j in range(2):
            ax.text(j, i, str(cm[i, j]), ha="center", va="center", fontsize=14)
    ax.set_xticks([0, 1], ["incorrect", "correct"]); ax.set_yticks([0, 1], ["incorrect", "correct"])
    ax.set_xlabel("predicted"); ax.set_ylabel("actual")
    ax.set_title(f"{key}\naccuracy {res['accuracy']:.0%}, F1 {res['f1']:.2f}")
    fig.tight_layout(); fig.savefig(rep_dir / "confusion_matrix.png", dpi=150); plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("key", nargs="?")
    ap.add_argument("--epochs", type=int, default=300)
    ap.add_argument("--synthetic", action="store_true")
    ap.add_argument("--own-only", action="store_true", help="train on Elwin's recordings only (drop REHAB24-6)")
    ap.add_argument("--all-inputs", action="store_true",
                    help="read every FEATURES series instead of the exercise's INPUTS (the pre-8 Oct models)")
    a = ap.parse_args()
    if a.synthetic:
        X, y, ym, g, mistakes = synthetic()
        name, res = train("synthetic", X, y, ym, g, mistakes, a.epochs, out_name="synthetic_smoke")
        (WEIGHTS_DIR / f"{name}.pt").unlink()  # never shipped
    else:
        d = dict(np.load(DATA / "datasets" / f"{a.key}.npz"))
        if a.own_only:
            keep = np.char.startswith(d["groups"].astype(str), "own")
            for k in ("X", "y_correct", "y_mistake", "groups", "clip", "aug"):
                if k in d:
                    d[k] = d[k][keep]
        name, res = train(a.key, d["X"], d["y_correct"], d["y_mistake"], d["groups"], d["mistakes"].tolist(), a.epochs,
                          clips=d.get("clip"), aug=d.get("aug"),
                          inputs=None if a.all_inputs else INPUTS.get(a.key))
    print(json.dumps({k: v for k, v in res.items() if k != "confusion_matrix"}, indent=2))
    print("confusion matrix [true incorrect, true correct] x [pred incorrect, pred correct]:",
          res["confusion_matrix"]["rows_true_cols_pred"])
    print(f"saved {name}")


if __name__ == "__main__":
    main()
