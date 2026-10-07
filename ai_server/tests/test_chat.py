"""Rule-based chatbot (FR500_17 to FR500_23; Table 4.2.2: reply filtered by health condition).

Every question in the four question sets is a regression test, plus behaviour tests for the
decision-tree follow-ups, condition tailoring, red flags, negation and the request contract.
"""
import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.chat import engine
from app.main import app
from chat_eval_set import EVAL
from chat_final_set import FINAL
from chat_holdout_set import CORE, HOLDOUT, KNEE
from chat_verify_set import VERIFY

client = TestClient(app)
DEV = {"Authorization": "Bearer dev-token"}
CATALOGUE = json.loads((Path(__file__).parents[2] / "assets" / "seed" / "catalogue.json").read_text(encoding="utf-8"))
KNEE_PLAN = next(p for p in CATALOGUE["plans"] if p["plan_id"] == KNEE)
NOT_RECOGNISED = "The question is not recognised, please try asking other question."

ALL_QUESTIONS = [(KNEE, q, e) for q, e in EVAL] + list(HOLDOUT) + list(VERIFY) + list(FINAL)


def ask(text=None, category=None, plan_id=KNEE, **profile):
    r = client.post("/chat", headers=DEV, json={"plan_id": plan_id, "category": category, "text": text, **profile})
    assert r.status_code == 200, r.text
    return r.json()


# ---- every question in the four sets ----------------------------------------

@pytest.mark.parametrize("plan, question, expected", ALL_QUESTIONS, ids=[q[:40] for _, q, _ in ALL_QUESTIONS])
def test_question_sets(plan, question, expected):
    got = engine.reply(plan, None, question)["category"]
    assert (got in expected) if isinstance(expected, tuple) else (got == expected), got


# ---- categories (FR500_18) ----------------------------------------------------

def test_categories_are_plan_specific():
    cats = client.get("/chat/categories", params={"plan_id": KNEE}, headers=DEV).json()
    keys = [c["key"] for c in cats["categories"]]
    assert keys[:2] == ["plan_exercises", "plan_progress"]
    in_plan = {f"exercise:{pe['exercise']['pose_key']}" for pe in KNEE_PLAN["plan_exercise"]}
    assert in_plan <= set(keys)                                         # its own exercises are listed
    assert "exercise:bird_dog" not in keys                              # other plans' exercises are not
    assert "greeting" not in keys and "pain_mild" not in keys            # hidden rules are not listed
    assert cats["rules_version"].startswith("chat-rules-")


def test_categories_without_plan_are_general_only():
    keys = [c["key"] for c in client.get("/chat/categories", headers=DEV).json()["categories"]]
    assert "plan_exercises" not in keys and not any(k.startswith("exercise:") for k in keys)
    assert {"how_to", "pain_or_discomfort", "safety", "recording_help"} <= set(keys)


def test_every_shown_category_answers_when_tapped():
    for c in engine.categories_for(KNEE):
        res = ask(category=c["key"])
        assert res["is_matched"] and res["category"] == c["key"] and res["answer"]


# ---- answers ------------------------------------------------------------------

def test_plan_answer_lists_the_plans_own_exercises_in_order():
    res = ask(category="plan_exercises")
    names = [pe["exercise"]["exercise_name"] for pe in sorted(KNEE_PLAN["plan_exercise"], key=lambda e: e["sequence_order"])]
    positions = [res["answer"].index(n) for n in names]
    assert positions == sorted(positions)
    assert f"{KNEE_PLAN['frequency_per_week']} times a week" in res["answer"]


def test_exercise_answer_says_whether_it_is_in_the_plan():
    assert "In your plan this is exercise" in ask(text="how do I do heel raises")["answer"]
    assert "not part of your current plan" in ask(text="how do I do the bird dog")["answer"]
    assert "In your plan" in ask(text="how do I do the bird dog", plan_id=CORE)["answer"]


def test_pain_offers_decision_tree_follow_ups():
    res = ask(text="my knee hurts")
    assert [f["key"] for f in res["follow_ups"]] == ["pain_mild", "pain_sharp", "pain_swelling"]
    sharp = ask(category="pain_sharp")
    assert sharp["is_matched"] and "Stop the exercise" in sharp["answer"]


def test_unrecognised_shows_message_and_categories_again():
    res = ask(text="what is the capital of France")
    assert not res["is_matched"] and res["category"] is None and res["answer"] == NOT_RECOGNISED
    assert len(res["categories"]) == len(engine.categories_for(KNEE))     # FR500_22


def test_answers_stay_within_scope():
    assert "cannot give advice about medicines" in ask(text="can I take panadol")["answer"]
    assert "cannot diagnose" in ask(text="is my knee broken")["answer"]


# ---- reply filtered by health condition (Table 4.2.2) -------------------------

def test_profile_conditions_add_safety_notes():
    plain = ask(text="is it safe for me to exercise")
    tailored = ask(text="is it safe for me to exercise", conditions=["HYPERTENSION", "DIABETES"],
                   limitations=["BALANCE_IMPAIRMENT"], risk_level="High")
    assert plain["notes"] == []
    assert len(tailored["notes"]) == 4
    assert "high blood pressure" in tailored["answer"] and "low blood sugar" in tailored["answer"]
    assert "balance" in tailored["answer"] and "risk level is High" in tailored["answer"]


def test_condition_named_in_the_question_is_used():
    res = ask(text="I have asthma, any advice?")
    assert res["category"] == "condition_advice" and "inhaler" in res["answer"]


def test_notes_only_on_safety_related_answers():
    assert ask(text="thank you", conditions=["HYPERTENSION"])["notes"] == []


# ---- red flags ------------------------------------------------------------------

@pytest.mark.parametrize("text", ["I have chest pain", "CHEST PAIN while doing step ups", "my chest pian is bad",
                                  "i cant breath", "I'm breathless", "my knee is badly swollen", "I feel faint",
                                  "my speech is slurred", "my heart is racing", "I fell and hit my head",
                                  "No, I really do have chest pain"])
def test_red_flags_with_typos_and_variants(text):
    res = ask(text=text)
    assert res["category"] == "red_flag" and "999" in res["answer"]


def test_red_flag_beats_a_tapped_category():
    assert ask(text="I have chest pain", category="how_often")["category"] == "red_flag"


@pytest.mark.parametrize("text", ["I have no chest pain", "I'm not dizzy at all", "never fainted before"])
def test_negated_red_flags_are_not_urgent(text):
    assert ask(text=text)["category"] != "red_flag"


# ---- contract -----------------------------------------------------------------------

def test_request_validation():
    assert client.post("/chat", headers=DEV, json={}).status_code == 422
    assert client.post("/chat", headers=DEV, json={"text": "   "}).status_code == 422
    assert client.post("/chat", headers=DEV, json={"text": "x" * 501}).status_code == 422
    assert client.post("/chat", headers=DEV, json={"text": "hi", "risk_level": "Extreme"}).status_code == 422
    assert client.post("/chat", json={"text": "hi"}).status_code == 401


def test_response_fields():
    res = ask(text="how often should I exercise")
    assert set(res) == {"answer", "category", "title", "is_matched", "matched_by", "follow_ups", "notes",
                        "categories", "rules_version", "action"}
    assert res["matched_by"] == "keyword"


def test_unknown_plan_falls_back_to_general_rules():
    assert ask(text="what exercises are in my plan", plan_id="not-a-plan")["category"] != "plan_exercises"


def test_deterministic():
    answers = {ask(text="my knee hurts")["answer"] for _ in range(3)}
    assert len(answers) == 1


def test_rules_file_matches_catalogue():
    rules = engine.rules()
    assert set(rules["plans"]) == {p["plan_id"] for p in CATALOGUE["plans"]}
    assert set(rules["exercises"]) == {e["pose_key"] for e in CATALOGUE["exercises"]}
    keys = [i["key"] for i in rules["intents"]]
    assert len(keys) == len(set(keys))
    for i in rules["intents"]:
        assert i["keywords"] and i["examples"] and i["answer"], i["key"]
        assert all(f in keys for f in i["follow_ups"]), i["key"]


# ---- chat-rules-3.2: everyday questions found on the phone (7 Oct) ----------------------------------

@pytest.mark.parametrize("text, key", [
    ("how should we start", "getting_started"),
    ("where do I begin", "getting_started"),
    ("what should I do first", "getting_started"),
    ("forgot password", "forgot_password"),
    ("I can't log in", "forgot_password"),
    ("didn't get the code", "verification_code"),
    ("got it", "acknowledge"),
    ("ok my knee hurts", "pain_or_discomfort"),     # an acknowledgement never hides a real question
    ("right knee hurts", "pain_or_discomfort"),
    ("how do i start the heel raise", "exercise:heel_raise"),
])
def test_everyday_questions(text, key):
    res = client.post("/chat", json={"plan_id": KNEE, "text": text}, headers=DEV).json()
    assert res["category"] == key, res["answer"][:80]


def test_password_and_start_answers_offer_a_button():
    res = client.post("/chat", json={"text": "I forgot my password"}, headers=DEV).json()
    assert res["action"] == {"key": "open_reset_password", "label": "Reset password"}
    res = client.post("/chat", json={"text": "how should we start"}, headers=DEV).json()
    assert res["action"]["key"] == "open_planning"
    res = client.post("/chat", json={"text": "asdfgh"}, headers=DEV).json()
    assert res["action"] is None and res["answer"] == engine.rules()["not_recognised"]   # FR500_22 unchanged

