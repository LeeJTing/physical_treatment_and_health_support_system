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
from chat_round1_set import ROUND1
from chat_round2_set import ROUND2
from chat_round3_set import ROUND3
from chat_round4_set import ROUND4
from chat_round5_set import ROUND5
from chat_round6_set import ROUND6
from chat_round7_set import ROUND7
from chat_round8_set import ROUND8
from chat_round9_set import ROUND9
from chat_round10_set import ROUND10
from chat_round11_set import ROUND11
from chat_round12_set import ROUND12
from chat_round13_set import ROUND13
from chat_round14_set import ROUND14
from chat_round15_set import ROUND15
from chat_round16_set import ROUND16
from chat_round17_set import ROUND17
from chat_round18_set import ROUND18
from chat_round19_set import ROUND19
from chat_posture_messages_set import POSTURE_MESSAGES
from chat_safety_review_set import SAFETY_REVIEW
from chat_safety_pass2_set import SAFETY_PASS2
from chat_verify_set import VERIFY

client = TestClient(app)
DEV = {"Authorization": "Bearer dev-token"}
CATALOGUE = json.loads((Path(__file__).parents[2] / "assets" / "seed" / "catalogue.json").read_text(encoding="utf-8"))
KNEE_PLAN = next(p for p in CATALOGUE["plans"] if p["plan_id"] == KNEE)
NOT_RECOGNISED = "The question is not recognised, please try asking other question."

ALL_QUESTIONS = [(KNEE, q, e) for q, e in EVAL] + list(HOLDOUT) + list(VERIFY) + list(FINAL) + list(ROUND1) + list(ROUND2) + list(ROUND3) + list(ROUND4) + list(ROUND5) + list(ROUND6) + list(ROUND7) + list(ROUND8) + list(ROUND9) + list(ROUND10) + list(ROUND11) + list(ROUND12) + list(ROUND13) + list(ROUND14) + list(ROUND15) + list(ROUND16) + list(ROUND17) + list(ROUND18) + list(ROUND19) + list(POSTURE_MESSAGES) + list(SAFETY_REVIEW) + list(SAFETY_PASS2)


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
                        "categories", "rules_version", "action", "actions"}
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
        # Mistake names (rules 3.15) are reached through the glossary, not keywords.
        assert (i["keywords"] or i["key"].startswith("mistake:")) and i["examples"] and i["answer"], i["key"]
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


def test_a_second_button_when_the_answer_names_a_second_screen():
    res = ask("how do i change my password")
    assert [a["key"] for a in res["actions"]] == ["open_profile", "open_reset_password"]
    assert res["action"]["key"] == "open_profile"           # older apps read only this
    res = ask("how do i exit the recording")
    assert [a["key"] for a in res["actions"]] == ["open_treatment"]
    res = ask("asdfgh")
    assert res["actions"] == []


def test_password_and_start_answers_offer_a_button():
    res = client.post("/chat", json={"text": "I forgot my password"}, headers=DEV).json()
    assert res["action"] == {"key": "open_reset_password", "label": "Reset password"}
    res = client.post("/chat", json={"text": "how should we start"}, headers=DEV).json()
    assert res["action"]["key"] == "open_planning"
    res = client.post("/chat", json={"text": "asdfgh"}, headers=DEV).json()
    assert res["action"] is None and res["answer"] == engine.rules()["not_recognised"]   # FR500_22 unchanged



# ---- chat-rules-3.4: links to screens, time of day ----------------------------------------------

@pytest.mark.parametrize("text, key, action", [
    ("update my profile", "profile_help", "open_profile"),
    ("why is my risk level high", "risk_level", "open_profile"),
    ("change my reminder time", "reminders_help", "open_reminders"),
    ("show my past results", "history_help", "open_history"),
    ("how do I record my video", "recording_help", "open_treatment"),
    ("what exercises are in my plan", "plan_exercises", "open_treatment"),
    ("how do I do the exercises", "how_to", "open_treatment"),
    ("I forgot my password", "forgot_password", "open_reset_password"),
])
def test_answers_link_to_the_right_screen(text, key, action):
    res = ask(text)
    assert res["category"] == key and res["action"]["key"] == action


def test_late_night_advises_rest_and_shows_the_local_time():
    res = ask("can I exercise now", local_hour=23, local_minute=40)
    assert res["category"] == "best_time"
    assert res["notes"][0].startswith("It is 11:40 pm where you are. Late at night is not a good time")
    # also for an exercise question, but not for pain (safety advice must not be delayed)
    assert "Late at night" in ask("how do I do the exercises", local_hour=2, local_minute=0)["notes"][0]
    assert ask("my knee hurts", local_hour=23, local_minute=0)["notes"] == []


def test_daytime_says_now_is_fine_and_no_time_without_the_phone_time():
    assert ask("can I exercise now", local_hour=15, local_minute=0)["notes"][0].startswith("It is 3:00 pm")
    assert ask("can I exercise now")["notes"] == []          # older app: no local time sent


def test_condition_specific_timing():
    diabetic_evening = ask("can I exercise now", local_hour=20, local_minute=0, conditions=["DIABETES"])["notes"]
    assert any("blood sugar drop overnight" in n for n in diabetic_evening)
    morning = ask("when is the best time to exercise", local_hour=7, local_minute=0,
                  conditions=["HYPERTENSION", "ARTHRITIS"])["notes"]
    assert any("higher in the first hours after waking" in n for n in morning)
    assert any("stiffest first thing" in n for n in morning)
    balance_evening = ask("can I exercise now", local_hour=19, local_minute=0, limitations=["BALANCE_IMPAIRMENT"])
    assert any("well-lit room" in n for n in balance_evening["notes"])


def test_local_time_is_validated():
    r = client.post("/chat", headers=DEV, json={"text": "hi", "local_hour": 25})
    assert r.status_code == 422


def test_malay_symptoms_get_the_urgent_answer():
    for text in ["dada sakit, sesak nafas", "saya pening lepas senaman", "saya jatuh tadi"]:
        assert ask(text)["category"] == "red_flag", text


def test_malay_words_are_understood():
    assert ask("boleh buat senaman malam?")["category"] == "best_time"
    assert ask("lupa kata laluan")["category"] == "forgot_password"
    assert ask("terima kasih")["category"] == "thanks"


# ---- chat-rules-3.7: a different answer for each health condition (Table 4.2.2) ------------------

def test_condition_answer_differs_by_condition():
    generic = ask("can I exercise with my condition")["answer"]
    bp = ask("can I exercise with my condition", conditions=["HYPERTENSION"])["answer"]
    diabetes = ask("can I exercise with my condition", conditions=["DIABETES"])["answer"]
    assert len({generic, bp, diabetes}) == 3
    assert "180/110" in bp and "low sugar" in diabetes


def test_condition_named_in_the_question_is_answered_on_its_own():
    # 8 Oct (phone test): with the profile's conditions added, answers for older readers ran to 230
    # words. A condition named in the question is answered alone; otherwise the profile's are used.
    a = ask("i have diabetes can i exercise", conditions=["ARTHRITIS"])["answer"]
    assert "With diabetes" in a and "With arthritis" not in a
    b = ask("can i exercise with my condition", conditions=["ARTHRITIS"])["answer"]
    assert "With arthritis" in b


def test_diet_answers_get_diet_notes_not_exercise_reminders():
    notes = ask("what should I eat", conditions=["HYPERTENSION", "DIABETES"])["notes"]
    assert any("salt" in n for n in notes) and any("carbohydrates" in n for n in notes)
    assert not any(n.startswith("Because you have") for n in notes)


def test_more_topics_follow_the_patients_conditions():
    assert ask("i feel tired today", conditions=["DIABETES"])["notes"]
    assert ask("i missed yesterday", conditions=["HEART_DISEASE"])["notes"]


# ---- chat-rules-3.10: emergencies in free words, without false alarms ---------------------------

@pytest.mark.parametrize("text", [
    "my chest feels heavy and painful", "i can hardly breathe", "my left arm suddenly cannot move",
    "the pain moved to my chest", "i cannot breathe properly", "suddenly my face is drooping",
])
def test_free_worded_emergencies_get_the_urgent_answer(text):
    assert engine.red_flag(text), text


@pytest.mark.parametrize("text", [
    "how do i breathe during the exercise", "breathe out as you lift?", "my chest is fine",
    "no chest pain at all", "i never had breathing problems", "suddenly i feel better",
    "can i do chest exercises",
])
def test_no_false_alarms(text):
    assert not engine.red_flag(text), text


def test_no_keyword_reduces_to_a_common_word():
    """A keyword whose stem is an everyday word ('cane' -> 'can') would capture every question
    containing that word. Guard: no single-word keyword may stem to a stop word."""
    bad = []
    for i in engine.intents_for(KNEE):
        for k in i["keywords"]:
            words = engine.clean(k).split()
            if len(words) == 1 and engine.stem(words[0]) in engine.STOP and words[0] not in engine.STOP:
                bad.append((i["key"], k))
    assert not bad, bad


# ---- follow-ups use the previous answer's topic ----------------------------------------------------

def test_follow_up_continues_the_previous_exercise():
    r = ask("how many reps for that one", previous_category="exercise:heel_raise")
    assert r["category"] == "exercise:heel_raise" and r["matched_by"] == "follow_up"
    assert ask("how often should i do it", previous_category="exercise:heel_raise")["category"] == "exercise:heel_raise"


def test_follow_up_never_overrides_safety_or_a_new_topic():
    assert ask("is it painful", previous_category="exercise:heel_raise")["category"] == "pain_or_discomfort"
    assert ask("how do i do the sit to stand", previous_category="exercise:heel_raise")["category"] == "exercise:sit_to_stand"
    assert ask("i feel chest pain doing it", previous_category="exercise:heel_raise")["category"] == "red_flag"
    assert ask("how many reps for that one")["category"] == "plan_exercises"      # no previous topic


# ---- safety pass 3 (laptop, 8 Oct): messages that must not trigger the urgent answers -------------

from chat_safety_pass3_set import SAFETY_PASS3  # noqa: E402


@pytest.mark.parametrize("plan, question, expected", SAFETY_PASS3, ids=[q[:40] for _, q, _ in SAFETY_PASS3])
def test_safety_pass3(plan, question, expected):
    got = engine.reply(plan, None, question)["category"]
    if expected == "NOT_URGENT":
        assert got not in ("crisis", "red_flag"), got
    else:
        assert got in expected.split("/"), got


from chat_safety_pass4_set import SAFETY_PASS4  # noqa: E402


@pytest.mark.parametrize("plan, question, expected", SAFETY_PASS4, ids=[q[:40] for _, q, _ in SAFETY_PASS4])
def test_safety_pass4(plan, question, expected):
    got = engine.reply(plan, None, question)["category"]
    if expected == "NOT_URGENT":
        assert got not in ("crisis", "red_flag"), got
    else:
        assert got in expected.split("/"), got


from chat_safety_pass5_set import SAFETY_PASS5  # noqa: E402


@pytest.mark.parametrize("plan, question, expected", SAFETY_PASS5, ids=[q[:40] for _, q, _ in SAFETY_PASS5])
def test_safety_pass5(plan, question, expected):
    got = engine.reply(plan, None, question)["category"]
    if expected == "NOT_URGENT":
        assert got not in ("crisis", "red_flag", "overdose", "poisoning"), got
    else:
        assert got in expected.split("/"), got


from chat_safety_pass6_set import SAFETY_PASS6  # noqa: E402


@pytest.mark.parametrize("plan, question, expected", SAFETY_PASS6, ids=[q[:40] for _, q, _ in SAFETY_PASS6])
def test_safety_pass6(plan, question, expected):
    got = engine.reply(plan, None, question)["category"]
    if expected == "NOT_URGENT":
        assert got not in ("crisis", "red_flag", "overdose", "poisoning"), got
    else:
        assert got in expected.split("/"), got


from chat_safety_pass7_set import SAFETY_PASS7  # noqa: E402


@pytest.mark.parametrize("plan, question, expected", SAFETY_PASS7, ids=[q[:40] for _, q, _ in SAFETY_PASS7])
def test_safety_pass7(plan, question, expected):
    got = engine.reply(plan, None, question)["category"]
    if expected == "NOT_URGENT":
        assert got not in ("crisis", "red_flag", "overdose", "poisoning"), got
    else:
        assert got in expected.split("/"), got


from chat_safety_pass8_set import SAFETY_PASS8  # noqa: E402


@pytest.mark.parametrize("plan, question, expected", SAFETY_PASS8, ids=[q[:40] for _, q, _ in SAFETY_PASS8])
def test_safety_pass8(plan, question, expected):
    got = engine.reply(plan, None, question)["category"]
    if expected == "NOT_URGENT":
        assert got not in ("crisis", "red_flag", "overdose", "poisoning"), got
    else:
        assert got in expected.split("/"), got


from chat_safety_pass9_set import SAFETY_PASS9  # noqa: E402


@pytest.mark.parametrize("plan, question, expected", SAFETY_PASS9, ids=[q[:40] for _, q, _ in SAFETY_PASS9])
def test_safety_pass9(plan, question, expected):
    got = engine.reply(plan, None, question)["category"]
    if expected == "NOT_URGENT":
        assert got not in ("crisis", "red_flag", "overdose", "poisoning"), got
    else:
        assert got in expected.split("/"), got


from chat_safety_pass10_set import SAFETY_PASS10  # noqa: E402


@pytest.mark.parametrize("plan, question, expected", SAFETY_PASS10, ids=[q[:40] for _, q, _ in SAFETY_PASS10])
def test_safety_pass10(plan, question, expected):
    got = engine.reply(plan, None, question)["category"]
    if expected == "NOT_URGENT":
        assert got not in ("crisis", "red_flag", "overdose", "poisoning"), got
    else:
        assert got in expected.split("/"), got


from chat_safety_pass11_set import SAFETY_PASS11  # noqa: E402


@pytest.mark.parametrize("plan, question, expected", SAFETY_PASS11, ids=[q[:40] for _, q, _ in SAFETY_PASS11])
def test_safety_pass11(plan, question, expected):
    got = engine.reply(plan, None, question)["category"]
    if expected == "NOT_URGENT":
        assert got not in ("crisis", "red_flag", "overdose", "poisoning"), got
    elif expected == "UNREC":   # not matched to a topic; small talk and app help are fine
        assert got in (None, "greeting", "acknowledge", "thanks", "goodbye", "bot_identity", "app_help"), got
    else:
        assert (got if got is not None else "None") in expected.split("/"), got


from chat_safety_pass12_set import SAFETY_PASS12  # noqa: E402
from chat_safety_pass13_set import SAFETY_PASS13  # noqa: E402
from chat_safety_pass14_set import SAFETY_PASS14  # noqa: E402
from chat_safety_pass15_set import SAFETY_PASS15  # noqa: E402
from chat_safety_pass16_set import SAFETY_PASS16  # noqa: E402


@pytest.mark.parametrize("plan, question, expected", SAFETY_PASS12, ids=[q[:40] for _, q, _ in SAFETY_PASS12])
def test_safety_pass12(plan, question, expected):
    got = engine.reply(plan, None, question)["category"]
    if expected == "NOT_URGENT":
        assert got not in ("crisis", "red_flag", "overdose", "poisoning"), got
    else:
        assert (got if got is not None else "None") in expected.split("/"), got


@pytest.mark.parametrize("plan, question, expected", SAFETY_PASS13, ids=[q[:40] for _, q, _ in SAFETY_PASS13])
def test_safety_pass13(plan, question, expected):
    got = engine.reply(plan, None, question)["category"]
    if expected == "NOT_URGENT":
        assert got not in ("crisis", "red_flag", "overdose", "poisoning"), got
    else:
        assert (got if got is not None else "None") in expected.split("/"), got


@pytest.mark.parametrize("plan, question, expected", SAFETY_PASS14, ids=[q[:40] for _, q, _ in SAFETY_PASS14])
def test_safety_pass14(plan, question, expected):
    got = engine.reply(plan, None, question)["category"]
    if expected == "NOT_URGENT":
        assert got not in ("crisis", "red_flag", "overdose", "poisoning"), got
    else:
        assert (got if got is not None else "None") in expected.split("/"), got


@pytest.mark.parametrize("plan, question, expected", SAFETY_PASS15, ids=[q[:40] for _, q, _ in SAFETY_PASS15])
def test_safety_pass15(plan, question, expected):
    got = engine.reply(plan, None, question)["category"]
    if expected == "NOT_CRISIS":
        assert got != "crisis", got
    else:
        assert got == expected, got


@pytest.mark.parametrize("plan, question, expected", SAFETY_PASS16, ids=[q[:40] for _, q, _ in SAFETY_PASS16])
def test_safety_pass16(plan, question, expected):
    got = engine.reply(plan, None, question)["category"]
    if expected == "NOT_URGENT":
        assert got not in ("crisis", "red_flag", "overdose", "poisoning"), got
    else:
        assert (got if got is not None else "None") in expected.split("/"), got


# ---- chat-rules-3.49: plans stop at 65 (Terms of Use, section 2) ------------------------------------

OLD = {"restriction": "AGE_65_PLUS"}


@pytest.mark.parametrize("question", ["how do I start", "what is in my plan", "how do I record my video",
                                      "how many plans can I have", "I missed a session", "how often should I exercise",
                                      "why is my plan paused", "how do I change my plan"])
def test_restricted_plan_questions_get_the_age_answer(question):
    res = ask(question, **OLD)
    assert res["category"] == "age_limit" and res["title"] == "Your plans are paused"
    assert "Terms of Use (section 2)" in res["answer"] and "physiotherapist" in res["answer"]
    assert res["actions"] == [{"key": "open_age_limit", "label": "Why plans are paused"}]


def test_restricted_tapped_plan_category_gets_the_age_answer():
    assert ask(category="getting_started", **OLD)["category"] == "age_limit"
    assert ask(category="plan_exercises", **OLD)["category"] == "age_limit"


@pytest.mark.parametrize("question, category", [("is it safe to exercise", "safety"),
                                                ("how do I do sit to stand", "exercise:sit_to_stand"),
                                                ("I feel weak after being in hospital", "muscle_loss")])
def test_restricted_general_advice_stays_with_a_note_first(question, category):
    res = ask(question, **OLD)
    assert res["category"] == category
    assert res["notes"][0].startswith("Your plans are paused (plans are for users under 65")


@pytest.mark.parametrize("question, category", [("chest pain and dizzy", "red_flag"), ("hello", "greeting"),
                                                ("I forgot my password", "forgot_password")])
def test_restricted_safety_and_account_answers_are_unchanged(question, category):
    plain, old = ask(question), ask(question, **OLD)
    assert old["category"] == plain["category"] == category and old["answer"] == plain["answer"]


def test_restricted_categories_put_the_age_limit_first_and_drop_plan_topics():
    cats = client.get("/chat/categories", headers=DEV, params={"plan_id": KNEE, "restriction": "AGE_65_PLUS"}).json()
    keys = [c["key"] for c in cats["categories"]]
    assert keys[0] == "age_limit"
    assert not {"getting_started", "how_to", "missed_session", "recording_help"} & set(keys)
    assert not [k for k in keys if k.startswith("plan_")]
    assert {"safety", "pain_or_discomfort"} <= set(keys)
    assert [c["key"] for c in ask("hello", **OLD)["categories"]] == keys


@pytest.mark.parametrize("question", ["is there an age limit", "am I too old for a plan", "why can't I get a plan",
                                      "can I still exercise after 65"])
def test_anyone_can_ask_about_the_age_limit(question):
    res = ask(question)
    assert res["category"] == "age_limit" and "Exercise plans are for users under 65" in res["answer"]


def test_too_old_to_exercise_is_still_the_safety_answer():
    assert ask("am I too old to exercise")["category"] == "safety"


def test_unknown_restriction_is_rejected():
    r = client.post("/chat", headers=DEV, json={"text": "hello", "restriction": "UNDER_13"})
    assert r.status_code == 422


# ---- chat-rules-3.50: the conditions added to the health profile -------------------------------------

@pytest.mark.parametrize("question, condition", [
    ("can I exercise with copd", "chronic lung disease"), ("I have rheumatoid arthritis any advice", "rheumatoid"),
    ("I am on dialysis can I exercise", "kidney"), ("I have parkinsons", "Parkinson"),
    ("I have cancer and chemo", "cancer"), ("is it safe with my foot ulcer", "foot ulcer"),
    ("I have multiple sclerosis, can I exercise", "multiple sclerosis")])
def test_new_conditions_get_their_own_advice(question, condition):
    res = ask(question)
    assert res["category"] == "condition_advice" and condition.lower() in res["answer"].lower()


def test_do_i_have_cancer_stays_a_diagnosis_question():
    assert ask("do I have cancer")["category"] == "diagnosis"


@pytest.mark.parametrize("code", ["PREGNANCY", "JOINT_REPLACEMENT", "RHEUMATOID_ARTHRITIS", "COPD", "CANCER",
                                  "KIDNEY_DISEASE", "PARKINSONS", "MULTIPLE_SCLEROSIS", "FOOT_ULCER", "OTHER"])
def test_every_new_profile_condition_adds_a_safety_note(code):
    res = ask("is it safe to exercise", conditions=[code])
    assert any(n.startswith("Because") for n in res["notes"]), res["notes"]


@pytest.mark.parametrize("question", ["do I have cancer", "could this lump be cancer", "what are the signs of cancer"])
def test_cancer_diagnosis_questions_stay_diagnosis(question):
    assert ask(question)["category"] == "diagnosis"
