"""Everyday situations around exercising (tests/chat_situations_set.py, chat-rules-3.76) as a guard: 500
messages of seed 3 (not used while building 3.76) keep today's level; the same words meaning something else
are not these topics; warning signs told with a situation stay urgent. Before 3.76 the set scored 0%."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_situations_set import build  # noqa: E402

from app.chat import engine  # noqa: E402

PLAN = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"


def test_situations_keep_their_level():
    cases = build(3, 500)
    bad = [(c["text"], c["want"], engine.reply(c["plan_id"], None, c["text"])["category"]) for c in cases
           if str((lambda x: x["category"] if x["is_matched"] else None)(engine.reply(c["plan_id"], None, c["text"])))
           not in c["want"]]
    assert len(bad) / len(cases) <= 0.03, bad[:20]


def test_the_same_words_meaning_something_else():
    for text, wrong in [("reply asap", "haze"), ("can i walk fast today", "fasting"), ("i drunk water already",
                        "alcohol_smoking"), ("can i climb a flight of stairs", "travel"),
                        ("how far should my knee travel", "travel"), ("i have a cold", "weather")]:
        assert engine.reply(PLAN, None, text)["category"] != wrong, text


def test_warning_signs_with_a_situation_stay_urgent():
    for text in ["haze makes me breathless and my chest is tight", "heavy bleeding during my period and dizzy",
                 "after my operation my calf is swollen red and painful"]:
        assert engine.reply(PLAN, None, text)["category"] == "red_flag", text
