"""/chat - Rule-Based Chatbot Engine (M500.2). Stub until Phase 5."""
from fastapi import APIRouter, Depends

from ..auth import current_account_id

router = APIRouter(tags=["M500 chat"])


@router.get("/chat/categories")
def categories(plan_id: str | None = None, account_id: str = Depends(current_account_id)):
    return {"stub": True, "plan_id": plan_id, "categories": []}


@router.post("/chat")
def chat(body: dict, account_id: str = Depends(current_account_id)):
    return {"stub": True, "is_matched": False, "category": None, "response": ""}
