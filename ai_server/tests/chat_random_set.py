"""10 000 different messages, typed the way users really type (Elwin, 15 Oct: "keep on running until the
chatbot can pass 10000 different random wording tests; users type wrongly, or only a few words and
press Enter, in all sorts of conditions").

Each message starts from a question whose right answer is known, then is changed at random the way
people type: typos (a letter dropped, doubled, swapped or a neighbouring key), a missing space,
capitals, "??" or "...", short forms (u, pls, y, wat, tq), "lah"/"ah"/"pls", "hi"/"ok"/"erm" before
it, a Malay word for an English one, or only the important words. It is asked in a random situation:
another plan or none, health conditions and a risk level in the profile, a time of day (late at night
too), a previous answer, and sometimes a user aged 65 or over (whose plans are paused).

Starting questions: the 1 035 hand-written questions (rounds 1-19, the safety passes), the generated
exercise, condition, posture mistake and warning-sign questions, the hand-written few-word messages
(chat_short_forms.py) and the follow-ups. The same seed always gives the same 10 000 messages:
seed 1 is the set the rules were fixed against; seed 2 is a fresh set they never saw.
"""
import random
import re
import sys
from pathlib import Path

sys.path[:0] = [str(Path(__file__).resolve().parent), str(Path(__file__).resolve().parents[1])]

from app.chat import engine  # noqa: E402
from chat_followup_set import FOLLOW_UPS, NO_CONTEXT, variants  # noqa: E402
from chat_short_forms import ALSO, SHORT_FORMS  # noqa: E402

KEYBOARD = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
NEIGHBOURS = {}
for row in KEYBOARD:
    for i, ch in enumerate(row):
        NEIGHBOURS[ch] = (row[i - 1] if i else "") + (row[i + 1] if i + 1 < len(row) else "")

# Words a slip must not touch: they change what is meant ("no pain" / "pain").
PROTECTED = {"no", "not", "dont", "don't", "cant", "can't", "cannot", "never", "without", "isn't", "isnt",
             "won't", "wont", "didn't", "didnt", "tak", "tidak", "bukan", "jangan", "tiada"}
STOP = {"i", "me", "my", "the", "a", "an", "is", "am", "are", "was", "do", "does", "did", "to", "of", "it",
        "this", "that", "please", "could", "should", "would", "will", "be", "there", "so", "just", "really",
        "very", "any", "some", "on", "in", "at", "for", "and", "or", "you", "your", "im", "i'm"}
SHORT = {"you": "u", "your": "ur", "please": "pls", "what": "wat", "why": "y", "because": "bcos",
         "are": "r", "thanks": "tq", "okay": "ok", "how": "hw", "with": "w", "before": "b4", "people": "ppl",
         "know": "noe", "really": "rly", "tomorrow": "tmr", "today": "tdy", "minutes": "mins", "exercise": "exercise"}
MALAY = {"exercise": "senaman", "can": "boleh", "pain": "sakit", "knee": "lutut", "today": "hari ini",
         "why": "kenapa", "what": "apa", "doctor": "doktor", "tired": "penat", "leg": "kaki", "back": "belakang"}
SUFFIX = [" lah", " ah", " pls", " leh", " ya", " huh", " ?"]
PREFIX = ["hi ", "ok ", "erm ", "sorry ", "doc ", "hello ", "excuse me ", "hmm "]
ENDS = ["", "", "", "?", "??", "...", "!", "!!", " ?"]
REFERENCES = {"it", "that", "this"}


def typo(word: str, rng: random.Random) -> str:
    kind = rng.choice(["drop", "double", "swap", "near"])
    i = rng.randrange(1, len(word) - 1)                  # never the first letter
    if kind == "drop":
        return word[:i] + word[i + 1:]
    if kind == "double":
        return word[:i] + word[i] + word[i:]
    if kind == "swap":
        return word[:i] + word[i + 1] + word[i] + word[i + 2:]
    near = NEIGHBOURS.get(word[i], "")
    return word[:i] + rng.choice(near) + word[i + 1:] if near else word


def perturb(text: str, rng: random.Random) -> str:
    """One random way a user might type [text]."""
    words = text.lower().strip().rstrip("?!. ").split()
    if len(words) >= 5 and rng.random() < 0.25:          # only the important words
        kept = [w for w in words if w not in STOP or w in PROTECTED]
        if len(kept) >= 2:
            words = kept
    if rng.random() < 0.3:
        words = [SHORT.get(w, w) if rng.random() < 0.6 else w for w in words]
    if rng.random() < 0.1:
        words = [MALAY.get(w, w) if rng.random() < 0.5 else w for w in words]
    slips = 0 if rng.random() < 0.43 else (1 if rng.random() < 0.8 else 2)
    for _ in range(slips):
        cand = [k for k, w in enumerate(words) if len(w) >= 4 and w.isalpha() and w not in PROTECTED]
        if cand:
            k = rng.choice(cand)
            for _ in range(5):                           # a slip that makes another real word ("jatuh" ->
                slip = typo(words[k], rng)               # "jauh", far) changes the meaning: not a typo
                if slip not in engine._respell_vocab() and slip not in engine.dictionary():
                    words[k] = slip
                    break
    if len(words) >= 3 and rng.random() < 0.05:          # a missing space
        k = rng.randrange(len(words) - 1)
        words[k:k + 2] = [words[k] + words[k + 1]]
    out = " ".join(words)
    if rng.random() < 0.12:
        out = rng.choice(PREFIX) + out
    if rng.random() < 0.15:
        out += rng.choice(SUFFIX)
    out += rng.choice(ENDS)
    r = rng.random()
    if r < 0.2:
        out = out[:1].upper() + out[1:]
    elif r < 0.27:
        out = out.upper()
    return out


def _seeds():
    """(kind, plan, text, acceptable answers) for every starting question."""
    import test_chat
    from evaluate_chat_entities import cases
    out = []
    for plan, q, want in test_chat.ALL_QUESTIONS:
        if want is None or (isinstance(want, str) and "/" in want):
            continue
        out.append(("written", plan, q, set(want) if isinstance(want, tuple) else {want}))
    for group, q, want, _ in cases():
        out.append((group, test_chat.KNEE, q, set(want)))
    for key, forms in SHORT_FORMS.items():
        for q in forms:
            out.append(("short", None, q, set(ALSO.get(q, (key,)))))
    return out


SEEDS = None
CONDITIONS = ["HYPERTENSION", "DIABETES", "HEART_DISEASE", "STROKE", "ARTHRITIS", "OSTEOPOROSIS", "ASTHMA",
              "COPD", "PARKINSONS", "PREGNANCY", "KIDNEY_DISEASE"]


def build(seed: int = 1, n: int = 10_000) -> list[dict]:
    """n different messages, each with its situation and the answers that are right for it."""
    global SEEDS
    if SEEDS is None:
        SEEDS = _seeds()
    rng = random.Random(seed)
    plans = list(engine.rules()["plans"])
    by_kind = {}
    for s in SEEDS:
        by_kind.setdefault(s[0], []).append(s)
    weights = {"written": 30, "short": 25, "exercises": 8, "conditions": 5, "mistakes": 4, "red_flags": 12,
               "follow": 10, "restricted": 6}
    kinds = list(weights)
    rest = engine.rules()["restrictions"]["AGE_65_PLUS"]
    topics = [k for k, i in {i["key"]: i for i in engine.intents_for(plans[0])}.items()
              if not i.get("small_talk") and k != "clarify"]
    seen, out = set(), []
    while len(out) < n:
        kind = rng.choices(kinds, [weights[k] for k in kinds])[0]
        ctx = {"plan_id": None, "previous_category": None, "restriction": None, "conditions": None,
               "risk_level": None, "local_time": None}
        if kind == "follow":
            q = rng.choice(sorted({v for f in FOLLOW_UPS for v in variants(f)} - {"and the"}))
            prev = rng.choice(topics + [None, "greeting", "thanks", "red_flag"])
            ctx.update(plan_id=rng.choice(plans), previous_category=prev)
            want = ({"clarify"} | engine.NO_CONTEXT_ANSWERS) if prev in NO_CONTEXT else {prev}
            text = q
        else:
            pool = by_kind["written"] if kind == "restricted" else by_kind[kind]
            _, plan, q, want = rng.choice(pool)
            text = perturb(q, rng)
            ctx["plan_id"] = plan if plan is not None else rng.choice(plans + [None])
            if any(w and w.startswith("plan_") for w in want) and ctx["plan_id"] is None:
                ctx["plan_id"] = rng.choice(plans)
            if rng.random() < 0.3:
                ctx["conditions"] = rng.sample(CONDITIONS, rng.randint(1, 2))
            if rng.random() < 0.5:
                ctx["risk_level"] = rng.choice(["Low", "Medium", "High"])
            if rng.random() < 0.4:
                ctx["local_time"] = (rng.randrange(24), rng.choice([0, 15, 30, 45]))
            if rng.random() < 0.25:
                prev = rng.choice(topics)
                ctx["previous_category"] = prev
                if engine.pure_follow_up(text):
                    want = {prev}                        # a follow-up of its own continues the topic
                elif (REFERENCES & set(re.findall(r"[a-z]+", text.lower())) and prev.startswith("exercise:")
                      and want & engine.FOLLOW_GENERAL):
                    want = want | {prev}                 # "how many for that one?" after an exercise
            if kind == "restricted":
                ctx["restriction"] = "AGE_65_PLUS"
                safety = {"red_flag", "crisis", "overdose", "poisoning"}
                if not want & safety:
                    want = {("age_limit" if w and engine._restricted(w, rest) else w) for w in want}
        key = (text, ctx["plan_id"], ctx["previous_category"], ctx["restriction"])
        if text.strip() and key not in seen and text not in seen:
            seen.add(key)
            seen.add(text)
            out.append({"kind": kind, "text": text, "want": sorted(want, key=str), "context": ctx,
                        "seed_question": q})
    return out
