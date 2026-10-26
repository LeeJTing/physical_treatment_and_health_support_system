"""Turns the chatbot's unrecognised questions into its next round of rules, so it keeps improving.

The chatbot is rule-based: it does not learn by itself (a health answer must be written and checked,
not guessed). It improves in rounds: questions -> honest first score -> new or wider rules -> every
earlier question set still passes (tests/test_chat.py). Rounds 1-17 used questions we wrote; this
script feeds a round with the questions real users asked and the rules did not recognise.

Every chat is stored in Supabase chat_message (Table 4.99); a patient question that was not recognised
has is_matched = false. Export them in the Supabase Dashboard -> SQL editor (Elwin), and download the
result as CSV:

    select message_text, count(*) as times, max(created_at) as last_asked
    from public.chat_message
    where sender = 'PATIENT' and is_matched = false
    group by message_text
    order by times desc;

Then:

    cd ai_server
    .venv\\Scripts\\python chat_backlog.py backlog.csv [--draft tests/chat_round18_set.py]

For each question (near-duplicates grouped): what the CURRENT rules answer (newer rules may already
recognise it) and the two nearest rules, to show which rule to widen or that a new one is needed.
--draft writes the still-unrecognised ones as a question set with "TODO" answers: fill in the
expected rule, run it once for the honest score, then change the rules.

Reports ("Report this answer" under a chat answer, table chat_report, 11 Oct): a patient says an answer
was wrong, optionally what they expected and which topic they meant. Nothing changes on its own; export
the NEW ones in the SQL editor and save the result as backlog_reports.csv:

    select r.report_id, r.created_at, r.question_text, r.answer_category, r.matched_by,
           r.expected_text, r.wanted_category, r.answer_text
    from public.chat_report r
    where r.status = 'NEW'
    order by r.created_at;

    .venv\\Scripts\\python chat_backlog.py [backlog.csv] --reports backlog_reports.csv [--draft ...]

Each report gets one verdict (what the reviewer should do):
    FIXED    the current rules already answer the topic the patient meant -> mark ADDED (no work)
    ALIAS    the patient named a topic: add their wording as an example question or keyword of that rule
    CHANGED  no topic named, and the current rules answer differently from the reported answer -> check it
    CHECK    no topic named, same answer: read "expected"; the answer text or a new rule may be needed
    TAPPED   the patient tapped a topic, so the answer text itself is the complaint, not the matching
    SAFETY   a safety answer (urgent symptoms, crisis, overdose): never widen or loosen from a report;
             a doctor-level check only
    UNKNOWN  the topic named is not a rule of the current version (renamed or removed)
Then mark each report in the Dashboard (Table editor, chat_report): status ADDED or REJECTED and a
reviewed_note saying what was added or why not. --draft also writes the ALIAS reports as tests with the
named rule as the expected answer, so the change is checked before and after.

Privacy: the questions come from patients. Keep the CSV on this PC (backlog*.csv is git-ignored),
never paste it into an outside chatbot, and remove names or numbers before a question goes into a
test file.
"""
import argparse
import csv
import re
import sys
from collections import defaultdict
from pathlib import Path

from app.chat import engine


def read(path: Path) -> list[tuple[str, int]]:
    rows = []
    with path.open(encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f):
            text = (r.get("message_text") or "").strip()
            if text:
                rows.append((text, int(r.get("times") or 1)))
    return rows


def grouped(rows: list[tuple[str, int]]) -> list[tuple[str, int, list[str]]]:
    """Near-duplicates ("how to change password?" / "How to change password") count as one."""
    groups: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for text, times in rows:
        groups[re.sub(r"[^a-z0-9 ]", "", engine.clean(text))].append((text, times))
    out = []
    for items in groups.values():
        items.sort(key=lambda x: -x[1])
        out.append((items[0][0], sum(t for _, t in items), [t for t, _ in items[1:]]))
    return sorted(out, key=lambda g: -g[1])


def nearest(text: str, n: int = 2) -> list[tuple[str, float]]:
    scored = [(i["key"], engine.fuzzy_score(text, i)) for i in engine.intents_for(None)]
    return sorted(scored, key=lambda s: -s[1])[:n]


def review(rows: list[tuple[str, int]]) -> list[dict]:
    out = []
    for text, times, variants in grouped(rows):
        r = engine.reply(None, None, text)
        out.append({"question": text, "times": times, "variants": variants,
                    "now": r["category"] if r["is_matched"] else None,
                    "nearest": nearest(text)})
    return out


SAFETY = {"red_flag", "crisis", "overdose", "poisoning"}


def read_reports(path: Path) -> list[dict]:
    """The reviewer's export of NEW chat_report rows (columns as in the SQL above)."""
    keep = ("report_id", "created_at", "question_text", "answer_category", "matched_by",
            "expected_text", "wanted_category", "answer_text")
    rows = []
    with path.open(encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f):
            row = {k: (r.get(k) or "").strip() or None for k in keep}
            if row["question_text"]:
                rows.append(row)
    return rows


def verdict(rep: dict, now: dict, keys: set[str]) -> str:
    wanted = rep["wanted_category"]
    if rep["answer_category"] in SAFETY or rep["matched_by"] in SAFETY or now["category"] in SAFETY:
        return "SAFETY"
    if rep["matched_by"] in ("category", "follow_up"):
        return "TAPPED"
    if wanted and wanted not in keys:
        return "UNKNOWN"
    if wanted:
        return "FIXED" if now["is_matched"] and now["category"] == wanted else "ALIAS"
    return "CHANGED" if now["category"] != rep["answer_category"] else "CHECK"


def review_reports(rows: list[dict]) -> list[dict]:
    intents = {i["key"]: i for i in engine.intents_for(None)}
    out = []
    for rep in rows:
        now = engine.reply(None, None, rep["question_text"])
        wanted = rep["wanted_category"]
        out.append({**rep, "verdict": verdict(rep, now, set(intents)),
                    "now": now["category"] if now["is_matched"] else None,
                    "wanted_score": engine.fuzzy_score(rep["question_text"], intents[wanted])
                    if wanted in intents else None,
                    "nearest": nearest(rep["question_text"])})
    return out


def draft(items: list[dict], reports: list[dict] | None = None) -> str:
    lines = ['"""Draft round from real unrecognised questions (chat_backlog.py). Replace every TODO with the',
             'expected rule key (or None if the chatbot should say "not recognised"), run it once for the honest',
             'score, then change the rules."""', "from chat_round1_set import KNEE", "", "ROUND_NEXT = ["]
    for it in items:
        if it["now"] is None:
            hint = ", ".join(f"{k} {s:.0f}" for k, s in it["nearest"])
            lines.append(f"    (KNEE, {it['question']!r}, \"TODO\"),  # asked {it['times']}x; nearest: {hint}")
    lines.append("]")
    alias = [r for r in reports or [] if r["verdict"] == "ALIAS"]
    if alias:
        lines += ["", "# Reported answers: the rule the patient said they meant (check it is right before using).",
                  "ROUND_REPORTS = ["]
        for r in alias:
            lines.append(f"    (KNEE, {r['question_text']!r}, {r['wanted_category']!r}),"
                         f"  # report {(r['report_id'] or '')[:8]}; answered {r['answer_category']}")
        lines.append("]")
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("csv", type=Path, nargs="?", help="unrecognised questions (chat_message export)")
    ap.add_argument("--reports", type=Path, help="NEW chat_report rows (Report this answer)")
    ap.add_argument("--draft", type=Path, help="write the still-unrecognised questions as a question set")
    a = ap.parse_args()
    if not a.csv and not a.reports:
        ap.error("give the unrecognised questions CSV, --reports, or both")
    items = review(read(a.csv)) if a.csv else []
    still = [it for it in items if it["now"] is None]
    if a.csv:
        print(f"{len(items)} distinct questions; recognised by rules {engine.rules()['version']}: "
          f"{len(items) - len(still)}; still not recognised: {len(still)}\n")
    for it in items:
        status = f"now -> {it['now']}" if it["now"] else "NOT RECOGNISED"
        near = ", ".join(f"{k} {s:.0f}" for k, s in it["nearest"])
        print(f"{it['times']:>4}x  {it['question'][:70]:<70}  {status:<28} nearest: {near}")
    reports = review_reports(read_reports(a.reports)) if a.reports else []
    if a.reports:
        counts = defaultdict(int)
        for r in reports:
            counts[r["verdict"]] += 1
        print(f"\n{len(reports)} reports: " + ", ".join(f"{k} {n}" for k, n in sorted(counts.items())) + "\n")
        for r in reports:
            near = ", ".join(f"{k} {s:.0f}" for k, s in r["nearest"])
            print(f"{r['verdict']:<8} {(r['report_id'] or '?')[:8]}  {r['question_text'][:70]}")
            print(f"         answered {r['answer_category']} ({r['matched_by']}); now {r['now'] or 'not recognised'}"
                  + (f"; meant {r['wanted_category']}" if r["wanted_category"] else "")
                  + (f" (similarity {r['wanted_score']:.0f})" if r["wanted_score"] is not None else "")
                  + f"; nearest: {near}")
            if r["expected_text"]:
                print(f"         expected: {r['expected_text'][:150]}")
    if a.draft:
        a.draft.write_text(draft(items, reports), encoding="utf-8")
        print(f"\ndraft written: {a.draft}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
