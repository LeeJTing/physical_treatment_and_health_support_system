"""Rule-based matching for the rehabilitation chatbot (FR500_19 to FR500_22).

Order of checks:
  1. red-flag phrases -> urgent safety answer (always wins)
  2. a tapped category -> its answer
  3. free text -> keyword phrases, then fuzzy match against example questions
     (stop words removed, so "what is the ..." alone never matches)
  4. nothing above the threshold -> "not recognised" plus the categories
"""
import json
import re
from functools import lru_cache
from pathlib import Path

from rapidfuzz import fuzz, process

RULES_PATH = Path(__file__).with_name("rules.json")
NOT_RECOGNISED = "The question is not recognised, please try asking other question."
THRESHOLD = 0.75
STOP = set("""a an the is are am was were be been do does did i me my mine you your we our it its this that these
those to of in on at for with and or but if so can could should would will shall may might what which who whom
when where why how about please tell any some just there here have has had get got im i'm""".split())


@lru_cache
def rules() -> dict:
    return json.loads(RULES_PATH.read_text(encoding="utf-8"))


def categories_for(plan_id: str | None) -> list[dict]:
    r = rules()
    plan = r["plans"].get(plan_id or "", {})
    return r["general"] + plan.get("categories", [])


def _clean(text: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9' ]", " ", text.lower())).strip()


@lru_cache
def vocabulary() -> tuple[str, ...]:
    """Every word the rules use, for correcting typos in the patient's question."""
    words = set(STOP)
    r = rules()
    for phrase in r["red_flags"]:
        words.update(_clean(phrase).split())
    for c in r["general"] + [c for p in r["plans"].values() for c in p["categories"]]:
        for phrase in c["keywords"] + c["examples"]:
            words.update(_clean(phrase).split())
    return tuple(sorted(words))


def normalise(text: str) -> str:
    """Lower case, no punctuation, and each word replaced by its closest known word (typos)."""
    vocab = vocabulary()
    out = []
    for w in _clean(text).split():
        if w not in vocab and len(w) >= 2:
            hit = process.extractOne(w, vocab, scorer=fuzz.ratio, score_cutoff=75)
            w = hit[0] if hit else w
        out.append(w)
    return " ".join(out)


def content_words(text: str) -> str:
    return " ".join(w for w in normalise(text).split() if w not in STOP)



def score(text: str, cat: dict) -> float:
    t = normalise(text)
    padded = f" {t} "
    for kw in cat["keywords"]:
        if f" {_clean(kw)} " in padded:
            return 1.1          # an exact keyword phrase beats any fuzzy match
    words = content_words(text)
    if not words:
        return 0.0
    best = 0.0
    for kw in cat["keywords"]:
        k = _clean(kw)
        if len(k) >= 5 and fuzz.partial_ratio(k, t) >= 88:      # typo in a keyword ("excercises", "dizy")
            best = max(best, 0.85)
    for ex in cat["examples"]:
        e = content_words(ex)
        # token_set alone gives 100 whenever one word list contains the other; averaging with
        # token_sort stops a single shared word from looking like a perfect match.
        best = max(best, (fuzz.token_set_ratio(words, e) + fuzz.token_sort_ratio(words, e)) / 200)
    return best


def red_flag(text: str | None) -> bool:
    if not text:
        return False
    # Raw words AND spell-corrected words: a red flag must never be missed or corrected away.
    raw, fixed = f" {_clean(text)} ", f" {normalise(text)} "
    return any(f" {_clean(p)} " in raw or f" {_clean(p)} " in fixed for p in rules()["red_flags"])


def reply(plan_id: str | None, category: str | None, text: str | None) -> dict:
    cats = categories_for(plan_id)
    listing = [{"key": c["key"], "title": c["title"]} for c in cats]
    if red_flag(text):
        return {"answer": rules()["red_flag_answer"], "category": "safety", "is_matched": True, "categories": listing}
    if category:
        for c in cats:
            if c["key"] == category:
                return {"answer": c["answer"], "category": c["key"], "is_matched": True, "categories": listing}
    if text:
        best, best_cat = max(((score(text, c), c) for c in cats), key=lambda x: x[0])
        if best >= THRESHOLD:
            return {"answer": best_cat["answer"], "category": best_cat["key"], "is_matched": True,
                    "categories": listing}
    return {"answer": NOT_RECOGNISED, "category": None, "is_matched": False, "categories": listing}
