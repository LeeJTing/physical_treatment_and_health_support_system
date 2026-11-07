"""Elwin's 21 chat reports (Supabase chat_report, 11 Oct; chat-rules-3.66) and random messages in their
patterns (tests/chat_user_style_set.py) as a guard. Before 3.66: 7 of the 20 one-message reports were
answered as he expected, and 46 % of the random messages (evaluate_chat_user_style.py)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_user_style_set import REPORTED, build  # noqa: E402

from app.chat import engine  # noqa: E402

PLAN = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"
URGENT = {"red_flag", "crisis", "overdose", "poisoning"}


def _reply(text, previous=None):
    return engine.reply(PLAN, None, text, previous_category=previous)


def _got(text, previous=None):
    x = _reply(text, previous)
    return x["category"] if x["is_matched"] else None


def test_every_reported_question_is_answered_as_expected():
    wrong = [(q, _got(q)) for q, want in REPORTED if _got(q) not in want]
    assert not wrong, wrong


def test_really_after_an_answer_continues_it():
    # Report 13: "The response didn't link back to the previous question and answer."
    assert _got("Really?", "how_often") == "how_often"
    assert _got("are you sure lah", "pain_or_discomfort") == "pain_or_discomfort"


def test_slips_of_short_words_from_the_reports():
    # 3.89: "medic", "what", "dial 999", "i love you", "come again" typed with a slip or stretched
    for text, want in [("medci leh ?", "med_help"), ("Medicccc leh ?", "med_help"), ("MEDD AH ?", "med_help"),
                       ("whaat", "clarify"), ("um whhat??", "clarify"), ("Disl 999!", "red_flag"),
                       ("i lve you ah", "bot_identity"), ("cme again?", "pardon")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text
    for text in ["media", "medal"]:
        assert engine.reply(PLAN, None, text)["category"] != "med_help", text


def test_not_recognised_echoes_a_short_message():
    x = _reply("going")
    assert x["answer"].startswith("Question not recognised") and '"going"' in x["answer"]       # FR500_22
    assert "typed by accident" in _reply("kdjsb")["answer"]
    assert _reply("what is the capital of france")["answer"] == engine.rules()["not_recognised"]


def test_exercise_answers_are_set_out_in_lines():
    # Reports 17-18: "The answer should display more neatly".
    lines = _reply("How to do Shoulder Abduction")["answer"].split("\n")
    assert lines[0] == "Shoulder Abduction" and lines[1].startswith("1) ") and lines[2].startswith("2) ")


def test_random_messages_like_the_reports_keep_their_level():
    cases = build(3, 500)
    results = [(c, _got(c["text"], c["previous_category"])) for c in cases]
    good = sum(str(g) in c["want"] for c, g in results)
    assert good / len(results) >= 0.95, [(c["text"], c["want"], g) for c, g in results if str(g) not in c["want"]][:20]
    assert not [(c["text"], g) for c, g in results if c["kind"] in ("gibberish", "vague", "small_talk") and g in URGENT]


def test_every_answer_is_set_out_in_lines():
    # 3.68 (Elwin, 21 Oct): no answer of three or more sentences is one block of text.
    from app.chat.layout import sentences
    for i in engine.rules()["intents"]:
        a = i["answer"]
        assert "\n" in a or len(sentences(a)) <= 2 or len(a) <= 220, i["key"]
    for key in ("red_flag_answer", "crisis_answer"):
        assert "\n1) " in engine.rules()[key]
