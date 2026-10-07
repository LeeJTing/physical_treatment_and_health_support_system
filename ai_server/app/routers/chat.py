"""/chat - Rule-Based Chatbot Engine (M500.2). Rules in app/chat/rules.json, matching in app/chat/engine.py."""
from typing import Literal

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
    rules_version: str


class ChatRequest(BaseModel):
    plan_id: str | None = None
    category: str | None = None
    text: str | None = Field(default=None, max_length=500)
    # From the patient's profile, so the reply can be filtered by health condition (Table 4.2.2).
    conditions: list[str] = Field(default_factory=list)        # e.g. ["HYPERTENSION", "DIABETES"]
    limitations: list[str] = Field(default_factory=list)       # e.g. ["BALANCE_IMPAIRMENT"]
    risk_level: Literal["Low", "Medium", "High"] | None = None
    # The phone's local time and time zone (no GPS): late-night and condition-specific timing advice.
    local_hour: int | None = Field(default=None, ge=0, le=23)
    local_minute: int | None = Field(default=None, ge=0, le=59)
    utc_offset_minutes: int | None = Field(default=None, ge=-840, le=840)
    timezone: str | None = Field(default=None, max_length=64)
    # The rule that answered the previous question, so "how many reps for that one?" continues it.
    previous_category: str | None = Field(default=None, max_length=80)

    @model_validator(mode="after")
    def needs_input(self):
        if not self.category and not (self.text or "").strip():
            raise ValueError("Send a category or a question.")
        return self


class ChatAction(BaseModel):
    key: str        # the app maps it to a screen, e.g. open_reset_password -> Reset password
    label: str      # button text


class ChatResponse(BaseModel):
    answer: str
    category: str | None            # rule that answered; None when not recognised
    title: str | None
    is_matched: bool                # False -> "Question not recognised" (FR500_22)
    matched_by: str | None          # red_flag | category | keyword | similar_question
    follow_ups: list[Category]      # decision-tree options to offer next
    notes: list[str]                # condition-specific safety lines already appended to answer
    categories: list[Category]      # shown again after every reply (FR500_21, FR500_22)
    action: ChatAction | None = None  # optional button under the answer (e.g. "Reset password")
    rules_version: str


@router.get("/chat/categories", response_model=CategoriesResponse)
def categories(plan_id: str | None = None, account_id: str = Depends(current_account_id)):
    """Question categories for the patient's plan (FR500_18)."""
    return {"plan_id": plan_id, "rules_version": engine.rules()["version"],
            "categories": [{"key": c["key"], "title": c["title"]} for c in engine.categories_for(plan_id)]}


@router.post("/chat", response_model=ChatResponse)
def chat(body: ChatRequest, account_id: str = Depends(current_account_id)):
    """Answer a tapped category or a typed question (FR500_19 to FR500_22)."""
    local = (body.local_hour, body.local_minute or 0) if body.local_hour is not None else None
    return engine.reply(body.plan_id, body.category, body.text, body.conditions, body.limitations, body.risk_level,
                        local_time=local, previous_category=body.previous_category)
