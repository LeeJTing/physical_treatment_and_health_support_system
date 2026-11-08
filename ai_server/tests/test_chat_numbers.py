"""Messages with a number in them (tests/chat_numbers_set.py, chat-rules-3.74) as a guard: 500 messages of
seed 3 (not used while building 3.74) keep today's level, and every reading that needs help now is urgent.
Before 3.74 seed 1 scored 20.15%, urgent 0/132 ("spo2 88", "heart rate 160" were not warning signs)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_numbers_set import build  # noqa: E402

from app.chat import engine  # noqa: E402

PLAN = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"
RESULTS = [(c, (lambda x: x["category"] if x["is_matched"] else None)(engine.reply(c["plan_id"], None, c["text"])))
           for c in build(3, 500)]


def test_numbers_keep_their_level():
    good = sum(str(g) in c["want"] for c, g in RESULTS)
    assert good / len(RESULTS) >= 0.97, [(c["text"], c["want"], g) for c, g in RESULTS if str(g) not in c["want"]][:20]


def test_readings_that_need_help_now_are_urgent():
    assert not [(c["text"], g) for c, g in RESULTS if c["urgent"] and str(g) not in c["want"]]
    for text in ["spo2 88", "my oxygen is 92%", "heart rate 165 after exercise", "pulse 38"]:
        assert engine.reply(PLAN, None, text)["category"] == "red_flag", text


def test_numbers_that_are_not_readings():
    for text, want in [("pain 10/10", "pain_sharp"), ("pain 2/10", "pain_mild"), ("i am 75", "age_limit"),
                       ("my mother is 80", "age_limit"), ("i'm 16", "guardian_consent"), ("i am 75 kg", "profile_help"),
                       ("1 hr 20 min walk", "how_often"), ("temperature outside is 35 degrees", "hot_weather"),
                       ("my mother is 80 and her knee hurts", "pain_or_discomfort"),
                       ("i did 30 reps is that too much", "difficulty"), ("bp 120/80", "condition_advice")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text
    for text in ["10/10 would recommend", "i'm 50/50 about this", "oxygen tank lasts 90 minutes"]:
        assert engine.reply(PLAN, None, text)["category"] != "red_flag", text
