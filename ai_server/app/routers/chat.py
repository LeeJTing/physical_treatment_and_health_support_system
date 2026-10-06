"""/chat - Rule-Based Chatbot Engine (M500.2). Matching in app/chat/engine.py."""
from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field, model_validator

from ..auth import current_account_id
from ..chat import engine

router = APIRouter(tags=["M500 chat"])


class Category(BaseModel):
    key: str
    title: str


class CategoriesResponse(BaseModel):
    plan_id: str | None
    categories: list[Category]


class ChatRequest(BaseModel):
    plan_id: str | None = None
    category: str | None = None
    text: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def needs_input(self):
        if not self.category and not (self.text or "").strip():
            raise ValueError("Send a category or a question.")
        return self


class ChatResponse(BaseModel):
    answer: str
    category: str | None
    is_matched: bool
    categories: list[Category]


@router.get("/chat/categories", response_model=CategoriesResponse)
def categories(plan_id: str | None = None, account_id: str = Depends(current_account_id)):
    """Question categories for the patient's plan (FR500_18)."""
    return {"plan_id": plan_id, "categories": [{"key": c["key"], "title": c["title"]}
                                               for c in engine.categories_for(plan_id)]}


@router.post("/chat", response_model=ChatResponse)
def chat(body: ChatRequest, account_id: str = Depends(current_account_id)):
    """Answer a tapped category or a typed question (FR500_19 to FR500_22)."""
    return engine.reply(body.plan_id, body.category, body.text)
