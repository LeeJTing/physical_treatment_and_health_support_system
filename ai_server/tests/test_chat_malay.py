"""Malay texting (tests/chat_malay_texting_set.py, chat-rules-3.64) as a guard: 500 messages of seed 3 (not
used while building 3.64) must keep today's level, and so must the warning signs among them. Before
3.64 the same set scored about 59 %, warning signs about 50 % (evaluate_chat_malay.py)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_malay_texting_set import build  # noqa: E402

from app.chat import engine  # noqa: E402

URGENT = {"red_flag", "crisis"}
CASES = build(3, 500)
RESULTS = [(c, (lambda x: x["category"] if x["is_matched"] else None)(engine.reply(c["plan_id"], None, c["text"])))
           for c in CASES]


def test_malay_texting_sample_keeps_its_level():
    good = sum(g in c["want"] for c, g in RESULTS)
    assert good / len(RESULTS) >= 0.95, [(c["text"], c["want"][:2], g) for c, g in RESULTS if g not in c["want"]][:25]


def test_malay_warning_signs_texted_are_caught():
    urgent = [(c, g) for c, g in RESULTS if set(c["want"]) <= URGENT]
    caught = sum(g in URGENT for _, g in urgent)
    assert caught / len(urgent) >= 0.95, [(c["text"], g) for c, g in urgent if g not in URGENT]


def test_english_short_forms_are_not_read_as_malay():
    assert engine.respell("i have ms") == "i have ms"                    # multiple sclerosis, not "masa"
    assert engine.respell("3 x 10 reps") == "3 x 10 reps"                # not "tak"
    assert engine.respell("boleh buat 3 x 10 ke") == "boleh buat 3 x 10 ke"
    assert engine.respell("minum 500 ml air") == "minum 500 ml air"      # not "mula"
    assert engine.respell("my dr said ok") == "my doctor said ok"
    assert engine.respell("saya nak bunuh dr") == "saya nak bunuh diri"
