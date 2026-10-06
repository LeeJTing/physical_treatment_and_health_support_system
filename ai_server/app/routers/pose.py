"""/pose - Pose Estimation Model (M300.1, FR300_06 to FR300_19).

Multipart upload: `file` (MP4 or MOV, 10-30 s, <= 100 MB, >= 720p) and
`exercise_key` (the exercise's pose_key). The clip is written to a
temporary file, analysed, and deleted; nothing is stored (stateless).

Errors use the shared contract {"error": {"code", "message"}} with HTTP 422:
  invalid_video          format, length, size or resolution not allowed (FR300_14-16)
  unknown_exercise       exercise_key has no posture rules
  pose_not_detected      no person found (FR300_25)
  full_body_not_visible  body parts outside the picture (FR300_17)
  no_repetitions         no complete repetition found (FR300_26)
"""
import os
import tempfile
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, UploadFile
from fastapi.responses import JSONResponse

from ..auth import current_account_id
from ..pose import exercises
from ..pose.analyse import PoseError, analyse
from ..pose.landmarks import extract, read_video_info

router = APIRouter(tags=["M300 posture"])

ALLOWED_EXT = {".mp4", ".mov"}
MAX_BYTES = 100 * 1024 * 1024
MIN_SEC, MAX_SEC, TOLERANCE_SEC = 10.0, 30.0, 0.5
MIN_SHORT_SIDE = 720


def _error(code: str, message: str) -> JSONResponse:
    return JSONResponse(status_code=422, content={"error": {"code": code, "message": message}})


@router.get("/pose/exercises")
def pose_exercises(account_id: str = Depends(current_account_id)):
    """The exercise keys the server can analyse, with their camera view."""
    return {"exercises": [{"key": s.key, "name": s.name, "view": s.view, "kind": s.kind}
                          for s in exercises.EXERCISES.values()]}


@router.post("/pose")
def pose(
    file: UploadFile = File(...),
    exercise_key: str = Form(...),
    account_id: str = Depends(current_account_id),
):
    if exercise_key not in exercises.EXERCISES:
        return _error("unknown_exercise", f"No posture analysis exists for '{exercise_key}'.")
    ext = Path(file.filename or "").suffix.lower()
    if ext not in ALLOWED_EXT:
        return _error("invalid_video", "The video must be an MP4 or MOV file.")

    fd, path = tempfile.mkstemp(suffix=ext)
    try:
        size = 0
        with os.fdopen(fd, "wb") as out:
            while chunk := file.file.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_BYTES:
                    return _error("invalid_video", "The video must be under 100 MB.")
                out.write(chunk)
        try:
            info = read_video_info(path)
        except ValueError:
            return _error("invalid_video", "The video file cannot be opened.")
        if info.frame_count <= 0 or info.fps <= 0:
            return _error("invalid_video", "The video file cannot be opened.")
        if not (MIN_SEC - TOLERANCE_SEC <= info.duration_sec <= MAX_SEC + TOLERANCE_SEC):
            return _error("invalid_video", "The video must be between 10 and 30 seconds long.")
        if min(info.width, info.height) < MIN_SHORT_SIDE:
            return _error("invalid_video", "The video resolution must be at least 720p.")
        try:
            return analyse(exercise_key, extract(path))
        except PoseError as e:
            return _error(e.code, e.message)
    finally:
        try:
            os.remove(path)
        except OSError:
            pass
