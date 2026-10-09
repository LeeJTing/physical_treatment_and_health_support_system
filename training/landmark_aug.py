"""Landmark-level copies of a recorded clip (9 Oct, condition audit): the same movement done slower, or
seen by a phone that is not held quite straight. Unlike augment.py (video pixels: outfits, rooms,
light), these change only the timing or the camera roll, so the labels stay true:

  * slower (x1.6, x2.2): older patients move slowly, and the trained models had learned Elwin's own
    pace (half-speed correct reps: 102/128 passed with the models, 127/128 with the rules alone);
    never for speed mistakes (a slowed "swinging" repetition is no longer swinging);
  * tilted: a phone propped against something (audit only; see COPIES).

Used by build_dataset.py (aug codes 101, 102) and audit_conditions.py.
"""
import numpy as np

from app.pose.landmarks import PoseSequence, VideoInfo

SPEED_MISTAKES = {"swinging", "uncontrolled_sit", "no_hold", "drop_down"}
# Tilted copies (codes 111/112, +-6 deg) were tried and left out: they cost shoulder abduction 5 points
# in cross-validation (79 -> 74 %), because lean is measured from the picture's vertical and a tilted
# correct clip teaches the model that leaning is fine. The phone's tilt sensor is the fix for tilt
# (routers/pose.py upright_turn_deg).
COPIES = {101: ("slower", 1.6), 102: ("slower", 2.2)}


def _seq(s: PoseSequence, xy, vis=None, t=None) -> PoseSequence:
    t = s.t if t is None else t
    return PoseSequence(xy=np.asarray(xy, np.float32), vis=np.asarray(s.vis if vis is None else vis, np.float32),
                        t=np.asarray(t, np.float32), info=VideoInfo(s.info.fps, len(t), s.info.width, s.info.height))


def retimed(s: PoseSequence, k: float) -> PoseSequence:
    """The same movement k times as long (k > 1 slower), sampled again at the clip's own rate."""
    t_new = np.arange(0, s.t[-1] * k, np.median(np.diff(s.t)))
    src = t_new / k
    xy = np.full((len(t_new), 33, 2), np.nan)
    for j in range(33):
        for d in range(2):
            col = s.xy[:, j, d]
            ok = np.isfinite(col)
            if ok.sum() > 1:
                xy[:, j, d] = np.interp(src, s.t[ok], col[ok])
    vis = np.stack([np.interp(src, s.t, s.vis[:, j]) for j in range(33)], axis=1)
    return _seq(s, xy, vis, t_new)


def tilted(s: PoseSequence, deg: float) -> PoseSequence:
    """The picture turned by deg about its centre (a phone not held upright)."""
    c = np.array([s.info.width / 2, s.info.height / 2])
    a = np.radians(deg)
    r = np.array([[np.cos(a), -np.sin(a)], [np.sin(a), np.cos(a)]])
    return _seq(s, (s.xy - c) @ r.T + c)


def copies(s: PoseSequence, mistake: str):
    """(aug code, sequence) for every landmark-level copy that keeps the clip's label."""
    for code, (kind, v) in COPIES.items():
        if kind == "slower":
            if mistake in SPEED_MISTAKES:
                continue
            yield code, retimed(s, v)
        else:
            yield code, tilted(s, v)
