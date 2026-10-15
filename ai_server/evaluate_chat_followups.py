"""Every short follow-up after every previous answer (chat-rules-3.53, Elwin 14 Oct: "handle single or
double words like 'how to' and link back to the previous response; make thousands of combinations,
then fix them"). Writes docs/chat_followup_eval.json.

    .venv\Scripts\python evaluate_chat_followups.py

  follow_ups   every follow-up in tests/chat_followup_set.py x every previous answer: continues it
               (or, with nothing to continue, asks for more or gives the general answer)
  messy        every typed variant (capitals, punctuation, "ok ...", "... lah", short forms, typos)
               x 10 previous answers
  controls     questions with a topic of their own x every previous answer: answered for themselves
"""
import json
import sys
import time
from collections import Counter
from pathlib import Path

sys.path[:0] = [str(Path(__file__).parent), str(Path(__file__).parent / "tests")]
from app.chat import engine  # noqa: E402
from chat_followup_set import CONTROLS, FOLLOW_UPS, NO_CONTEXT, variants  # noqa: E402
from chat_round1_set import KNEE  # noqa: E402

BY_KEY = {i["key"]: i for i in engine.intents_for(KNEE)}
TOPICS = [None] + [k for k in BY_KEY if k != "clarify"] + ["red_flag", "crisis", "overdose", "poisoning"]
MESSY_TOPICS = ["exercise:heel_raise", "pain_or_discomfort", "delete_account", "posture_result", "red_flag",
                "risk_level", "plan_exercises", "mistake:low_range", None, "thanks"]


def got(text, previous):
    r = engine.reply(KNEE, None, text, previous_category=previous)
    return r["category"] if r["is_matched"] else None


def ok(text, previous, g):
    return g in (({"clarify"} | engine.NO_CONTEXT_ANSWERS) if previous in NO_CONTEXT else {previous})


def run(pairs):
    n = good = 0
    misses = Counter()
    for q, p in pairs:
        g = got(q, p)
        n += 1
        if ok(q, p, g):
            good += 1
        else:
            misses[f"{q!r} after {p} -> {g}"] += 1
    return {"pairs": n, "correct": good, "rate": round(good / n, 4), "misses": [m for m, _ in misses.most_common(30)]}


def main():
    t0 = time.time()
    messy_qs = sorted({v for q in FOLLOW_UPS for v in variants(q)})
    report = {
        "rules_version": engine.rules()["version"],
        "topics": len(TOPICS), "follow_ups": len(FOLLOW_UPS), "messy_variants": len(messy_qs),
        "follow_ups_result": run([(q, p) for p in TOPICS for q in FOLLOW_UPS]),
        "messy_result": run([(q, p) for p in MESSY_TOPICS for q in messy_qs]),
    }
    n = good = 0
    misses = []
    for p in TOPICS:
        for q, want in CONTROLS:
            n += 1
            g = got(q, p)
            good += g == want
            if g != want:
                misses.append(f"{q!r} after {p} -> {g} (want {want})")
    report["controls_result"] = {"pairs": n, "correct": good, "rate": round(good / n, 4), "misses": misses[:30]}
    report["seconds"] = round(time.time() - t0)
    out = Path(__file__).parent / "docs" / "chat_followup_eval.json"
    out.write_text(json.dumps(report, indent=1), encoding="utf-8")
    for k in ("follow_ups_result", "messy_result", "controls_result"):
        r = report[k]
        print(f"{k:18} {r['correct']}/{r['pairs']} ({r['rate']:.2%})")
    print("wrote", out)


if __name__ == "__main__":
    main()
