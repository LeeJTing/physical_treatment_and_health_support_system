"""Medicines by name (tests/chat_medicines_set.py, chat-rules-3.77) as a guard: 500 messages of seed 3 (not
used while building 3.77) keep today's level and every overdose by name is urgent. Before 3.77 the set
scored 24.50% and caught 205 of 512 overdoses ("i took 30 amlodipine" was not recognised)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_medicines_set import build  # noqa: E402

from app.chat import engine  # noqa: E402

PLAN = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"
RESULTS = [(c, (lambda x: x["category"] if x["is_matched"] else None)(engine.reply(c["plan_id"], None, c["text"])))
           for c in build(3, 500)]


def test_medicines_by_name_keep_their_level():
    good = sum(str(g) in c["want"] for c, g in RESULTS)
    assert good / len(RESULTS) >= 0.97, [(c["text"], c["want"], g) for c, g in RESULTS if str(g) not in c["want"]][:20]


def test_every_overdose_by_name_is_urgent():
    assert not [(c["text"], g) for c, g in RESULTS if c["urgent"] and g != "overdose"]


def test_a_normal_dose_is_not_an_emergency():
    for text in ["i take 2 panadol a day", "i took my metformin this morning", "my mother took 2 aspirin",
                 "i took 10 minutes to walk"]:
        assert engine.reply(PLAN, None, text)["category"] not in ("overdose", "red_flag"), text
