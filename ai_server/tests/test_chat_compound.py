"""Compound and rambling messages (tests/chat_compound_set.py, chat-rules-3.70) as a guard: every urgent
message of a 500-message sample of seed 3 is caught; the rest keep today's level; a fall told with its
own "long ago" or "now fine" is not urgent. Before 3.70 urgent messages joined to another question with
"also", "plus", "another thing", "anyway", "..." were missed (405/412 on seed 1)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_compound_set import build  # noqa: E402

from app.chat import engine  # noqa: E402

PLAN = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"
RESULTS = [(c, (lambda x: x["category"] if x["is_matched"] else None)(engine.reply(c["plan_id"], None, c["text"])))
           for c in build(3, 500)]


def test_every_urgent_compound_message_is_caught():
    missed = [(c["text"], g) for c, g in RESULTS if c["urgent"] and str(g) not in c["want"]]
    assert not missed, missed


def test_compound_messages_keep_their_level():
    good = sum(str(g) in c["want"] for c, g in RESULTS)
    assert good / len(RESULTS) >= 0.92, [(c["text"], c["want"], g) for c, g in RESULTS if str(g) not in c["want"]][:20]


def test_old_or_settled_falls_split_off_are_not_urgent():
    for text in ["i fell... long time ago, now ok", "she fell... that was last year",
                 "i fell last year and then i did the plan today"]:
        assert engine.reply(PLAN, None, text)["category"] != "red_flag", text
    assert engine.reply(PLAN, None, "my son bought me a new phone. anyway my eyesight is blurry suddenly")["category"] \
        == "red_flag"
