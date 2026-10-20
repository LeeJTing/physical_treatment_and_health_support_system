"""A family member typing for someone else (21 Oct): the chatbot's first-person questions rewritten in the
third person ("my knee hurts after the exercise" -> "my mother's knee hurts after the exercise", "i feel
dizzy" -> "my father feels dizzy", "can i exercise with diabetes" -> "can my husband exercise with
diabetes"). The answer should be the question's own topic - a warning sign stays urgent - or the answer
for helping someone else (for_someone_else, family_help). evaluate_chat_caregiver.py runs it.
"""
import random
import re

PEOPLE = [("my mother", "she", "her"), ("my father", "he", "his"), ("my mum", "she", "her"), ("my dad", "he", "his"),
          ("my husband", "he", "his"), ("my wife", "she", "her"), ("my grandmother", "she", "her"),
          ("my grandfather", "he", "his"), ("my mak", "she", "her"), ("my ayah", "he", "his")]
HELPING = {"for_someone_else", "family_help"}
URGENT = {"red_flag", "crisis", "overdose", "poisoning"}
# Verbs that take an -s after he / she.
VERB_S = {"feel": "feels", "have": "has", "do": "does", "get": "gets", "need": "needs", "want": "wants",
          "keep": "keeps", "can't": "can't", "cannot": "cannot", "am": "is", "was": "was", "fell": "fell",
          "hurt": "hurts", "go": "goes", "try": "tries", "lose": "loses", "think": "thinks"}


AUX = {"do", "does", "did", "can", "could", "should", "will", "would", "may", "might", "must", "to", "shall"}
# Seeds whose meaning changes when told of someone else ("better if i was gone" -> "better if my husband
# was gone" is no longer about the speaker), or that already name another person.
NOT_SEEDS = re.compile(r"\b(?:better if i|better off without me|without me|mum|mom|mother|dad|father|husband|wife|"
                       r"son|daughter|grandma|grandpa|grandmother|grandfather|she|he|her|him|his|they|family|"
                       r"children|kids|caregiver|carer|helper|maid)\b")


def third_person(text: str, rng: random.Random) -> str | None:
    """[text] said by a family member about someone else, or None when it is not about the speaker."""
    q = " ".join(text.lower().strip().split())
    if not re.search(r"\b(?:i|my|me|i'm|im)\b", q) or re.search(r"\b(?:password|account|app|log ?in|email|"
                                                                 r"profile|reminder|notification|video|phone)\b", q):
        return None                                      # about the speaker's own account or phone: not this
    who, he, his = rng.choice(PEOPLE)
    first = [True]

    def person():
        if first[0]:
            first[0] = False
            return who
        return he

    def poss():
        if first[0]:
            first[0] = False
            return who + "'s"
        return his

    out = []
    words = q.split()
    for k, w in enumerate(words):
        bare = w.strip("?!.,")
        tail = w[len(bare):]
        if bare in ("i", "i'm", "im"):
            out.append((person() + (" is" if bare != "i" else "")) + tail)
            # "i feel" -> "he feels", but "do i have" -> "does he have" (3.73)
            if bare == "i" and k + 1 < len(words) and words[k + 1] in VERB_S and (k == 0 or words[k - 1] not in AUX):
                words[k + 1] = VERB_S[words[k + 1]]
        elif bare == "my":
            out.append(poss() + tail)
        elif bare == "me":
            out.append(("him" if he == "he" else "her") + tail)
        elif bare == "myself":
            out.append(("himself" if he == "he" else "herself") + tail)
        else:
            out.append(w)
    s = " ".join(out)
    s = re.sub(r"^(can|should|do|does|is|will) (my \w+|he|she)\b", r"\1 \2", s)
    s = re.sub(r"\bdo (my \w+|he|she) ", r"does \1 ", s)
    return s if s != q else None


def seeds():
    import test_chat
    probe = random.Random(0)
    out = []
    for p, q, w in test_chat.ALL_QUESTIONS:
        if w is None or (isinstance(w, str) and "/" in w) or NOT_SEEDS.search(q.lower()) \
                or third_person(q, probe) is None:
            continue
        out.append((p, q, set(w) if isinstance(w, tuple) else {w}))
    return out


def build(seed: int, n: int = 2000) -> list[dict]:
    rng = random.Random(seed)
    base = seeds()
    cases = []
    for _ in range(n):
        p, q, want = rng.choice(base)
        urgent = want <= URGENT
        ok = want if urgent else want | HELPING
        cases.append({"plan_id": p, "seed_question": q, "text": third_person(q, rng), "want": sorted(map(str, ok)),
                      "urgent": urgent})
    return cases
