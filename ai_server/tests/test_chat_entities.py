"""Every exercise, condition and posture mistake asked about in many ways (chat-rules-3.54). A sample of
evaluate_chat_entities.py's generated questions, so the suite stays quick."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from evaluate_chat_entities import KNEE, cases, engine  # noqa: E402

CASES = list(cases())
SAMPLE = CASES[::5]                                     # every fifth question of each group


@pytest.mark.parametrize("group", ["exercises", "conditions", "mistakes"])
def test_sample(group):
    wrong = []
    for g, q, want, detail in SAMPLE:
        if g != group:
            continue
        x = engine.reply(KNEE, None, q)
        got = x["category"] if x["is_matched"] else None
        if got not in want or (detail is not None and detail not in x["answer"]):
            wrong.append((q, got))
    assert not wrong, wrong[:20]


@pytest.mark.parametrize("q, want", [
    ("how to do sit-tostand", "exercise:sit_to_stand"),     # a slip inside the name
    ("wall pus-up", "exercise:wall_push_up"),
    ("heel raise", "exercise:heel_raise"),                  # not the mistake "heels lift"
    ("heels lift?", "mistake:heels_lift"),
    ("open and close", "exercise:hand_open_close"),         # not goodbye
    ("do i rest between exercises", ("how_to", "how_often", "plan_exercises")),   # no exercise name
    ("saya ada darah tinggi", "condition_advice"),
    ("angin ahmar boleh exercise?", "condition_advice"),
])
def test_examples(q, want):
    x = engine.reply(KNEE, None, q)
    assert x["category"] in (want if isinstance(want, tuple) else (want,)), (q, x["category"])
