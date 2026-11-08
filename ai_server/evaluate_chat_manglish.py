"""Manglish sentence shapes (tests/chat_manglish_set.py). Writes docs/chat_manglish_eval.json.

    .venv\\Scripts\\python evaluate_chat_manglish.py [seed] [n]

Each message is one of the chatbot's English questions rewritten in a Manglish shape ("exercise can or
not", "got knee pain"); right when the answer is one of the question's own topics.
"""
import json
import sys
import time
from collections import Counter
from pathlib import Path

sys.path[:0] = [str(Path(__file__).parent), str(Path(__file__).parent / "tests")]
from app.chat import engine  # noqa: E402
from chat_manglish_set import build, seeds  # noqa: E402

URGENT = {"red_flag", "crisis"}


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 2000
    t0 = time.time()
    cases = build(seed, n)
    ok = urgent_ok = urgent_n = 0
    misses = Counter()
    for c in cases:
        x = engine.reply(c["plan_id"], None, c["text"])
        got = x["category"] if x["is_matched"] else None
        good = got in c["want"]
        ok += good
        if set(c["want"]) <= URGENT:
            urgent_n += 1
            urgent_ok += good
        if not good:
            misses[f"{c['text']!r} -> {got} (want {c['want'][:2]}; from {c['seed_question']!r})"] += 1
    report = {"rules_version": engine.rules()["version"], "seed": seed, "messages": n, "questions": len(seeds()),
              "passed": ok, "rate": round(ok / n, 4), "warning_signs": urgent_n, "warning_signs_passed": urgent_ok,
              "misses": [m for m, _ in misses.most_common(300)], "seconds": round(time.time() - t0)}
    out = Path(__file__).parent / "docs" / "chat_manglish_eval.json"
    out.write_text(json.dumps(report, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"seed {seed}: {ok}/{n} ({100 * ok / n:.2f}%), "
          f"from {report['questions']} questions -> {out}")


if __name__ == "__main__":
    main()
