"""Short follow-ups continue the previous answer (chat-rules-3.53; tests/chat_followup_set.py).
A sample of the generated pairs, so the suite stays quick; evaluate_chat_followups.py runs them all."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_followup_set import CONTROLS, FOLLOW_UPS, NO_CONTEXT, variants  # noqa: E402
from chat_round1_set import KNEE  # noqa: E402

from app.chat import engine  # noqa: E402

BY_KEY = {i["key"]: i for i in engine.intents_for(KNEE)}
TOPICS = [k for k in BY_KEY if k != "clarify"] + ["red_flag", "crisis", "overdose", "poisoning"]
SAMPLE_TOPICS = ["exercise:heel_raise", "exercise:glute_bridge", "plan_exercises", "pain_or_discomfort",
                 "posture_result", "delete_account", "risk_level", "mistake:low_range", "red_flag", "crisis"]


def category(text, previous):
    r = engine.reply(KNEE, None, text, previous_category=previous)
    return r["category"] if r["is_matched"] else None


def expected(text, previous):
    if previous in NO_CONTEXT:
        return {"clarify"} | engine.NO_CONTEXT_ANSWERS     # nothing to continue: ask, or a question of its own
    return {previous}


@pytest.mark.parametrize("previous", SAMPLE_TOPICS)
def test_every_follow_up_continues_the_topic(previous):
    wrong = [(q, g) for q in FOLLOW_UPS if (g := category(q, previous)) not in expected(q, previous)]
    assert not wrong, wrong


@pytest.mark.parametrize("follow_up", ["how to", "why", "more", "how many", "is it safe", "kenapa", "macam mana"])
def test_every_topic_continues(follow_up):
    wrong = [(p, g) for p in TOPICS if (g := category(follow_up, p)) not in expected(follow_up, p)]
    assert not wrong, wrong


@pytest.mark.parametrize("previous", ["exercise:heel_raise", "delete_account", None])
def test_messy_follow_ups(previous):
    qs = sorted({v for q in FOLLOW_UPS for v in variants(q)} - {"and the"})   # "and the": too ambiguous
    wrong = [(q, g) for q in qs if (g := category(q, previous)) not in expected(q, previous)]
    assert len(wrong) == 0, wrong[:20]


@pytest.mark.parametrize("previous", SAMPLE_TOPICS + [None, "thanks"])
def test_a_question_with_its_own_topic_is_not_taken_over(previous):
    wrong = [(q, want, g) for q, want in CONTROLS if (g := category(q, previous)) != want]
    assert not wrong, wrong


def test_the_api_takes_previous_category():
    from fastapi.testclient import TestClient
    from app.main import app
    r = TestClient(app).post("/chat", headers={"Authorization": "Bearer dev-token"},
                             json={"plan_id": KNEE, "text": "how to", "previous_category": "exercise:heel_raise"})
    assert r.status_code == 200 and r.json()["category"] == "exercise:heel_raise"
    assert r.json()["matched_by"] == "follow_up"


def test_what_else_and_is_it_serious_continue_the_answer():
    # 3.94: after an answer, "what else?", "is it serious?", "should i worry?" continue it
    from app.chat import engine as e
    plan = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"
    for prev in ["pain_or_discomfort", "cramp", "sleep"]:
        for text in ["what else?", "is it serious?", "should i worry", "anything else"]:
            assert e.reply(plan, None, text, previous_category=prev)["category"] == prev, (prev, text)
    x = e.reply(plan, None, "why?", previous_category="word_meaning")
    assert "Which word" in x["answer"]
