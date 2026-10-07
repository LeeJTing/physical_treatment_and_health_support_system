"""Rule-based rehabilitation chatbot engine (FR500_18 to FR500_22, Table 4.2.4 /chat).

Matching order (deterministic, so every answer can be traced to one rule):
  1. Red flags: urgent safety phrases in the raw or spell-corrected text, unless negated
     ("I have no chest pain"). Always answered first, whatever else was sent.
  2. A tapped category (any rule key valid for the patient's plan).
  3. Keyword rules: every rule whose keyword phrase appears in the text is a candidate;
     the highest priority wins, then the longest matching phrase.
  4. No keyword phrase: (a) fuzzy match against each rule's example questions, or
     (b) weighted keyword overlap: the share of the question's words (rare words weigh
     more) that belong to a rule's keyword list; for exercises, its instruction words.
     Each must reach its threshold, otherwise the question is not recognised.
  5. Otherwise the "not recognised" message and the categories again (FR500_22).
Answers of safety-related rules get extra lines for the patient's declared conditions,
limitations and risk level (Table 4.2.2: the reply is filtered by health condition).
"""
import json
import math
import re
from functools import lru_cache
from pathlib import Path

from rapidfuzz import fuzz, process

RULES_PATH = Path(__file__).with_name("rules.json")
THRESHOLD = 0.75          # fuzzy example match
OVERLAP_THRESHOLD = 0.6   # weighted keyword overlap
STOP = set("""a an the is are am was were be been being do does did i me my mine myself you your we our it its
this that these those to of in on at for with and or but if so can could should would will shall may might must
what which who whom when where why how about please tell any some just there here have has had get got im i'm
ive i've id i'd ok okay also really very much still even then than too""".split())
NEGATORS = {"no", "not", "without", "never", "don't", "dont", "didn't", "didnt", "haven't", "havent", "isn't",
            "isnt", "wasn't", "wasnt", "nor"}
# Everyday words mapped onto the words the rules use.
SYNONYMS = {"workout": "exercise", "workouts": "exercises", "train": "exercise", "training": "exercising",
            "lift": "raise", "lifts": "raises", "lifting": "raising", "lifted": "raised", "high": "height",
            "physio": "physiotherapist", "doc": "doctor", "vid": "video", "pic": "photo"}
CONTRACTIONS = {"dont": "don't", "cant": "can't", "wont": "won't", "im": "i'm", "ive": "i've", "isnt": "isn't",
                "doesnt": "doesn't", "didnt": "didn't", "havent": "haven't", "whats": "what's", "thats": "that's",
                "u": "you", "ur": "your", "pls": "please", "plz": "please", "r": "are", "abt": "about"}


@lru_cache
def rules() -> dict:
    return json.loads(RULES_PATH.read_text(encoding="utf-8"))


def clean(text: str) -> str:
    t = text.lower().replace("’", "'").replace("%", " percent ")
    words = re.sub(r"[^a-z0-9' ]", " ", t).split()
    return " ".join(SYNONYMS.get(w, CONTRACTIONS.get(w, w)) for w in words)


# ---------------------------------------------------------------------------
# Rule set for one plan
# ---------------------------------------------------------------------------

def exercise_intent(key: str, ex: dict, plan: dict | None) -> dict:
    in_plan = next((e for e in (plan or {}).get("exercises", []) if e["pose_key"] == key), None)
    if in_plan:
        extra = (f"In your plan this is exercise {in_plan['order']}: {in_plan['repetitions']} repetitions, about "
                 f"{in_plan['duration']}, {plan['frequency_per_week']} times a week.")
    elif plan:
        extra = "This exercise is not part of your current plan."
    else:
        extra = ""
    camera = f" When recording it: {ex['camera'][0].lower() + ex['camera'][1:]}." if ex.get("camera") else ""
    aliases = ex["aliases"]
    return {
        "key": f"exercise:{key}", "title": f"How to do {ex['name']}", "show": bool(in_plan), "priority": 6,
        "keywords": aliases,
        "examples": [f"how do I do the {aliases[0]}", f"{aliases[0]} instructions", f"how many {aliases[0]}"],
        "answer": f"{ex['name']}: {ex['instruction']} {extra}{camera}".strip(),
        "follow_ups": [], "tailor": True,
    }


def plan_intents(plan: dict) -> list[dict]:
    lines = "; ".join(f"{e['order']}. {e['name']}, {e['repetitions']} repetitions (about {e['duration']})"
                      for e in plan["exercises"])
    return [
        # Priority 3: "my plan" appears in many questions about other topics, which should win.
        {"key": "plan_exercises", "title": "What is in my plan", "show": True, "priority": 3,
         "keywords": ["plan", "what exercises", "which exercises", "exercises in my plan", "my plan", "in my plan",
                      "this plan", "exercise list", "list of exercises", "what order", "which order", "first exercise",
                      "next exercise", "how many reps", "how many repetitions", "repetitions", "reps", "sets",
                      "every session", "each session", "all the exercises", "all exercises", "all three",
                      "comes first", "which first", "which one first", "order"],
         "examples": ["what exercises are in my plan", "which exercise do I do first", "how many repetitions",
                      "what is in this plan"],
         "answer": f"Your plan, {plan['plan_name']}, has {len(plan['exercises'])} exercises, done in this order: "
                   f"{lines}. Do it {plan['frequency_per_week']} times a week.",
         "follow_ups": [], "tailor": True},
        {"key": "plan_progress", "title": "Progress and results", "show": True, "priority": 6,
         "keywords": ["results", "see results", "progress", "improve", "improving", "improvement", "how long until",
                      "when will", "getting better", "get better", "working", "is it working", "finish the plan",
                      "finished the plan", "complete the plan", "after this plan", "next plan", "recover", "recovery",
                      "helping", "help me", "effective", "worth it", "making a difference", "any difference",
                      "fix", "cure", "heal", "do for me", "purpose", "aim", "goal", "benefit", "benefits",
                      "why this plan", "what does this plan do", "what next", "what's next", "next step",
                      "better now", "feel better", "feeling better"],
         "examples": ["when will I see results", "how do I know I am improving", "is the plan working",
                      "what happens when I finish this plan"],
         "answer": f"This plan aims to help you {plan['goal_text']}. Most people notice a difference after two to "
                   f"four weeks of regular sessions. Your progress bar moves forward each time you complete an "
                   f"exercise with good posture; when the plan is complete, request a new recommendation to move on.",
         "follow_ups": [], "tailor": False},
    ]


@lru_cache(maxsize=64)
def _intents_for(plan_id: str | None) -> tuple:
    r = rules()
    plan = r["plans"].get(plan_id or "")
    items = list(plan_intents(plan)) if plan else []
    items += [exercise_intent(k, ex, plan) for k, ex in r["exercises"].items()]
    items += r["intents"]
    return tuple(items)


def intents_for(plan_id: str | None) -> list[dict]:
    return list(_intents_for(plan_id))


def categories_for(plan_id: str | None) -> list[dict]:
    """The question categories the app lists (FR500_18): plan topics first, then general ones."""
    return [i for i in intents_for(plan_id) if i["show"]]


# ---------------------------------------------------------------------------
# Text handling
# ---------------------------------------------------------------------------

@lru_cache
def vocabulary() -> tuple[str, ...]:
    r = rules()
    words = set(STOP) | set(NEGATORS)
    phrases = list(r["red_flags"])
    for i in r["intents"]:
        phrases += i["keywords"] + i["examples"]
    for i in r["intents"]:
        phrases.append(i["answer"])
    for ex in r["exercises"].values():
        phrases += ex["aliases"] + [ex["name"], ex["instruction"]]
    for p in r["plans"].values():
        phrases.append(p["plan_name"])
        for i in plan_intents(p):
            phrases += i["keywords"] + i["examples"]
    for ph in phrases:
        words.update(clean(ph).split())
    return tuple(sorted(words))


@lru_cache(maxsize=4096)
def correct(text: str) -> str:
    """Each unknown word replaced by its closest known word (typos such as 'excercise', 'ofen').

    A correction must start with the same letter and differ in length by at most one letter,
    so real words the rules do not use are left alone ('sure' never becomes 'cure',
    'weather' never becomes 'water')."""
    vocab = vocabulary()
    out = []
    for w in clean(text).split():
        if w not in vocab and len(w) >= 2 and not w.isdigit():
            candidates = [v for v in vocab if v[0] == w[0] and abs(len(v) - len(w)) <= 1]
            hit = process.extractOne(w, candidates, scorer=fuzz.ratio, score_cutoff=75) if candidates else None
            w = hit[0] if hit else w
        out.append(w)
    return " ".join(out)


def content_words(text: str) -> str:
    return " ".join(w for w in correct(text).split() if w not in STOP)


@lru_cache(maxsize=8192)
def stem(w: str) -> str:
    """Crude suffix stripping so burn / burns / burning and raise / raises / raising compare equal.
    The same function is applied to the rules and the question, so only consistency matters."""
    if len(w) <= 3 or "'" in w:
        return w
    if w.endswith("ies") and len(w) > 4:
        return w[:-3] + "y"
    for suf in ("ings", "ing", "ed", "es", "s", "e"):
        if w.endswith(suf) and len(w) - len(suf) >= 3 and not (suf == "s" and w.endswith("ss")):
            w = w[: -len(suf)]
            break
    if len(w) >= 7 and w.endswith("en"):            # straighten -> straight
        w = w[:-2]
    return w


def find_phrase(phrase: str, words: list[str]) -> list[int]:
    p = [stem(x) for x in clean(phrase).split()]
    n = len(p)
    if not n:
        return []
    ws = [stem(x) for x in words]
    return [i for i in range(len(ws) - n + 1) if ws[i:i + n] == p]


def negated(words: list[str], i: int) -> bool:
    """A negator in the two words before position i ('no chest pain', 'not dizzy')."""
    return bool(NEGATORS & set(words[max(0, i - 2):i]))


def red_flag(text: str | None) -> bool:
    if not text:
        return False
    for variant in {clean(text), correct(text)}:
        words = variant.split()
        for phrase in rules()["red_flags"]:
            for i in find_phrase(phrase, words):
                if not negated(words, i):
                    return True
    return False


def keyword_match(text: str, intent: dict, corrected: bool = False) -> int:
    """Length in words of the longest keyword phrase found (0 = none). With corrected=True the
    spell-corrected text is used instead of the patient's exact words."""
    best = 0
    variants = [(correct(text) if corrected else clean(text)).split()]
    for kw in intent["keywords"]:
        n = len(clean(kw).split())
        if n <= best:
            continue
        for words in variants:
            hits = find_phrase(kw, words)
            if intent.get("anchor_start"):
                hits = [i for i in hits if i == 0]
            if intent.get("negatable"):
                hits = [i for i in hits if not negated(words, i)]
            if hits:
                best = n
                break
    return best


def fuzzy_score(text: str, intent: dict) -> float:
    words = content_words(text)
    if not words:
        return 0.0
    best = 0.0
    for ex in intent["examples"]:
        e = content_words(ex)
        if e:
            # token_set alone gives 100 whenever one word list contains the other; averaging with
            # token_sort stops one shared word from looking like a perfect match.
            best = max(best, (fuzz.token_set_ratio(words, e) + fuzz.token_sort_ratio(words, e)) / 200)
    return best


def _stems(text: str) -> set[str]:
    return {stem(w) for w in content_words(text).split()}


@lru_cache(maxsize=64)
def _overlap_index(plan_id: str | None):
    """Per rule: the stems of its keywords and examples (exercise rules: also name and
    instruction words), and an IDF weight per stem so words shared by many rules count less."""
    r = rules()
    docs = []
    for i in intents_for(plan_id):
        text = " ".join(i["keywords"] + i["examples"])
        if i["key"].startswith("exercise:"):
            ex = r["exercises"][i["key"].split(":", 1)[1]]
            text += " " + ex["name"] + " " + ex["instruction"]
        docs.append((i, _stems(text)))
    n = len(docs)
    df: dict[str, int] = {}
    for _, d in docs:
        for t in d:
            df[t] = df.get(t, 0) + 1
    idf = {t: math.log((n + 1) / (c + 1)) + 1 for t, c in df.items()}
    return docs, idf


def overlap_match(plan_id: str | None, text: str) -> tuple[dict | None, float]:
    """Best rule by weighted share of the question's words found in the rule's vocabulary."""
    q = _stems(text)
    docs, idf = _overlap_index(plan_id)
    known = {t for t in q if t in idf}
    if not known:
        return None, 0.0
    unknown_weight = math.log(len(docs) + 1) + 1          # an unseen word weighs like the rarest word
    total = sum(idf.get(t, unknown_weight) for t in q)
    best, best_score = None, 0.0
    for intent, d in docs:
        if len(q & d) < 2:          # one shared word ("time", "arm") is not enough evidence
            continue
        hit = sum(idf[t] for t in q & d)
        score = hit / total if total else 0.0
        if intent["key"].startswith("exercise:"):
            score *= 1.15 if intent["show"] else 0.85     # prefer exercises in the patient's own plan
        if score > best_score or (score == best_score and best and intent["priority"] > best["priority"]):
            best, best_score = intent, score
    return best, best_score


CONDITION_WORDS = {"high blood pressure": "HYPERTENSION", "blood pressure": "HYPERTENSION",
                   "hypertension": "HYPERTENSION", "diabetes": "DIABETES", "diabetic": "DIABETES",
                   "blood sugar": "DIABETES", "heart disease": "HEART_DISEASE", "heart condition": "HEART_DISEASE",
                   "heart problem": "HEART_DISEASE", "stroke": "STROKE", "asthma": "ASTHMA", "asthmatic": "ASTHMA",
                   "arthritis": "ARTHRITIS", "osteoporosis": "OSTEOPOROSIS"}


def conditions_in(text: str | None) -> list[str]:
    if not text:
        return []
    words = clean(text).split()
    return list(dict.fromkeys(code for phrase, code in CONDITION_WORDS.items() if find_phrase(phrase, words)))


def tailor_notes(intent: dict, conditions, limitations, risk_level) -> list[str]:
    if not intent.get("tailor"):
        return []
    r = rules()
    notes = [r["condition_notes"][c] for c in (conditions or []) if c in r["condition_notes"]]
    notes += [r["limitation_notes"][x] for x in (limitations or []) if x in r["limitation_notes"]]
    if risk_level in r["risk_notes"]:
        notes.append(r["risk_notes"][risk_level])
    return notes


# ---------------------------------------------------------------------------
# Reply
# ---------------------------------------------------------------------------

def _listing(items):
    return [{"key": i["key"], "title": i["title"]} for i in items]


def match(plan_id: str | None, text: str) -> tuple[dict | None, str | None]:
    """The rule a typed question resolves to, and how it was matched."""
    intents = intents_for(plan_id)
    # The patient's exact words first; spell-corrected words only if nothing matched, so a real
    # word the rules do not know ("turn") is never "corrected" into a different rule's keyword ("torn").
    hits = [(i["priority"], n, i) for i in intents if (n := keyword_match(text, i))]
    if not hits and correct(text) != clean(text):
        hits = [(i["priority"], n, i) for i in intents if (n := keyword_match(text, i, corrected=True))]
    exercises = {h[2]["key"] for h in hits if h[2]["key"].startswith("exercise:")}
    if len(exercises) >= 2 and "plan_exercises" in {i["key"] for i in intents}:
        # "Which comes first, heel raise or sit to stand?" is about the plan's order.
        return next(i for i in intents if i["key"] == "plan_exercises"), "keyword"
    if len(clean(text).split()) <= 3:
        small = [h for h in hits if h[2].get("small_talk")]
        if small:                                    # "good morning", "help", "ok thanks"
            return max(small, key=lambda h: (h[0], h[1]))[2], "keyword"
    if hits:
        return max(hits, key=lambda h: (h[0], h[1]))[2], "keyword"
    score, best = max(((fuzzy_score(text, i), i) for i in intents), key=lambda s: s[0])
    if score >= THRESHOLD:
        return best, "similar_question"
    best, score = overlap_match(plan_id, text)
    return (best, "keyword_overlap") if best is not None and score >= OVERLAP_THRESHOLD else (None, None)


def reply(plan_id: str | None, category: str | None, text: str | None,
          conditions: list[str] | None = None, limitations: list[str] | None = None,
          risk_level: str | None = None) -> dict:
    r = rules()
    by_key = {i["key"]: i for i in intents_for(plan_id)}
    base = {"categories": _listing(categories_for(plan_id)), "rules_version": r["version"]}

    if red_flag(text):
        return {**base, "answer": r["red_flag_answer"], "category": "red_flag", "title": "Urgent safety advice",
                "is_matched": True, "matched_by": "red_flag", "follow_ups": [], "notes": [], "action": None}

    chosen, how = None, None
    if category and category in by_key:
        chosen, how = by_key[category], "category"
    elif text and text.strip():
        chosen, how = match(plan_id, text)

    if chosen is None:
        return {**base, "answer": r["not_recognised"], "category": None, "title": None, "is_matched": False,
                "matched_by": None, "follow_ups": [], "notes": [], "action": None}

    mentioned = conditions_in(text) if chosen["key"] in ("condition_advice", "safety") else []
    notes = tailor_notes(chosen, list(dict.fromkeys((conditions or []) + mentioned)), limitations, risk_level)
    answer = chosen["answer"] + ("\n\n" + " ".join(notes) if notes else "")
    follow = [by_key[k] for k in chosen.get("follow_ups", []) if k in by_key]
    return {**base, "answer": answer, "category": chosen["key"], "title": chosen["title"], "is_matched": True,
            "matched_by": how, "follow_ups": _listing(follow), "notes": notes, "action": chosen.get("action")}
