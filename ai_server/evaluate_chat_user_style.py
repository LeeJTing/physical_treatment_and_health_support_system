"""Messages like the ones Elwin reported (tests/chat_user_style_set.py). Writes docs/chat_user_style_eval.json.

    .venv\\Scripts\\python evaluate_chat_user_style.py [seed] [n]

Right when the answer's topic is one the pattern expects ("None" = not recognised, the message echoed
back). The 21 reported questions are checked first, then n random messages in their patterns.
"""
import json
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

sys.path[:0] = [str(Path(__file__).parent), str(Path(__file__).parent / "tests")]
from app.chat import engine  # noqa: E402
from chat_user_style_set import REPORTED, build  # noqa: E402

PLAN = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"            # the knee plan, as in the random typing test


def got(text, previous=None):
    x = engine.reply(PLAN, None, text, previous_category=previous)
    return x["category"] if x["is_matched"] else None, x["answer"]


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 2000
    t0 = time.time()
    reported = []
    for q, want in REPORTED:
        g, answer = got(q)
        reported.append({"question": q, "want": sorted(map(str, want)), "got": str(g), "ok": g in want,
                         "answer": answer[:200]})
    res, misses = defaultdict(lambda: [0, 0]), Counter()
    for c in build(seed, n):
        g, _ = got(c["text"], c["previous_category"])
        ok = str(g) in c["want"]
        res[c["kind"]][0] += ok
        res[c["kind"]][1] += 1
        if not ok:
            misses[f"{c['kind']}: {c['text']!r} -> {g} (want {c['want']}; from {c['base']!r})"] += 1
    passed = sum(a for a, _ in res.values())
    report = {"rules_version": engine.rules()["version"], "seed": seed, "messages": n,
              "reported_ok": sum(r["ok"] for r in reported), "reported": reported,
              "passed": passed, "rate": round(passed / n, 4),
              "by_kind": {k: {"passed": a, "messages": b} for k, (a, b) in sorted(res.items())},
              "misses": [m for m, _ in misses.most_common(200)], "seconds": round(time.time() - t0)}
    out = Path(__file__).parent / "docs" / "chat_user_style_eval.json"
    out.write_text(json.dumps(report, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"reported: {report['reported_ok']}/{len(REPORTED)}  seed {seed}: {passed}/{n} ({100 * passed / n:.2f}%)")
    for k, v in report["by_kind"].items():
        print(f"  {k:12} {v['passed']}/{v['messages']}")
    print("wrote", out)


if __name__ == "__main__":
    main()
