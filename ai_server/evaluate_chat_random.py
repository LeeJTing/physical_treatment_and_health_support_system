"""The 10 000-message random wording test (tests/chat_random_set.py): messages typed the way users type,
in random situations. Writes docs/chat_random_eval_seed<N>.json.

    .venv\\Scripts\\python evaluate_chat_random.py [seed]      (seed 1: the set the rules were fixed
                                                             against; seed 2: a fresh set)
"""
import json
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

sys.path[:0] = [str(Path(__file__).parent), str(Path(__file__).parent / "tests")]
from app.chat import engine  # noqa: E402
from chat_random_set import build  # noqa: E402


def run(cases):
    by_kind = defaultdict(lambda: [0, 0])
    misses = []
    for c in cases:
        x = engine.reply(c["context"]["plan_id"], None, c["text"], conditions=c["context"]["conditions"],
                         risk_level=c["context"]["risk_level"], local_time=c["context"]["local_time"],
                         previous_category=c["context"]["previous_category"],
                         restriction=c["context"]["restriction"])
        got = x["category"] if x["is_matched"] else None
        ok = got in c["want"]
        by_kind[c["kind"]][0] += ok
        by_kind[c["kind"]][1] += 1
        if not ok:
            misses.append({**c, "got": got})
    return by_kind, misses


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    t0 = time.time()
    cases = build(seed)
    by_kind, misses = run(cases)
    total = sum(v[0] for v in by_kind.values())
    print(f"seed {seed}: {total}/{len(cases)} ({total / len(cases):.2%}) in {time.time() - t0:.0f}s")
    for k, (good, n) in sorted(by_kind.items()):
        print(f"  {k:11} {good}/{n} ({good / n:.1%})")
    pairs = Counter((tuple(m["want"]) if len(m["want"]) < 4 else m["want"][0], m["got"]) for m in misses)
    report = {"rules_version": engine.rules()["version"], "seed": seed, "messages": len(cases),
              "passed": total, "rate": round(total / len(cases), 4),
              "by_kind": {k: {"passed": g, "messages": n} for k, (g, n) in by_kind.items()},
              "commonest_misses": [f"{w} -> {g}: {c}" for (w, g), c in pairs.most_common(40)],
              "misses": [{"text": m["text"], "want": [str(w) for w in m["want"]], "got": m["got"],
                          "seed_question": m["seed_question"], "context": m["context"]} for m in misses[:400]]}
    out = Path(__file__).parent / "docs" / f"chat_random_eval_seed{seed}.json"
    out.write_text(json.dumps(report, indent=1, default=str), encoding="utf-8")
    print("wrote", out)


if __name__ == "__main__":
    main()
