"""Compound and rambling messages (21 Oct): two questions in one message ("how do i record the video, also my
chest hurts since morning"), and a neutral story before the question ("yesterday i went to the market with my
grandson, then ... can i skip today?"). With two questions either topic is right, but when one of them is a
warning sign or a crisis only the urgent answer is; with a story, the question's own topic. Made from the
chatbot's question sets. evaluate_chat_compound.py runs it.
"""
import random

URGENT = {"red_flag", "crisis", "overdose", "poisoning"}
JOINERS = [" and ", ", also ", ". ", " also ", ", and ", "... ", " lah, ", ". another thing, ", " plus "]
STORIES = ["yesterday i went to the market", "my grandson visited me today", "i had nasi lemak for breakfast",
           "it rained the whole morning", "i just came back from the clinic for my usual check up",
           "my daughter helped me set up the phone", "i watched tv the whole afternoon",
           "we went to the mall on sunday", "i cooked lunch for the family", "my wife is at work now",
           "i woke up early today", "the weather is very hot today", "i just finished my breakfast",
           "my son bought me a new phone", "i was reading the newspaper", "i have been at home all week",
           "i talked to my friend on the phone", "i finished my prayers", "the neighbours were noisy last night",
           "i took my dog for a short walk"]
LINKS = [", ", ". ", " and then ", ", so ", ". anyway ", " lah, ", "... "]


def seeds():
    import test_chat
    return [(p, q, set(w) if isinstance(w, tuple) else {w}) for p, q, w in test_chat.ALL_QUESTIONS
            if w is not None and not (isinstance(w, str) and "/" in w) and len(q.split()) >= 3]


def build(seed: int, n: int = 2000) -> list[dict]:
    rng = random.Random(seed)
    base = seeds()
    cases = []
    for _ in range(n):
        p, q, want = rng.choice(base)
        if rng.random() < 0.5:
            p2, q2, want2 = rng.choice([b for b in base if b[0] == p] or base)
            if want & want2:
                continue
            text = q.rstrip("?!. ") + rng.choice(JOINERS) + q2
            # urgent only when all a question's answers are urgent ("lutut saya bengkak" may be swelling)
            urgent = (want if want <= URGENT else set()) | (want2 if want2 <= URGENT else set())
            both = urgent if urgent else (want | want2)
            cases.append({"kind": "two_questions", "plan_id": p, "text": text, "want": sorted(map(str, both)),
                          "urgent": bool(urgent)})
        else:
            text = rng.choice(STORIES) + rng.choice(LINKS) + q
            cases.append({"kind": "story", "plan_id": p, "text": text, "want": sorted(map(str, want)),
                          "urgent": want <= URGENT})
    return cases
