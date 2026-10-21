"""Symptoms by their kind (tests/chat_symptoms_set.py). Writes docs/chat_symptoms_eval.json.

    .venv\\Scripts\\python evaluate_chat_symptoms.py [seed] [n]

Right when the answer's topic is the symptom's own: a cramp, pins and needles, stiffness, a stitch, a pulled
muscle, soreness the day after, or a joint that locks.
"""
import json
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

sys.path[:0] = [str(Path(__file__).parent), str(Path(__file__).parent / "tests")]
from app.chat import engine  # noqa: E402
from chat_symptoms_set import build  # noqa: E402


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 2000
    t0 = time.time()
    cases = build(seed, n)
    res, misses = defaultdict(lambda: [0, 0]), Counter()
    for c in cases:
        x = engine.reply(c["plan_id"], None, c["text"])
        got = x["category"] if x["is_matched"] else None
        ok = str(got) in c["want"]
        res[c["kind"]][0] += ok
        res[c["kind"]][1] += 1
        if not ok:
            misses[f"{c['kind']}: {c['text'][:100]!r} -> {got} (want {c['want'][:3]})"] += 1
    passed = sum(a for a, _ in res.values())
    report = {"rules_version": engine.rules()["version"], "seed": seed, "messages": len(cases), "passed": passed,
              "rate": round(passed / len(cases), 4),
              "by_kind": {k: {"passed": a, "messages": b} for k, (a, b) in sorted(res.items())},
              "misses": [m for m, _ in misses.most_common(200)], "seconds": round(time.time() - t0)}
    out = Path(__file__).parent / "docs" / "chat_symptoms_eval.json"
    out.write_text(json.dumps(report, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"seed {seed}: {passed}/{len(cases)} ({100 * passed / len(cases):.2f}%)")
    for k, v in report["by_kind"].items():
        print(f"  {k:16} {v['passed']}/{v['messages']}")


if __name__ == "__main__":
    main()
