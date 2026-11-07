"""Health conditions the health profile does not list (tests/chat_conditions_set.py, chat-rules-3.75) as a
guard: 500 messages of seed 3 (not used while building 3.75) keep today's level, and the condition advice
speaks of the condition asked about."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_conditions_set import build  # noqa: E402

from app.chat import engine  # noqa: E402

PLAN = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"


def _ok(c):
    x = engine.reply(c["plan_id"], None, c["text"])
    got = x["category"] if x["is_matched"] else None
    return str(got) in c["want"] and (got != "condition_advice" or c["marker"].lower() in x["answer"].lower())


def test_unlisted_conditions_keep_their_level():
    cases = build(3, 500)
    bad = [c["text"] for c in cases if not _ok(c)]
    assert len(bad) / len(cases) <= 0.03, bad[:20]


def test_unlisted_condition_says_to_add_it_as_other():
    x = engine.reply(PLAN, None, "i have gout can i exercise")
    assert x["category"] == "condition_advice" and "gout" in x["answer"].lower()
    assert "Other condition (not listed)" in x["answer"]
    x = engine.reply(PLAN, None, "i have diabetes can i exercise")
    assert "Other condition" not in x["answer"]            # a condition the profile lists


def test_a_seizure_or_a_clot_now_is_urgent():
    for text in ["she is having a fit", "my father had a seizure just now", "dia sawan",
                 "i have a blood clot in my leg, it is swollen and painful"]:
        assert engine.reply(PLAN, None, text)["category"] == "red_flag", text
    for text in ["i had a seizure last year", "my seizures are controlled can i exercise",
                 "i had a blood clot last year, can i exercise", "i'm fit and healthy", "the clothes fit me well"]:
        assert engine.reply(PLAN, None, text)["category"] != "red_flag", text


def test_asking_for_a_diagnosis_is_still_a_diagnosis():
    assert engine.reply(PLAN, None, "is it a slipped disc")["category"] == "diagnosis"
    assert engine.reply(PLAN, None, "i have a slipped disc can i exercise")["category"] == "condition_advice"
