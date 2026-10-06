"""/recommend - Hybrid Plan Recommender (M500.1). Stub until Phase 3."""
from fastapi import APIRouter, Depends

from ..auth import current_account_id

router = APIRouter(tags=["M500 planning"])


@router.post("/recommend")
def recommend(body: dict, account_id: str = Depends(current_account_id)):
    return {"stub": True, "ranked": [], "model_version": "stub"}
