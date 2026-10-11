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


def test_reports_get_a_verdict_and_alias_reports_go_into_the_draft(tmp_path):
    csv = tmp_path / "backlog_reports.csv"
    csv.write_text(
        "report_id,created_at,question_text,answer_category,matched_by,expected_text,wanted_category,answer_text\n"
        "aaaaaaaa-1,2026-10-11,how do i change password,diet,keyword,,change_password,x\n"
        "bbbbbbbb-2,2026-10-11,what can i eat,diet,keyword,food for my knee,pain_or_discomfort,x\n"
        "cccccccc-3,2026-10-11,I feel chest pain and cant breathe,red_flag,red_flag,,diet,x\n"
        "dddddddd-4,2026-10-11,Diet,diet,category,more detail please,,x\n"
        "eeeeeeee-5,2026-10-11,my knee hurts,pain_or_discomfort,keyword,,no_such_rule,x\n"
        "ffffffff-6,2026-10-11,my knee hurts,how_to,keyword,,,x\n"
        "gggggggg-7,2026-10-11,what can i eat,diet,keyword,,,x\n",
        encoding="utf-8",
    )
    reports = chat_backlog.review_reports(chat_backlog.read_reports(csv))
    assert [r["verdict"] for r in reports] == ["FIXED", "ALIAS", "SAFETY", "TAPPED", "UNKNOWN", "CHANGED", "CHECK"]
    assert reports[1]["expected_text"] == "food for my knee" and reports[1]["wanted_score"] is not None

    text = chat_backlog.draft([], reports)
    assert "ROUND_REPORTS" in text and "'what can i eat', 'pain_or_discomfort'" in text
    assert "chest pain" not in text                          # a safety answer never becomes a test from a report
    compile(text, "round.py", "exec")
