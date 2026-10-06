"""Scores the chatbot rules on the three question sets and lists every miss.

    cd ai_server
    .venv\\Scripts\\python evaluate_chat.py            (summary + misses)
    .venv\\Scripts\\python evaluate_chat.py --csv out.csv   (every question, for the test-case table)

Sets: tests/chat_eval_set.py (used to write the rules), tests/chat_holdout_set.py (used for one
round of fixes), tests/chat_verify_set.py and tests/chat_final_set.py (fresh checks; first-run
scores 20/35 with rules v2 and 28/35 with rules v3). See their docstrings.
"""
import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "tests"))

from chat_eval_set import EVAL  # noqa: E402
from chat_holdout_set import HOLDOUT, KNEE  # noqa: E402
from chat_verify_set import VERIFY  # noqa: E402
from chat_final_set import FINAL  # noqa: E402

from app.chat import engine  # noqa: E402

SETS = {"tuning": [(KNEE, q, e) for q, e in EVAL], "held-out": HOLDOUT, "verify": VERIFY, "final": FINAL}


def ok(got, expected) -> bool:
    return got in expected if isinstance(expected, tuple) else got == expected


def main():
    rows, total, passed = [], 0, 0
    for name, data in SETS.items():
        bad = 0
        for plan, question, expected in data:
            r = engine.reply(plan, None, question)
            good = ok(r["category"], expected)
            bad += not good
            rows.append({"set": name, "plan": engine.rules()["plans"].get(plan, {}).get("plan_name", ""),
                         "question": question,
                         "expected": " or ".join(map(str, expected)) if isinstance(expected, tuple) else str(expected),
                         "got": str(r["category"]), "matched_by": str(r["matched_by"]), "pass": good,
                         "answer": r["answer"]})
            if not good:
                print(f"  MISS [{name}] {question!r:55s} expected={expected} got={r['category']} ({r['matched_by']})")
        total += len(data)
        passed += len(data) - bad
        print(f"{name:9s}: {len(data) - bad}/{len(data)}")
    print(f"all      : {passed}/{total} ({passed / total:.0%})   rules {engine.rules()['version']}")
    if "--csv" in sys.argv:
        out = Path(sys.argv[sys.argv.index("--csv") + 1])
        with out.open("w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0]))
            w.writeheader()
            w.writerows(rows)
        print(f"written {out}")


if __name__ == "__main__":
    main()
