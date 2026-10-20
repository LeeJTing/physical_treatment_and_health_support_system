"""A family member typing for someone else (tests/chat_caregiver_set.py, chat-rules-3.73) as a guard: 500
messages of seed 3 (not used while building 3.73) keep today's level, and every warning sign told of someone
else stays urgent. Before 3.73 seed 1 scored 96.80%, urgent 262/273."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_caregiver_set import build  # noqa: E402

from app.chat import engine  # noqa: E402

PLAN = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"
RESULTS = [(c, (lambda x: x["category"] if x["is_matched"] else None)(engine.reply(c["plan_id"], None, c["text"])))
           for c in build(3, 500)]


def test_caregiver_questions_keep_their_level():
    good = sum(str(g) in c["want"] for c, g in RESULTS)
    assert good / len(RESULTS) >= 0.97, [(c["text"], c["want"], g) for c, g in RESULTS if str(g) not in c["want"]][:20]


def test_warning_signs_told_of_someone_else_stay_urgent():
    assert not [(c["text"], g) for c, g in RESULTS if c["urgent"] and str(g) not in c["want"]]


def test_crisis_told_of_someone_else_gets_help_for_them():
    for text in ["my dad wish he was dead", "my mother keeps saying she wants to die", "my mum wants to kill herself",
                 "my husband talks about suicide"]:
        x = engine.reply(PLAN, None, text)
        assert x["category"] == "crisis" and "Stay with them" in x["answer"], text
    x = engine.reply(PLAN, None, "i want to die")
    assert x["category"] == "crisis" and "Stay with them" not in x["answer"]
    for text in ["i wish he was dead", "my mum cut herself cooking"]:
        assert engine.reply(PLAN, None, text)["category"] != "crisis", text


def test_the_family_members_own_question():
    # 3.73: read as if the person asked it themselves.
    for text, want in [("where to edit my dad's weight", "profile_help"),
                       ("my mother failed the posture check", "posture_result"),
                       ("does my father have arthritis", "diagnosis"),
                       ("how high should my mum's heels go", "exercise:heel_raise"),
                       ("my father is scared he will fall", "fear_of_falling"),
                       ("what if my father can't get up after a fall", "fear_of_falling"),
                       ("can my mother do these exercises", "for_someone_else"),
                       ("can my daughter help me", "family_help")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text
