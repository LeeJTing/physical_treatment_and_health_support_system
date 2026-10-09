"""chat_backlog.py: the unrecognised questions saved in chat_message become the next round of rules."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import chat_backlog  # noqa: E402


def test_groups_duplicates_and_tells_recognised_from_new(tmp_path):
    csv = tmp_path / "backlog.csv"
    csv.write_text(
        "message_text,times,last_asked\n"
        "How do I change my password?,3,2026-10-09\n"
        "how do i change my password,2,2026-10-09\n"
        "zxqv blorp,1,2026-10-09\n",
        encoding="utf-8",
    )
    items = chat_backlog.review(chat_backlog.read(csv))
    assert len(items) == 2                                   # the two password questions are one
    top = items[0]
    assert top["times"] == 5 and top["now"] == "change_password"   # recognised by newer rules
    assert items[1]["now"] is None                           # still to do

    draft = tmp_path / "round.py"
    draft.write_text(chat_backlog.draft(items), encoding="utf-8")
    text = draft.read_text(encoding="utf-8")
    assert "zxqv blorp" in text and "TODO" in text and "change my password" not in text
    compile(text, str(draft), "exec")                        # a valid Python question set
