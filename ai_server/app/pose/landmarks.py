"""Video -> per-frame body landmarks with MediaPipe Pose Landmarker (FR300_07).

Frames are sampled at `target_fps` (default 10) to keep a 30 s clip near
10 s of processing on the CPU. Landmarks are returned in PIXELS (x, y) so
angles are not distorted by the frame's aspect ratio, plus visibility.
"""
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

# MediaPipe landmark indices used by the exercises.
NOSE = 0
L_SHOULDER, R_SHOULDER = 11, 12
L_ELBOW, R_ELBOW = 13, 14
L_WRIST, R_WRIST = 15, 16
L_HIP, R_HIP = 23, 24
L_KNEE, R_KNEE = 25, 26
L_ANKLE, R_ANKLE = 27, 28
L_HEEL, R_HEEL = 29, 30
L_FOOT, R_FOOT = 31, 32

DEFAULT_MODEL = Path(__file__).resolve().parents[2] / "models" / "weights" / "pose_landmarker_full.task"


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

    @property
    def fps(self) -> float:
        return 1.0 / float(np.median(np.diff(self.t))) if len(self.t) > 1 else 0.0

    @property
    def detected_ratio(self) -> float:
        return float(np.mean(~np.isnan(self.xy[:, 0, 0]))) if len(self.t) else 0.0


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
) -> PoseSequence:
    """Runs the pose landmarker on every n-th frame of the video.

    start_frame / end_frame (inclusive) limit the work to part of a long
    video, e.g. one labelled repetition of a public dataset.
    """
    import mediapipe as mp

    info = read_video_info(path)
    src_fps = info.fps if info.fps > 0 else 30.0
    step = max(1, round(src_fps / target_fps))
    cap = cv2.VideoCapture(str(path))
    landmarker = _make_landmarker(model_path)
    xs, vs, ts = [], [], []
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
                h, w = frame.shape[:2]
                info.width, info.height = w, h  # the size actually analysed
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
                ts_ms = int(round(idx * 1000.0 / src_fps))
                result = landmarker.detect_for_video(image, ts_ms)
                if result.pose_landmarks:
                    lm = result.pose_landmarks[0]
                    xs.append([[p.x * w, p.y * h] for p in lm])
                    vs.append([float(getattr(p, "visibility", 1.0) or 0.0) for p in lm])
                else:
                    xs.append(np.full((33, 2), np.nan).tolist())
                    vs.append([0.0] * 33)
                ts.append(idx / src_fps)
            idx += 1
    finally:
        landmarker.close()
        cap.release()
    xy = np.asarray(xs, dtype=np.float32).reshape(-1, 33, 2)
    return PoseSequence(xy=xy, vis=np.asarray(vs, dtype=np.float32).reshape(-1, 33), t=np.asarray(ts, dtype=np.float32), info=info)


def save(seq: PoseSequence, path: str | Path) -> None:
    i = seq.info
    np.savez_compressed(path, xy=seq.xy, vis=seq.vis, t=seq.t,
                        info=np.array([i.fps, i.frame_count, i.width, i.height], dtype=np.float64))


def load(path: str | Path) -> PoseSequence:
    d = np.load(path)
    fps, n, w, h = d["info"].tolist()
    return PoseSequence(xy=d["xy"], vis=d["vis"], t=d["t"], info=VideoInfo(fps, int(n), int(w), int(h)))
