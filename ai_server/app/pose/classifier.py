"""Learned posture classifier for the trained-model exercises (Phase 6).

Input: one repetition as a sequence of joint angles, resampled to SEQ_LEN
steps. Output: probability the repetition is correct, plus the most likely
mistake. Weights live in models/weights/<pose_key>_v<N>.pt (git-ignored);
when none exist the server uses the angle rules alone.
"""
from functools import lru_cache
from pathlib import Path

import numpy as np

from .geometry import Features
from .reps import Rep

WEIGHTS_DIR = Path(__file__).resolve().parents[2] / "models" / "weights"
SEQ_LEN = 48

# Per-frame inputs. Angles are divided by 180; the other series are ratios.
FEATURES = [
    "elbow_L", "elbow_R", "shoulder_elev_L", "shoulder_elev_R", "knee_L", "knee_R", "hip_L", "hip_R",
    "leg_from_down_L", "leg_from_down_R", "thigh_from_down_L", "thigh_from_down_R",
    "lean_sagittal", "lean_lateral", "shin_forward_L", "shin_forward_R",
    "shrug", "heel_lift_L", "heel_lift_R", "wrist_thigh_L", "wrist_thigh_R", "leg_len_L", "leg_len_R",
]
ANGLE_FEATURES = {f for f in FEATURES if not f.startswith(("shrug", "heel_lift", "wrist_thigh", "leg_len"))}

# Inputs each exercise's model reads (8 Oct): only what its rules look at. With one person in the
# training data, the extra series (legs during an arm exercise, and so on) let the model learn
# that person's stance and outfit instead of the movement. Older checkpoints list all FEATURES.
INPUTS = {
    "sit_to_stand": ["knee_L", "knee_R", "hip_L", "hip_R", "lean_sagittal", "shin_forward_L", "shin_forward_R",
                     "wrist_thigh_L", "wrist_thigh_R"],
    "shoulder_abduction": ["elbow_L", "elbow_R", "shoulder_elev_L", "shoulder_elev_R", "lean_lateral", "shrug"],
    "shoulder_flexion": ["elbow_L", "elbow_R", "shoulder_elev_L", "shoulder_elev_R", "lean_sagittal", "shrug"],
    # hip_abduction reads ALL inputs: unlike the arm exercises, every reduced set did worse, both in
    # cross-validation on Elwin's clips (3 fold seeds: all 92.9 %, rule + thigh 90.4 %) and on the
    # REHAB24-6 people doing the same leg raise (balanced accuracy all 60.6 %, rule + thigh 51.8 %;
    # experiment_hip_crossperson.json).
    # + whole-leg angle and length: 88.3 -> 95.5 % (all inputs 94.7 %).
    "knee_extension": ["knee_L", "knee_R", "thigh_from_down_L", "thigh_from_down_R", "hip_L", "hip_R",
                       "lean_sagittal", "leg_from_down_L", "leg_from_down_R", "leg_len_L", "leg_len_R"],
}


def columns(names: list[str]) -> list[int]:
    """Column indices of `names` in a rep_tensor, plus the duration column (always last)."""
    return [FEATURES.index(n) for n in names] + [len(FEATURES)]


def rep_tensor(f: Features, rep: Rep) -> np.ndarray:
    """(SEQ_LEN, len(FEATURES) + 1): the rep resampled to a fixed length, plus its duration."""
    s = rep.slice()
    t = f.t[s]
    grid = np.linspace(t[0], t[-1], SEQ_LEN) if len(t) > 1 else np.full(SEQ_LEN, t[0])
    cols = []
    for name in FEATURES:
        x = f[name][s]
        x = np.interp(grid, t, x) if len(t) > 1 else np.full(SEQ_LEN, x[0])
        cols.append(x / 180.0 if name in ANGLE_FEATURES else np.clip(x, -3, 3))
    duration = float(t[-1] - t[0]) if len(t) > 1 else 0.0
    cols.append(np.full(SEQ_LEN, duration / 10.0))
    return np.stack(cols, axis=1).astype(np.float32)


def build_model(n_features: int, n_mistakes: int, hidden: int = 64):
    import torch
    from torch import nn

    class PostureGRU(nn.Module):
        def __init__(self):
            super().__init__()
            self.gru = nn.GRU(n_features, hidden, batch_first=True, bidirectional=True)
            self.drop = nn.Dropout(0.3)
            self.correct = nn.Linear(4 * hidden, 1)
            self.mistake = nn.Linear(4 * hidden, max(n_mistakes, 1))

        def forward(self, x):
            out, _ = self.gru(x)
            pooled = torch.cat([out.mean(dim=1), out.max(dim=1).values], dim=1)
            z = self.drop(pooled)
            return self.correct(z).squeeze(-1), self.mistake(z)

    return PostureGRU()


def latest_weights(pose_key: str, folder: Path = WEIGHTS_DIR) -> Path | None:
    """The highest <pose_key>_v<N>.pt. Other names that match the pattern (a copy such as
    <pose_key>_v4_backup.pt) are skipped: their int() made every /pose request for the exercise fail
    (audit, 24 Oct)."""
    found = []
    for p in folder.glob(f"{pose_key}_v*.pt"):
        version = p.stem.rsplit("_v", 1)[1]
        if version.isdigit():
            found.append((int(version), p))
    return max(found)[1] if found else None


@lru_cache(maxsize=16)
def _load(path: str):
    import torch

    ckpt = torch.load(path, map_location="cpu", weights_only=False)
    model = build_model(len(ckpt.get("features", FEATURES)) + 1, len(ckpt["mistakes"]))
    model.load_state_dict(ckpt["state"])
    model.eval()
    return model, ckpt


def predict(pose_key: str, f: Features, reps: list[Rep]) -> dict | None:
    """Per-rep probability of correct form and likely mistake, or None if no model is trained yet."""
    path = latest_weights(pose_key)
    if path is None or not reps:
        return None
    import torch

    model, ckpt = _load(str(path))
    cols = columns(ckpt.get("features", FEATURES))
    x = torch.from_numpy(np.stack([rep_tensor(f, r)[:, cols] for r in reps]))
    with torch.no_grad():
        c_logit, m_logit = model(x)
    p_correct = torch.sigmoid(c_logit).numpy().tolist()
    mistakes = ckpt["mistakes"]
    likely = [mistakes[i] if mistakes else None for i in m_logit.argmax(dim=1).tolist()]
    # A repetition slower than any the model learned from (or much quicker) is left to the rules (9 Oct
    # condition audit: at half speed the models failed 26 of 128 correct clips, the rules 1; with this,
    # 124-128 of 128 pass from normal speed to 2.5 times slower).
    lo, hi = ckpt.get("duration_range") or (None, None)
    if lo is not None:
        for i, r in enumerate(reps):
            d = float(f.t[r.end] - f.t[r.start])
            if d > hi or d < lo * 0.75:
                p_correct[i], likely[i] = None, None
    return {"p_correct": p_correct, "likely_mistake": likely, "version": f"{path.stem}"}
