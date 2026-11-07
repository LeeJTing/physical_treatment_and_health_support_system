"""Malay as it is texted (21 Oct): the chatbot's questions that are mostly Malay, typed the way Malaysians
text - vowels dropped ("sakit" -> "skt", "jalan" -> "jln", "berapa" -> "brp"), "tak"/"tidak" as "x"
joined to the next word ("xboleh", "xleh"), "saya" as "sy"/"sya", "nak" as "nk", "-lah" joined on,
English short forms, a slip or two, capitals and "??". The texting forms are made here by rule, not
taken from the engine's own list (engine.SHORT_WORDS_TYPED), so this measures how well Malay texting is
read in general. evaluate_chat_malay.py runs it.
"""
import random
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_random_set import ENDS, typo  # noqa: E402

from app.chat import engine  # noqa: E402

# Malay words (not English ones that look the same) used to find the mostly-Malay questions.
MALAY_WORDS = (set(engine.COMMON_MALAY) | set(engine.MALAY) | set(engine.MALAY_GRAMMAR)
               | {w for p in engine.MALAY_PHRASES for w in p.split()}
               | {"sakit", "lutut", "kaki", "tangan", "senaman", "bersenam", "dada", "nafas", "bernafas",
                  "jatuh", "pening", "pitam", "pengsan", "penat", "lemah", "bengkak", "berdebar", "jantung"})
MALAY_WORDS -= {"ok", "lah", "ah", "boss", "high", "i", "a", "on", "or", "to", "is", "it", "in", "at", "so",
                "no", "do", "go", "me", "my", "we", "he", "be", "up", "us", "as", "an", "am", "of", "by"}
JOIN_X = {"tak", "tidak", "tk"}
WHOLE = {"saya": ["sy", "sya", "saya"], "nak": ["nk", "nak"], "tak": ["x", "tk", "tak"], "tidak": ["x", "tak"],
         "boleh": ["blh", "bole", "boleh"], "dengan": ["dgn", "dengan"], "untuk": ["utk", "untuk"],
         "yang": ["yg", "yang"], "sangat": ["sgt", "sangat"]}
VOWELS = re.compile(r"[aeiou]")


def malay_share(text: str) -> float:
    words = re.findall(r"[a-z']+", text.lower())
    return sum(w in MALAY_WORDS for w in words) / len(words) if words else 0.0


def texted(text: str, rng: random.Random) -> str:
    """One way of texting [text] in Malay shorthand."""
    words = text.lower().strip().rstrip("?!. ").split()
    out = []
    for w in words:
        if w in WHOLE and rng.random() < 0.7:
            w = rng.choice(WHOLE[w])
        elif w in MALAY_WORDS and len(w) >= 4 and w.isalpha() and rng.random() < (0.5 if len(w) <= 6 else 0.15):
            w = w[0] + VOWELS.sub("", w[1:])               # "sakit" -> "skt"; long words less often
        out.append(w)
    for k in range(len(out) - 1):                         # "tak boleh" -> "xboleh" / "xblh"
        if words[k] in JOIN_X and out[k] in ("x", "tk") and rng.random() < 0.5:
            out[k:k + 2] = ["x" + out[k + 1], ""]
    out = [w for w in out if w]
    if out and rng.random() < 0.15 and out[-1].isalpha():
        out[-1] += "lah"                                 # "-lah" joined on
    if rng.random() < 0.3:                               # a slip in a longer word still written in full
        cand = [k for k, w in enumerate(out) if len(w) >= 5 and w.isalpha() and VOWELS.search(w[1:])]
        if cand:
            k = rng.choice(cand)
            for _ in range(5):                           # not one that makes another real word ("jatuh" ->
                slip = typo(out[k], rng)                 # "jauh", far; "malam" -> "makam")
                if slip not in engine._respell_vocab() and slip not in engine.dictionary():
                    out[k] = slip
                    break
    s = " ".join(out) + rng.choice(ENDS)
    return s.upper() if rng.random() < 0.08 else s


def seeds():
    """(plan, question, wanted topics) for the chatbot's questions that are at least half Malay."""
    import test_chat
    from chat_redflag_set import SYMPTOMS, TEMPLATES, URGENT
    out = []
    for p, q, w in test_chat.ALL_QUESTIONS:
        if w is None or (isinstance(w, str) and "/" in w) or malay_share(q) < 0.5:
            continue
        out.append((p, q, set(w) if isinstance(w, tuple) else {w}))
    for s in SYMPTOMS:                                    # the warning signs, said in Malay
        for t in TEMPLATES:
            q = t.format(s=s)
            if malay_share(q) >= 0.5:
                out.append((None, q, set(URGENT)))
    return out


def build(seed: int, n: int = 2000) -> list[dict]:
    rng = random.Random(seed)
    base = seeds()
    signs = [s for s in base if s[0] is None and s[2] == {"red_flag", "crisis"}]
    questions = [s for s in base if s not in signs]
    cases = []
    for _ in range(n):                                   # 60 % questions, 40 % warning signs
        p, q, want = rng.choice(questions if rng.random() < 0.6 else signs)
        cases.append({"plan_id": p, "seed_question": q, "text": texted(q, rng), "want": sorted(map(str, want))})
    return cases
