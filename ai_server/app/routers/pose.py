"""/pose - Pose Estimation Model (M300.1). Stub until Phase 6."""
from fastapi import APIRouter, Depends, File, Form, UploadFile

from ..auth import current_account_id

router = APIRouter(tags=["M300 posture"])


@router.post("/pose")
async def pose(
    file: UploadFile = File(...),
    exercise_key: str = Form(...),
    account_id: str = Depends(current_account_id),
):
    await file.read(1)  # touch the upload so the contract is exercised
    return {
        "stub": True,
        "pose_detected": False,
        "full_body_visible": False,
        "accuracy": 0.0,
        "repetitions": 0,
        "feedback": [],
        "model_version": "stub",
    }
