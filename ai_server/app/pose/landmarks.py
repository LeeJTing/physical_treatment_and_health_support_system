"""Video -> per-frame body landmarks with MediaPipe Pose Landmarker (FR300_07).

Frames are sampled at `target_fps` (default 10) to keep a 30 s clip near
10 s of processing on the CPU. Landmarks are returned in PIXELS (x, y) so
angles are not distorted by the frame's aspect ratio, plus visibility.
"""
from dataclasses import dataclass, replace
from pathlib import Path

import cv2
import numpy as np

# MediaPipe landmark indices used by the exercises.
NOSE = 0
L_EAR, R_EAR = 7, 8
L_SHOULDER, R_SHOULDER = 11, 12
L_ELBOW, R_ELBOW = 13, 14
L_WRIST, R_WRIST = 15, 16
L_HIP, R_HIP = 23, 24
L_KNEE, R_KNEE = 25, 26
L_ANKLE, R_ANKLE = 27, 28
L_HEEL, R_HEEL = 29, 30
L_FOOT, R_FOOT = 31, 32

DEFAULT_MODEL = Path(__file__).resolve().parents[2] / "models" / "weights" / "pose_landmarker_full.task"
# MediaPipe Hand Landmarker (21 points per hand), only for the wrist and hand exercises (9 Oct).
HAND_MODEL = Path(__file__).resolve().parents[2] / "models" / "weights" / "hand_landmarker.task"
# Hand landmark indices.
H_WRIST, H_THUMB_TIP, H_INDEX_MCP, H_INDEX_TIP, H_MIDDLE_MCP, H_MIDDLE_TIP = 0, 4, 5, 8, 9, 12
H_RING_TIP, H_PINKY_MCP, H_PINKY_TIP = 16, 17, 20


@dataclass
class VideoInfo:
    fps: float
    frame_count: int
    width: int
    height: int

    @property
    def duration_sec(self) -> float:
        return self.frame_count / self.fps if self.fps else 0.0


@dataclass
class PoseSequence:
    """xy: (T, 33, 2) pixels, NaN where no person was found.
    vis: (T, 33) visibility 0..1 (0 where no person). t: (T,) seconds."""
    xy: np.ndarray
    vis: np.ndarray
    t: np.ndarray
    info: VideoInfo
    # (T, 2, 21, 2) pixels for up to two hands, NaN where none; only filled for hand exercises.
    hands: np.ndarray | None = None

    @property
    def fps(self) -> float:
        return 1.0 / float(np.median(np.diff(self.t))) if len(self.t) > 1 else 0.0

    @property
    def detected_ratio(self) -> float:
        return float(np.mean(~np.isnan(self.xy[:, 0, 0]))) if len(self.t) else 0.0


def turned(seq: PoseSequence, deg: float) -> PoseSequence:
    """The points turned deg clockwise about the picture's centre (9 Oct condition audit: a phone tilted
    10 degrees failed 31 % of correct clips; the phone's own tilt sensor tells how far to turn back)."""
    if not deg:
        return seq
    c = np.array([seq.info.width / 2, seq.info.height / 2])
    a = np.radians(deg)
    r = np.array([[np.cos(a), -np.sin(a)], [np.sin(a), np.cos(a)]])
    hands = None if seq.hands is None else ((seq.hands - c) @ r.T + c).astype(np.float32)
    return PoseSequence(xy=((seq.xy - c) @ r.T + c).astype(np.float32), vis=seq.vis, t=seq.t, info=seq.info,
                        hands=hands)


def read_video_info(path: str | Path) -> VideoInfo:
    cap = cv2.VideoCapture(str(path))
    try:
        if not cap.isOpened():
            raise ValueError("The video file cannot be opened.")
        w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
        h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
        # Phones store portrait video as landscape frames plus a rotation tag.
        # OpenCV applies the rotation when reading frames, so report the rotated size.
        if int(cap.get(cv2.CAP_PROP_ORIENTATION_META) or 0) % 180 == 90:
            w, h = h, w
        return VideoInfo(fps=float(cap.get(cv2.CAP_PROP_FPS) or 0.0),
                         frame_count=int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0), width=w, height=h)
    finally:
        cap.release()


def _pad_square(rgb: np.ndarray) -> np.ndarray:
    """Pads the frame on the right or bottom to a square, so landmark x and y stay in pixels of the
    original frame. In VIDEO mode MediaPipe placed the skeleton upside down on some portrait phone
    videos (5 of 377 sit2stand.ai videos, 8 Oct; its log warns that NORM_RECT without image size is
    only supported for a square ROI); the same frames padded to a square came out right."""
    h, w = rgb.shape[:2]
    s = max(h, w)
    out = np.zeros((s, s, 3), dtype=rgb.dtype)
    out[:h, :w] = rgb
    return out


def _make_landmarker(model_path: Path):
    from mediapipe.tasks.python import vision
    from mediapipe.tasks.python.core.base_options import BaseOptions

    options = vision.PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=str(model_path)),
        running_mode=vision.RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=0.5,
        min_pose_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    return vision.PoseLandmarker.create_from_options(options)


def extract(
    path: str | Path,
    target_fps: float = 10.0,
    model_path: Path = DEFAULT_MODEL,
    start_frame: int = 0,
    end_frame: int | None = None,
    transform=None,
) -> PoseSequence:
    """Runs the pose landmarker on every n-th frame of the video.

    start_frame / end_frame (inclusive) limit the work to part of a long
    video, e.g. one labelled repetition of a public dataset.
    transform(frame_bgr) -> frame_bgr is applied to every analysed frame before detection
    (training-time augmentation: recoloured outfit, lighting, mirror...).
    """
    batch = (lambda f: [transform(f)]) if transform is not None else None
    return extract_many(path, 1, batch, target_fps, model_path, start_frame, end_frame)[0]


def extract_with_hands(path: str | Path, target_fps: float = 10.0) -> PoseSequence:
    """The body landmarks plus up to two hands (21 points each) on the same frames, for the wrist and
    hand exercises. Hands are kept in a fixed slot by their image side (slot 0 = the hand further left
    in the picture), so a slot follows the same hand through the clip."""
    import mediapipe as mp
    from mediapipe.tasks.python import vision
    from mediapipe.tasks.python.core.base_options import BaseOptions

    seq = extract(path, target_fps)
    info = read_video_info(path)
    src_fps = info.fps if info.fps > 0 else 30.0
    step = max(1, round(src_fps / target_fps))
    options = vision.HandLandmarkerOptions(base_options=BaseOptions(model_asset_path=str(HAND_MODEL)),
                                           running_mode=vision.RunningMode.VIDEO, num_hands=2,
                                           min_hand_detection_confidence=0.5, min_hand_presence_confidence=0.5,
                                           min_tracking_confidence=0.5)
    out = []
    cap = cv2.VideoCapture(str(path))
    lmk = vision.HandLandmarker.create_from_options(options)
    try:
        idx = 0
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            if idx % step == 0:
                h, w = frame.shape[:2]
                rgb = np.ascontiguousarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
                if h != w:
                    rgb = _pad_square(rgb)
                s = max(h, w)
                res = lmk.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb),
                                           int(round(idx * 1000.0 / src_fps)))
                slots = np.full((2, 21, 2), np.nan)
                found = [np.array([[p.x * s, p.y * s] for p in hand]) for hand in (res.hand_landmarks or [])][:2]
                found.sort(key=lambda a: float(a[H_WRIST, 0]))
                if len(found) == 1:
                    # One hand: slot by which half of the body it is on (left or right of the nose).
                    k = len(out)
                    nose_x = seq.xy[k, 0, 0] if k < len(seq.xy) else np.nan
                    slot = 0 if np.isnan(nose_x) or found[0][H_WRIST, 0] < nose_x else 1
                    slots[slot] = found[0]
                else:
                    for k, a in enumerate(found):
                        slots[k] = a
                out.append(slots)
            idx += 1
    finally:
        lmk.close()
        cap.release()
    hands = np.asarray(out, dtype=np.float32)
    n = len(seq.t)
    if len(hands) < n:
        hands = np.concatenate([hands, np.full((n - len(hands), 2, 21, 2), np.nan, np.float32)])
    seq.hands = hands[:n]
    return seq


def extract_many(
    path: str | Path,
    n: int,
    transform_batch=None,
    target_fps: float = 10.0,
    model_path: Path = DEFAULT_MODEL,
    start_frame: int = 0,
    end_frame: int | None = None,
    pad_square: bool = True,
) -> list[PoseSequence]:
    """Like extract, but transform_batch(frame_bgr) -> n frames, each tracked by its own
    landmarker: the video is decoded once for n augmented versions of it."""
    import mediapipe as mp

    base = read_video_info(path)
    src_fps = base.fps if base.fps > 0 else 30.0
    step = max(1, round(src_fps / target_fps))
    cap = cv2.VideoCapture(str(path))
    landmarkers = [_make_landmarker(model_path) for _ in range(n)]
    infos = [replace(base) for _ in range(n)]
    out = [([], [], []) for _ in range(n)]
    try:
        if start_frame:
            cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
        idx = start_frame
        while True:
            if end_frame is not None and idx > end_frame:
                break
            ok, frame = cap.read()
            if not ok:
                break
            if (idx - start_frame) % step == 0:
                frames = transform_batch(frame) if transform_batch is not None else [frame]
                ts_ms = int(round(idx * 1000.0 / src_fps))
                for k, (fr, lmk, info, (xs, vs, ts)) in enumerate(zip(frames, landmarkers, infos, out)):
                    h, w = fr.shape[:2]
                    info.width, info.height = w, h  # the size actually analysed
                    rgb = np.ascontiguousarray(cv2.cvtColor(fr, cv2.COLOR_BGR2RGB))
                    if pad_square and h != w:
                        rgb = _pad_square(rgb)
                    side_w, side_h = (max(h, w), max(h, w)) if pad_square else (w, h)
                    result = lmk.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), ts_ms)
                    if result.pose_landmarks:
                        lm = result.pose_landmarks[0]
                        xs.append([[p.x * side_w, p.y * side_h] for p in lm])
                        vs.append([float(getattr(p, "visibility", 1.0) or 0.0) for p in lm])
                    else:
                        xs.append(np.full((33, 2), np.nan).tolist())
                        vs.append([0.0] * 33)
                    ts.append(idx / src_fps)
            idx += 1
    finally:
        for lmk in landmarkers:
            lmk.close()
        cap.release()
    return [PoseSequence(xy=np.asarray(xs, dtype=np.float32).reshape(-1, 33, 2),
                         vis=np.asarray(vs, dtype=np.float32).reshape(-1, 33),
                         t=np.asarray(ts, dtype=np.float32), info=info)
            for info, (xs, vs, ts) in zip(infos, out)]


def save(seq: PoseSequence, path: str | Path) -> None:
    i = seq.info
    extra = {"hands": seq.hands} if seq.hands is not None else {}
    np.savez_compressed(path, xy=seq.xy, vis=seq.vis, t=seq.t,
                        info=np.array([i.fps, i.frame_count, i.width, i.height], dtype=np.float64), **extra)


def load(path: str | Path) -> PoseSequence:
    d = np.load(path)
    fps, n, w, h = d["info"].tolist()
    return PoseSequence(xy=d["xy"], vis=d["vis"], t=d["t"], info=VideoInfo(fps, int(n), int(w), int(h)),
                        hands=d["hands"] if "hands" in d.files else None)
