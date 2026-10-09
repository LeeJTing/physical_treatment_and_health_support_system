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


def draft(items: list[dict]) -> str:
    lines = ['"""Draft round from real unrecognised questions (chat_backlog.py). Replace every TODO with the',
             'expected rule key (or None if the chatbot should say "not recognised"), run it once for the honest',
             'score, then change the rules."""', "from chat_round1_set import KNEE", "", "ROUND_NEXT = ["]
    for it in items:
        if it["now"] is None:
            hint = ", ".join(f"{k} {s:.0f}" for k, s in it["nearest"])
            lines.append(f"    (KNEE, {it['question']!r}, \"TODO\"),  # asked {it['times']}x; nearest: {hint}")
    lines.append("]")
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("csv", type=Path)
    ap.add_argument("--draft", type=Path, help="write the still-unrecognised questions as a question set")
    a = ap.parse_args()
    items = review(read(a.csv))
    still = [it for it in items if it["now"] is None]
    print(f"{len(items)} distinct questions; recognised by rules {engine.rules()['version']}: "
          f"{len(items) - len(still)}; still not recognised: {len(still)}\n")
    for it in items:
        status = f"now -> {it['now']}" if it["now"] else "NOT RECOGNISED"
        near = ", ".join(f"{k} {s:.0f}" for k, s in it["nearest"])
        print(f"{it['times']:>4}x  {it['question'][:70]:<70}  {status:<28} nearest: {near}")
    if a.draft:
        a.draft.write_text(draft(items), encoding="utf-8")
        print(f"\ndraft written: {a.draft}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
