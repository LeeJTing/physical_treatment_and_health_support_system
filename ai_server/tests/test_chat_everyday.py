"""Everyday random inputs (tests/chat_everyday_set.py, chat-rules-3.67) as a guard: 500 messages of seed 3
(not used while building 3.67) keep today's level, and none of chit-chat, feelings, a body part, an app
feature, emoji, food or yes / no is answered as an emergency. Before 3.67 the set scored 58.75%."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_everyday_set import build  # noqa: E402

from app.chat import engine  # noqa: E402

PLAN = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"
URGENT = {"red_flag", "crisis", "overdose", "poisoning"}
CALM = {"chit_chat", "body_part", "app_feature", "emoji", "food", "yes_no", "time_alone", "activity"}
RESULTS = [(c, (lambda x: x["category"] if x["is_matched"] else None)(
    engine.reply(PLAN, None, c["text"], previous_category=c["previous_category"]))) for c in build(3, 500)]


def test_everyday_inputs_keep_their_level():
    good = sum(str(g) in c["want"] for c, g in RESULTS)
    assert good / len(RESULTS) >= 0.95, [(c["text"], c["want"], g) for c, g in RESULTS if str(g) not in c["want"]][:20]


def test_everyday_inputs_are_not_emergencies():
    assert not [(c["text"], g) for c, g in RESULTS if c["kind"] in CALM and g in URGENT]


def test_things_the_chatbot_cannot_do_say_so():
    for text in ["call my doctor", "book an appointment", "play music", "whatsapp my daughter"]:
        assert engine.reply(PLAN, None, text)["category"] == "cannot_do", text
    assert engine.reply(PLAN, None, "call ambulance for me")["category"] == "red_flag"


def test_a_body_part_alone_is_asked_about():
    x = engine.reply(PLAN, None, "knee")
    assert x["category"] == "clarify" and "your knee" in x["answer"]
