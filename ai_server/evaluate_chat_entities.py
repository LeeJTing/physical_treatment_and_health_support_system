"""Every exercise, health condition and posture mistake asked about in many ways (chat-rules-3.54;
tests/chat_entity_set.py). Writes docs/chat_entity_eval.json.

    .venv\\Scripts\\python evaluate_chat_entities.py

  exercises   each exercise's name, 3 other names and a typo x 24 question templates -> that exercise
              (or the answer the template also allows); x 4 pain templates -> the pain answer
  conditions  16 conditions x 2-4 ways to name them (everyday, Malay) x 10 templates -> condition advice
              that includes that condition's own detail
  mistakes    every posture mistake name x 6 templates -> that mistake's explanation
  red_flags   44 warning signs (English, Manglish, Malay) x 15 templates -> the urgent safety answer
              (tests/chat_redflag_set.py)
"""
import json
import sys
import time
from pathlib import Path

sys.path[:0] = [str(Path(__file__).parent), str(Path(__file__).parent / "tests")]
from app.chat import engine  # noqa: E402
from chat_entity_set import (CONDITION_NAMES, CONDITION_TEMPLATES, EXERCISE_TEMPLATES,  # noqa: E402
                             MISTAKE_TEMPLATES, PAIN_TEMPLATES, typo)
from chat_redflag_set import SYMPTOMS, TEMPLATES, URGENT  # noqa: E402
from chat_round1_set import KNEE  # noqa: E402

PAIN = {"pain_or_discomfort", "pain_sharp", "pain_mild", "red_flag"}


def cases():
    r = engine.rules()
    for key, ex in r["exercises"].items():
        for name in sorted({ex["name"].lower(), typo(ex["name"].lower()), *ex["aliases"][:3]}):
            for tpl, also in EXERCISE_TEMPLATES:
                yield "exercises", tpl.format(x=name), {f"exercise:{key}", *also}, None
            for tpl in PAIN_TEMPLATES:
                yield "exercises", tpl.format(x=name), PAIN, None
    for code, names in CONDITION_NAMES.items():
        for name in names:
            for tpl in CONDITION_TEMPLATES:
                yield "conditions", tpl.format(c=name), {"condition_advice"}, r["condition_detail"][code][:60]
    for name, key in r["glossary"].items():
        for tpl in MISTAKE_TEMPLATES:
            yield "mistakes", tpl.format(m=name), {key}, None
    for s in SYMPTOMS:
        for tpl in TEMPLATES:
            yield "red_flags", tpl.format(s=s), URGENT, None


def main():
    t0 = time.time()
    report = {"rules_version": engine.rules()["version"]}
    for group, q, want, detail in cases():
        x = engine.reply(KNEE, None, q)
        got = x["category"] if x["is_matched"] else None
        good = got in want and (detail is None or detail in x["answer"])
        g = report.setdefault(group, {"questions": 0, "correct": 0, "misses": []})
        g["questions"] += 1
        g["correct"] += good
        if not good and len(g["misses"]) < 30:
            g["misses"].append(f"{q!r} -> {got}")
    for k in ("exercises", "conditions", "mistakes", "red_flags"):
        g = report[k]
        g["rate"] = round(g["correct"] / g["questions"], 4)
        print(f"{k:11} {g['correct']}/{g['questions']} ({g['rate']:.2%})")
    report["seconds"] = round(time.time() - t0)
    out = Path(__file__).parent / "docs" / "chat_entity_eval.json"
    out.write_text(json.dumps(report, indent=1), encoding="utf-8")
    print("wrote", out)


if __name__ == "__main__":
    main()
