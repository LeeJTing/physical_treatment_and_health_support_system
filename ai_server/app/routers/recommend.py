"""/recommend - Hybrid Plan Recommender (M500.1). Algorithm in app/recommend/engine.py."""
from fastapi import APIRouter, Depends

from ..auth import current_account_id
from ..recommend.engine import recommend as run_recommender
from ..recommend.schemas import RecommendRequest, RecommendResponse

router = APIRouter(tags=["M500 planning"])


@router.post("/recommend", response_model=RecommendResponse)
def recommend(body: RecommendRequest, account_id: str = Depends(current_account_id)):
    return run_recommender(body)
