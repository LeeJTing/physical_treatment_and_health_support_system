"""Rule-based chatbot (FR500_17 to FR500_22)."""
import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.chat import engine
from app.main import app

client = TestClient(app)
DEV = {"Authorization": "Bearer dev-token"}
CATALOGUE = json.loads((Path(__file__).parents[2] / "assets" / "seed" / "catalogue.json").read_text(encoding="utf-8"))
KNEE = next(p for p in CATALOGUE["plans"] if p["plan_name"] == "Early Knee Recovery")


def ask(text=None, category=None, plan_id=KNEE["plan_id"]):
    r = client.post("/chat", headers=DEV, json={"plan_id": plan_id, "category": category, "text": text})
    assert r.status_code == 200, r.text
    return r.json()


def test_categories_general_plan_and_unknown():
    assert len(client.get("/chat/categories", headers=DEV).json()["categories"]) == 6
    assert len(client.get("/chat/categories", params={"plan_id": KNEE["plan_id"]}, headers=DEV).json()["categories"]) == 8
    assert len(client.get("/chat/categories", params={"plan_id": "nope"}, headers=DEV).json()["categories"]) == 6


def test_category_tap_returns_its_answer():
    res = ask(category="missed_session")
    assert res["is_matched"] and res["category"] == "missed_session" and "next session" in res["answer"]


def test_plan_answer_lists_the_plans_own_exercises():
    res = ask(category="plan_exercises")
    for pe in KNEE["plan_exercise"]:
        assert pe["exercise"]["exercise_name"] in res["answer"]
    assert f"{KNEE['frequency_per_week']} times a week" in res["answer"]


@pytest.mark.parametrize("question, expected", [
    ("my knee hurts after the exercise", "pain_or_discomfort"),
    ("How often should I do this?", "how_often"),
    ("what equipment do I need", "equipment"),
    ("I forgot to exercise yesterday", "missed_session"),
    ("which exercises are in my plan", "plan_exercises"),
    ("when will I see results", "plan_progress"),
    ("how do i do the excercises correctly", "how_to"),          # typo
    ("is it normall to be sore", "pain_or_discomfort"),          # typo
    ("hw ofen shuld i exersise", "how_often"),                   # several typos
])
def test_questions_match(question, expected):
    res = ask(text=question)
    assert res["is_matched"] and res["category"] == expected, res


@pytest.mark.parametrize("question", ["what is the capital of France", "tell me a joke", "what is the weather today"])
def test_unrelated_question_is_not_recognised(question):
    res = ask(text=question)
    assert not res["is_matched"] and res["category"] is None
    assert res["answer"] == "The question is not recognised, please try asking other question."
    assert len(res["categories"]) == 8                           # FR500_22: show the categories again


def test_red_flag_always_wins():
    res = ask(text="I have chest pain", category="how_often")
    assert res["category"] == "safety" and "999" in res["answer"]
    assert "999" in ask(text="I feel dizzy and might faint")["answer"]

@pytest.mark.parametrize("text", ["my chest pian is bad", "CHEST PAIN while doing step ups", "i feel feint",
                                  "i cant breath", "I'm breathless", "my knee is badly swollen"])
def test_red_flags_with_typos_and_variants(text):
    assert ask(text=text)["category"] == "safety"


def test_request_validation():
    assert client.post("/chat", headers=DEV, json={}).status_code == 422
    assert client.post("/chat", headers=DEV, json={"text": "x" * 501}).status_code == 422
    assert client.post("/chat", json={"text": "hi"}).status_code == 401


def test_rules_file_matches_catalogue():
    rules = engine.rules()
    assert set(rules["plans"]) == {p["plan_id"] for p in CATALOGUE["plans"]}
    for cat in engine.categories_for(KNEE["plan_id"]):
        assert cat["keywords"] and cat["examples"] and cat["answer"]
