"""Messages with a number in them (tests/chat_numbers_set.py). Writes docs/chat_numbers_eval.json.

    .venv\\Scripts\\python evaluate_chat_numbers.py [seed] [n]

Right when the answer's topic is one the number calls for: "pain 8/10" is sharp pain, "spo2 90" urgent,
"i am 75" the age limit. Urgent messages are counted apart: missing one is the worst mistake.
"""
import json
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

sys.path[:0] = [str(Path(__file__).parent), str(Path(__file__).parent / "tests")]
from app.chat import engine  # noqa: E402
from chat_numbers_set import build  # noqa: E402


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 2000
    t0 = time.time()
    cases = build(seed, n)
    res, urgent, misses = defaultdict(lambda: [0, 0]), [0, 0], Counter()
    for c in cases:
        x = engine.reply(c["plan_id"], None, c["text"])
        got = x["category"] if x["is_matched"] else None
        ok = str(got) in c["want"]
        res[c["kind"]][0] += ok
        res[c["kind"]][1] += 1
        if c["urgent"]:
            urgent[0] += ok
            urgent[1] += 1
        if not ok:
            misses[f"{c['kind']}: {c['text'][:100]!r} -> {got} (want {c['want'][:3]})"] += 1
    passed = sum(a for a, _ in res.values())
    report = {"rules_version": engine.rules()["version"], "seed": seed, "messages": len(cases), "passed": passed,
              "rate": round(passed / len(cases), 4), "urgent": urgent[1], "urgent_passed": urgent[0],
              "by_kind": {k: {"passed": a, "messages": b} for k, (a, b) in sorted(res.items())},
              "misses": [m for m, _ in misses.most_common(200)], "seconds": round(time.time() - t0)}
    out = Path(__file__).parent / "docs" / "chat_numbers_eval.json"
    out.write_text(json.dumps(report, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"seed {seed}: {passed}/{len(cases)} ({100 * passed / len(cases):.2f}%), urgent {urgent[0]}/{urgent[1]}")
    for k, v in report["by_kind"].items():
        print(f"  {k:14} {v['passed']}/{v['messages']}")


if __name__ == "__main__":
    main()
