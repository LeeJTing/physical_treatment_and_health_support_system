"""Malaysian English (Manglish) sentence shapes (21 Oct): the chatbot's English questions rewritten the way
Malaysians often write them - "can i exercise?" -> "exercise can or not?", "is it ok to walk" -> "walk ok
or not", "i have knee pain" -> "got knee pain", "my knee hurts" -> "my knee very pain", "i cannot finish"
-> "cannot finish leh", "i finished" -> "finish already", "why" -> "how come", endings lah / leh / lor /
meh / hor / one. The shapes are made by rule here, not from the engine's lists. evaluate_chat_manglish.py
runs it.
"""
import random
import re

ENDINGS = [" lah", " leh", " lor", " meh", " hor", " ah", " one", "", "", ""]
MARKS = ["", "", "?", "??", "!", " ?"]

# (pattern on the lower-cased question, replacements; {0}, {1} are the captured groups)
SHAPES = [
    (r"^can i (.+?)\??$", ["{0} can or not", "can {0} or not", "{0} can ah", "can {0} anot"]),
    (r"^is it (?:ok|okay|safe|alright) (?:to|if i) (.+?)\??$", ["{0} ok or not", "{0} safe or not",
                                                               "{0} can ah", "ok to {0} anot"]),
    (r"^should i (.+?)\??$", ["need to {0} or not", "must {0} ah", "{0} or not"]),
    (r"^do i (?:need|have) to (.+?)\??$", ["need to {0} or not", "must {0} meh", "{0} or not"]),
    (r"^i have (?!been |had |to |done |finished |just )(.+)$", ["got {0}", "i got {0}"]),
    (r"^my (.+?) (?:hurts|is painful|is sore|aches)(.*)$", ["my {0} very pain{1}", "{0} so pain{1}",
                                                            "my {0} pain{1}", "{0} painful{1}"]),
    (r"^i (?:cannot|can't|cant|can not) (.+)$", ["cannot {0}", "cannot {0} leh", "{0} cannot"]),
    (r"^i (?:finished|have finished|completed|did) (.+)$", ["finish {0} already", "{0} done already",
                                                            "done {0} liao"]),
    (r"^why (?:is|does|do|did|am|are) (.+?)\??$", ["how come {0}", "why {0} one", "why {0} ah"]),
    (r"^what should i do(.*)$", ["then how{0}", "how ah{0}", "what to do{0}"]),
    (r"^how (?:do|should|can) i (.+?)\??$", ["how to {0}", "{0} how", "how {0} ah", "{0} how ah"]),
    (r"^(?:it is|it's) too (.+?)\??$", ["too {0} lah", "very {0} one", "so {0}"]),
    (r"^where (?:is|are|do i find) (.+?)\??$", ["{0} where", "where got {0}", "{0} at where"]),
]


def manglish(text: str, rng: random.Random) -> str | None:
    """The question in a Manglish shape, or None when no shape fits it."""
    q = " ".join(text.lower().strip().split())
    fits = [(p, outs) for p, outs in SHAPES if re.match(p, q)]
    if not fits:
        return None
    p, outs = rng.choice(fits)
    m = re.match(p, q)
    s = rng.choice(outs).format(*[(g or "") for g in m.groups()])
    s = re.sub(r"\s+", " ", s).strip(" ?")
    if s.split()[-1] not in ("ah", "meh", "one", "leh", "lah", "liao", "anot", "already"):
        s += rng.choice(ENDINGS)                         # one particle at the end, not two
    return s + rng.choice(MARKS)


def seeds():
    """(plan, question, wanted topics) for the chatbot's English questions that a shape fits."""
    import test_chat
    probe = random.Random(0)
    out = []
    for p, q, w in test_chat.ALL_QUESTIONS:
        if w is None or (isinstance(w, str) and "/" in w):
            continue
        if manglish(q, probe) is not None:
            out.append((p, q, set(w) if isinstance(w, tuple) else {w}))
    return out


def build(seed: int, n: int = 2000) -> list[dict]:
    rng = random.Random(seed)
    base = seeds()
    cases = []
    for _ in range(n):
        p, q, want = rng.choice(base)
        cases.append({"plan_id": p, "seed_question": q, "text": manglish(q, rng), "want": sorted(map(str, want))})
    return cases
