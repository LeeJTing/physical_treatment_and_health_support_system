"""/chat - Rule-Based Chatbot Engine (M500.2). Rules in app/chat/rules.json, matching in app/chat/engine.py."""
import unicodedata
from typing import Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field, field_validator, model_validator

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


MAX_TEXT = 500                    # characters as the app's text box counts them (chat_view.dart)


def visible_length(text: str) -> int:
    """Characters as a person sees them: "👍🏽", "❤️", "1️⃣" and "👨‍👩‍👧‍👦" are one each, though Python counts
    2-11 code points (skin tones, joiners, variation selectors, a flag's two letters)."""
    n, joined = 0.0, False
    for ch in text:
        if joined:
            joined = False                             # joined to the one before by a zero-width joiner
            continue
        if ch == "‍":
            joined = True
            continue
        if unicodedata.category(ch) in ("Mn", "Me", "Cf") or 0x1F3FB <= ord(ch) <= 0x1F3FF:
            continue                                   # joins or changes the character before it
        n += 0.5 if 0x1F1E6 <= ord(ch) <= 0x1F1FF else 1   # a flag is two regional letters
    return int(n + 0.5)


class ChatRequest(BaseModel):
    plan_id: str | None = None
    category: str | None = None
    # 500 visible characters (an emoji is one, as in the app); at most 6 000 code points in all.
    text: str | None = Field(default=None, max_length=6000)
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
    # From the recommender's response (3.49): AGE_65_PLUS = plans are paused (Terms of Use, section 2).
    restriction: Literal["AGE_65_PLUS"] | None = None

    @field_validator("text")
    @classmethod
    def at_most_500_characters(cls, v: str | None) -> str | None:
        if v is not None and visible_length(v) > MAX_TEXT:
            raise ValueError(f"A question can be at most {MAX_TEXT} characters.")
        return v

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
    # Every button, first = action (3.48: a second one when the answer names a second screen).
    # Older apps read only "action".
    actions: list[ChatAction] = []
    rules_version: str


@router.get("/chat/categories", response_model=CategoriesResponse)
def categories(plan_id: str | None = None, restriction: Literal["AGE_65_PLUS"] | None = None,
               account_id: str = Depends(current_account_id)):
    """Question categories for the patient's plan (FR500_18); restricted users get no plan topics."""
    return {"plan_id": plan_id, "rules_version": engine.rules()["version"],
            "categories": [{"key": c["key"], "title": c["title"]}
                           for c in engine.categories_for(plan_id, restriction)]}


@router.post("/chat", response_model=ChatResponse)
def chat(body: ChatRequest, account_id: str = Depends(current_account_id)):
    """Answer a tapped category or a typed question (FR500_19 to FR500_22)."""
    local = (body.local_hour, body.local_minute or 0) if body.local_hour is not None else None
    res = engine.reply(body.plan_id, body.category, body.text, body.conditions, body.limitations, body.risk_level,
                       local_time=local, previous_category=body.previous_category, restriction=body.restriction)
    res["actions"] = [a for a in [res.get("action"), *res.pop("more_actions", [])] if a]
    return res
