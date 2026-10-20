"""Random characters (tests/chat_noise_set.py). Writes docs/chat_noise_eval.json.

    .venv\\Scripts\\python evaluate_chat_noise.py [seed] [n]

  noise   n messages with nothing to answer. Right: not recognised, "tell me a bit more" (clarify), or the
          language answer for another script. Wrong: any other topic; worst: an emergency answer.
  noisy   n questions with known answers, random characters added. Right: the same answer as without.
  blns    the Big List of Naughty Strings (515 strings that break input handling: odd Unicode, emoji,
          injection, scripts, zero-width; minimaxir/big-list-of-naughty-strings, MIT). Right: as noise.
  clinc   CLINC150's test questions of its 150 domains, except the ones that overlap with this chatbot
          (build_domain_words.OVERLAP): real questions about banking, travel, cars... Right: as noise.
  oos     CLINC150's 1 100 held-out out-of-scope questions ("how much has the dow changed today"; clinc/oos-eval,
          CC BY 3.0): real questions with no rehabilitation meaning. Right: as noise.
Every reply must come back without an error, also for the very long ones. The two downloaded files are in
training/data/public/input_tests (with their licences).
"""
import json
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

sys.path[:0] = [str(Path(__file__).parent), str(Path(__file__).parent / "tests")]
import random  # noqa: E402

from app.chat import engine  # noqa: E402
from chat_noise_set import add_noise, noise  # noqa: E402
from chat_round1_set import KNEE  # noqa: E402

URGENT = {"red_flag", "crisis", "overdose", "poisoning"}
FINE_FOR_NOISE = {None, "clarify", "language", "greeting", "acknowledge", "thanks", "goodbye"}


def seeds():
    import test_chat
    return [(p, q, set(w) if isinstance(w, tuple) else {w}) for p, q, w in test_chat.ALL_QUESTIONS
            if w is not None and not (isinstance(w, str) and "/" in w)]


EXTERNAL = Path(__file__).resolve().parents[1] / "training" / "data" / "public" / "input_tests"


def external():
    out = []
    blns = EXTERNAL / "blns.json"
    if blns.exists():
        out += [("blns", "blns", KNEE, s, FINE_FOR_NOISE) for s in json.loads(blns.read_text(encoding="utf-8"))]
    clinc = EXTERNAL / "clinc_data_full.json"
    if clinc.exists():
        d = json.loads(clinc.read_text(encoding="utf-8"))
        # oos_train and train were used to learn other_domain_words.json: only the held-out splits here.
        out += [("oos", "oos", KNEE, q, FINE_FOR_NOISE) for split in ("oos_val", "oos_test") for q, _ in d[split]]
        from app.chat.build_domain_words import OVERLAP
        out += [("clinc", intent, KNEE, q, FINE_FOR_NOISE) for q, intent in d["test"] if intent not in OVERLAP]
    return out


def cases(seed: int, n: int):
    rng = random.Random(seed)
    out = external()
    for _ in range(n):
        kind, t = noise(rng)
        out.append(("noise", kind, KNEE, t, FINE_FOR_NOISE))
    base = seeds()
    for _ in range(n):
        plan, q, want = rng.choice(base)
        how, t = add_noise(q, rng)
        out.append(("noisy", how, plan, t, want))
    return out


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 2000
    t0 = time.time()
    res = defaultdict(lambda: [0, 0])
    misses, errors, alarms = Counter(), [], []
    slowest = 0.0
    for group, kind, plan, text, want in cases(seed, n):
        s = time.time()
        try:
            x = engine.reply(plan, None, text)
        except Exception as e:                                     # must never happen
            errors.append(f"{text[:60]!r}: {type(e).__name__}: {e}")
            res[group][1] += 1
            continue
        slowest = max(slowest, time.time() - s)
        got = x["category"] if x["is_matched"] else None
        good = got in want
        if group in ("noise", "blns", "oos", "clinc") and got in URGENT:
            alarms.append(f"{kind}: {text[:60]!r} -> {got}")
        res[group][0] += good
        res[group][1] += 1
        if not good:
            misses[f"{group}/{kind}: {text[:50]!r} -> {got}" + ("" if group == "noise" else f" (want {sorted(map(str, want))})")] += 1
    report = {"rules_version": engine.rules()["version"], "seed": seed, "per_group": n,
              "noise_ok": res["noise"][0], "noise": res["noise"][1],
              "noisy_ok": res["noisy"][0], "noisy": res["noisy"][1],
              "blns_ok": res["blns"][0], "blns": res["blns"][1], "oos_ok": res["oos"][0], "oos": res["oos"][1],
              "clinc_ok": res["clinc"][0], "clinc": res["clinc"][1],
              "false_emergencies": alarms, "errors": errors, "slowest_reply_sec": round(slowest, 3),
              "misses": [m for m, _ in misses.most_common(200)], "seconds": round(time.time() - t0)}
    out = Path(__file__).parent / "docs" / "chat_noise_eval.json"
    out.write_text(json.dumps(report, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"blns: {report['blns_ok']}/{report['blns']}  oos: {report['oos_ok']}/{report['oos']}  "
          f"clinc other domains: {report['clinc_ok']}/{report['clinc']}  "
          f"noise: {report['noise_ok']}/{report['noise']}  noisy: {report['noisy_ok']}/{report['noisy']}  "
          f"false emergencies: {len(alarms)}  errors: {len(errors)}  slowest {report['slowest_reply_sec']} s")
    print("wrote", out)


if __name__ == "__main__":
    main()
