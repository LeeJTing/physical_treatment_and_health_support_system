"""The random typing test (chat-rules-3.55; tests/chat_random_set.py, evaluate_chat_random.py) as a guard:
every 10th message of seed 1 (1 000 messages, typed the way users type, in random situations) must keep
today's level, and so must the warning signs and thoughts of suicide among them. The full 10 000 of
seeds 1 and 2 are run by evaluate_chat_random.py (docs/chat_random_eval_seed*.json).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_random_set import build  # noqa: E402

from app.chat import engine  # noqa: E402

CASES = build(1)[::10]
URGENT = {"red_flag", "crisis", "overdose", "poisoning"}


def _got(c):
    x = engine.reply(c["context"]["plan_id"], None, c["text"], conditions=c["context"]["conditions"],
                     risk_level=c["context"]["risk_level"], local_time=c["context"]["local_time"],
                     previous_category=c["context"]["previous_category"], restriction=c["context"]["restriction"])
    return x["category"] if x["is_matched"] else None


RESULTS = [(c, _got(c)) for c in CASES]


def test_random_typing_sample_keeps_its_level():
    good = sum(g in c["want"] for c, g in RESULTS)
    assert good / len(RESULTS) >= 0.975, [(c["text"], c["want"], g) for c, g in RESULTS if g not in c["want"]][:30]


def test_warning_signs_and_crisis_typed_badly_are_still_caught():
    urgent = [(c, g) for c, g in RESULTS if set(c["want"]) <= URGENT]      # only a safety answer is right
    caught = sum(g in URGENT for _, g in urgent)
    assert caught / len(urgent) >= 0.98, [(c["text"], g) for c, g in urgent if g not in URGENT]


def test_follow_ups_in_the_sample_all_continue():
    follow = [(c, g) for c, g in RESULTS if c["kind"] == "follow"]
    assert all(g in c["want"] for c, g in follow), [(c["text"], g) for c, g in follow if g not in c["want"]]


def test_warning_signs_with_two_slips_are_read():
    # 3.97: the misses of seeds 1 and 2 among the warning signs, and the false emergency "ankles fel sore"
    plan = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"
    for text in ["HAED TO BREATEH", "my mother has hardto brate", "i can't get up from the foor ?",
                 "sudsenly shoortof breath??", "Hi suddwnlypasseed out", "hepfelll and cannot get up!",
                 "i feel about to fnt", "bteter if i was goe...", "Sjit dada during exercise leh!"]:
        assert engine.reply(plan, None, text)["category"] in URGENT, text
    for text, want in [("My ankles fel sore", "pain_or_discomfort"), ("change fnt size", "text_size"),
                       ("excuse me saya jatuh thun lepas!", "fear_of_falling"),
                       ("i fell in the bthroom lst month, can i still exercise", "fear_of_falling")]:
        assert engine.reply(plan, None, text)["category"] == want, text
    for text in ["erm i fellt leh", "my foor hurts", "pain on the foor"]:
        assert engine.reply(plan, None, text)["category"] not in URGENT, text
