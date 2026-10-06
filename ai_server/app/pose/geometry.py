"""Joint angles and body measurements per frame (2D, image pixels, y points down).

Every series is a float array of length T. Gaps where the person was not
found are filled by linear interpolation, then lightly smoothed, so a few
missed frames do not break repetition counting.
"""
import numpy as np

from .landmarks import (
    L_ANKLE, L_ELBOW, L_FOOT, L_HEEL, L_HIP, L_KNEE, L_SHOULDER, L_WRIST, NOSE,
    R_ANKLE, R_ELBOW, R_FOOT, R_HEEL, R_HIP, R_KNEE, R_SHOULDER, R_WRIST, PoseSequence,
)

SIDES = {
    "L": dict(sh=L_SHOULDER, el=L_ELBOW, wr=L_WRIST, hip=L_HIP, kn=L_KNEE, an=L_ANKLE, he=L_HEEL, ft=L_FOOT),
    "R": dict(sh=R_SHOULDER, el=R_ELBOW, wr=R_WRIST, hip=R_HIP, kn=R_KNEE, an=R_ANKLE, he=R_HEEL, ft=R_FOOT),
}
DOWN = np.array([0.0, 1.0])
UP = np.array([0.0, -1.0])


def fill_gaps(x: np.ndarray) -> np.ndarray:
    """Linear interpolation over NaNs along axis 0 (works for (T,) or (T, ...))."""
    x = np.array(x, dtype=np.float64, copy=True)
    flat = x.reshape(len(x), -1)
    idx = np.arange(len(x))
    for j in range(flat.shape[1]):
        col = flat[:, j]
        ok = ~np.isnan(col)
        if ok.sum() == 0:
            continue
        if (~ok).any():
            col[~ok] = np.interp(idx[~ok], idx[ok], col[ok])
    return flat.reshape(x.shape)


def smooth(x: np.ndarray, k: int = 3) -> np.ndarray:
    if len(x) < k or k <= 1:
        return x
    pad = k // 2
    xp = np.pad(x, (pad, pad), mode="edge")
    return np.convolve(xp, np.ones(k) / k, mode="valid")


def angle3(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> np.ndarray:
    """Angle ABC in degrees (180 = straight)."""
    v1, v2 = a - b, c - b
    cos = np.sum(v1 * v2, axis=1) / (np.linalg.norm(v1, axis=1) * np.linalg.norm(v2, axis=1) + 1e-9)
    return np.degrees(np.arccos(np.clip(cos, -1.0, 1.0)))


def angle_to(v: np.ndarray, ref: np.ndarray) -> np.ndarray:
    """Unsigned angle between each vector in v (T, 2) and a reference direction."""
    cos = (v @ ref) / (np.linalg.norm(v, axis=1) + 1e-9)
    return np.degrees(np.arccos(np.clip(cos, -1.0, 1.0)))


def dist(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    return np.linalg.norm(a - b, axis=1)


def point_segment_dist(p: np.ndarray, a: np.ndarray, b: np.ndarray) -> np.ndarray:
    ab = b - a
    t = np.clip(np.sum((p - a) * ab, axis=1) / (np.sum(ab * ab, axis=1) + 1e-9), 0, 1)
    return np.linalg.norm(p - (a + ab * t[:, None]), axis=1)


def signed_line_offset(p: np.ndarray, a: np.ndarray, b: np.ndarray, toward: np.ndarray) -> np.ndarray:
    """Distance of p from line a-b, positive when p lies on the side of `toward` (a unit 2D vector)."""
    ab = b - a
    n = np.stack([-ab[:, 1], ab[:, 0]], axis=1)
    n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-9
    n *= np.sign(n @ toward)[:, None] + (n @ toward == 0)[:, None]
    return np.sum((p - a) * n, axis=1)


class Features:
    """All series an exercise rule may need, computed once per clip."""

    def __init__(self, seq: PoseSequence):
        self.seq = seq
        self.t = seq.t
        xy = fill_gaps(seq.xy)
        self.ok = not np.isnan(xy).any()
        self.xy = np.nan_to_num(xy)
        p = lambda i: self.xy[:, i, :]  # noqa: E731
        s = {k: {n: p(i) for n, i in d.items()} for k, d in SIDES.items()}
        sh_mid = (p(L_SHOULDER) + p(R_SHOULDER)) / 2
        hip_mid = (p(L_HIP) + p(R_HIP)) / 2
        an_mid = (p(L_ANKLE) + p(R_ANKLE)) / 2
        kn_mid = (p(L_KNEE) + p(R_KNEE)) / 2

        self.torso = float(np.median(dist(sh_mid, hip_mid))) or 1.0
        self.shoulder_width = float(np.median(dist(p(L_SHOULDER), p(R_SHOULDER)))) or 1.0
        self.hip_width = float(np.median(dist(p(L_HIP), p(R_HIP)))) or 1.0

        # Facing direction in side views: +1 = the person faces image right.
        toe_dir = np.concatenate([s["L"]["ft"][:, 0] - s["L"]["he"][:, 0], s["R"]["ft"][:, 0] - s["R"]["he"][:, 0]])
        nose_dir = p(NOSE)[:, 0] - sh_mid[:, 0]
        f = np.sign(np.median(toe_dir)) or np.sign(np.median(nose_dir)) or 1.0
        self.facing = float(f)
        fwd = np.array([self.facing, 0.0])

        S = {}
        for k, d in s.items():
            S[f"elbow_{k}"] = angle3(d["sh"], d["el"], d["wr"])
            S[f"shoulder_elev_{k}"] = angle3(d["hip"], d["sh"], d["el"])          # arm vs trunk: 0 down, 90 level
            S[f"knee_{k}"] = angle3(d["hip"], d["kn"], d["an"])
            S[f"hip_{k}"] = angle3(d["sh"], d["hip"], d["kn"])
            S[f"leg_from_down_{k}"] = angle_to(d["an"] - d["hip"], DOWN)         # front view leg raise
            S[f"thigh_from_down_{k}"] = angle_to(d["kn"] - d["hip"], DOWN)        # 0 standing, 90 thigh level
            S[f"arm_from_down_{k}"] = angle_to(d["wr"] - d["sh"], DOWN)            # on all fours: 0 hanging, 90 level
            shin = dist(d["kn"], d["an"])
            S[f"heel_lift_{k}"] = (d["ft"][:, 1] - d["he"][:, 1]) / (np.median(shin) + 1e-9)
            S[f"shin_forward_{k}"] = np.degrees(np.arctan2((d["an"][:, 0] - d["kn"][:, 0]) * self.facing,
                                                           d["an"][:, 1] - d["kn"][:, 1]))
            S[f"leg_len_{k}"] = dist(d["hip"], d["an"]) / (np.median(dist(d["hip"], d["an"])) + 1e-9)
            S[f"foot_turn_{k}"] = np.abs(d["ft"][:, 0] - d["he"][:, 0]) / (np.median(shin) + 1e-9)
            S[f"wrist_thigh_{k}"] = np.minimum(
                point_segment_dist(d["wr"], s["L"]["hip"], s["L"]["kn"]),
                point_segment_dist(d["wr"], s["R"]["hip"], s["R"]["kn"])) / self.torso

        trunk = sh_mid - hip_mid
        lean = angle_to(trunk, UP)
        S["lean_sagittal"] = lean * np.sign(trunk[:, 0] * self.facing + 1e-9)      # + forward, - backward
        S["lean_lateral"] = lean                                                  # front view: any side
        S["trunk_from_horizontal"] = 90 - angle_to(trunk, UP)                      # all fours: 0 = level
        S["shrug"] = (sh_mid[:, 1] - p(NOSE)[:, 1]) / self.shoulder_width          # smaller = shoulders up
        S["feet_gap"] = np.abs(p(L_ANKLE)[:, 0] - p(R_ANKLE)[:, 0]) / self.hip_width
        S["hip_sway"] = (hip_mid[:, 0] - np.median(hip_mid[:, 0])) / self.torso
        S["hip_rise"] = (np.median(hip_mid[:, 1]) - hip_mid[:, 1]) / self.torso      # + when hips go up
        S["body_line_ankle"] = signed_line_offset(hip_mid, sh_mid, an_mid, fwd) / self.torso
        S["bridge_line"] = signed_line_offset(hip_mid, sh_mid, kn_mid, UP) / self.torso

        self.s = {k: smooth(v) for k, v in S.items()}

    def __getitem__(self, key: str) -> np.ndarray:
        return self.s[key]

    def both(self, name: str, how: str = "max") -> np.ndarray:
        a, b = self.s[f"{name}_L"], self.s[f"{name}_R"]
        return np.maximum(a, b) if how == "max" else np.minimum(a, b) if how == "min" else (a + b) / 2

    def visible(self, required: list[int], min_vis: float = 0.5, margin: float = 0.02) -> np.ndarray:
        """Per frame: are all required landmarks detected and inside the picture? (FR300_17)"""
        seq = self.seq
        w, h = seq.info.width or 1, seq.info.height or 1
        pts = seq.xy[:, required, :]
        inside = ((pts[..., 0] >= -margin * w) & (pts[..., 0] <= (1 + margin) * w)
                  & (pts[..., 1] >= -margin * h) & (pts[..., 1] <= (1 + margin) * h))
        return np.all((seq.vis[:, required] >= min_vis) & inside & ~np.isnan(pts[..., 0]), axis=1)
