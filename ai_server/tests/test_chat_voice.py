"""Voice typing (tests/chat_voice_set.py, chat-rules-3.69) as a guard: 500 messages of seed 3 keep today's
level; misheard crisis and warning-sign messages are caught; real words are left alone. Before 3.69 the set
scored 79.3%, and "i dont want two live anymore", "chess pain" and "i can hardly breed" were missed."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_voice_set import build  # noqa: E402

from app.chat import engine  # noqa: E402

PLAN = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"


def _got(text, plan=PLAN):
    x = engine.reply(plan, None, text)
    return x["category"] if x["is_matched"] else None


def test_voice_typing_sample_keeps_its_level():
    results = [(c, _got(c["text"], c["plan_id"])) for c in build(3, 500)]
    good = sum(str(g) in c["want"] for c, g in results)
    assert good / len(results) >= 0.95, [(c["text"], c["want"], g) for c, g in results if str(g) not in c["want"]][:20]


def test_misheard_emergencies_are_caught():
    for text, want in [("uh i dont want two live anymore", "crisis"), ("want too die la this pain", "crisis"),
                       ("um tied of living", "crisis"), ("dont want two wake up tomorrow", "crisis"),
                       ("um chess pain while exercising", "red_flag"), ("i can hardly breed", "red_flag"),
                       ("okay my neck hertz after falling", "red_flag"), ("okay i feel dizzie", "red_flag")]:
        assert _got(text) == want, text


def test_real_words_are_left_alone():
    for text in ["i went to the store", "i saw a doctor", "two times a week", "turn left", "my risk level",
                 "i need help", "i need pain relief", "can i do heel raise too"]:
        assert engine._voice(text) == text, text
