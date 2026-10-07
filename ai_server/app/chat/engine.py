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
ive i've id i'd ok okay also really very much still even then than too one second another other thing things
stuff lol""".split())
COMMON_WORDS = """able about above accident across act action add after afternoon again age ago agree air all allow almost alone along already alright always amount angry animal answer anyone anything appointment area arm arms around ask asked asleep attack aunt away baby back bad bag ball bathroom bed bedroom before begin behind believe belly best better big bike bit blood board body bone bones book born both bottle bottom box boy brain bread break breakfast bring brother brought brush building bus busy buy call called came cane car card care careful carry case cat catch caught chair change cheap check child children choose church city class clean clear climb clinic close clothes cold colour come comfortable coming company computer cook cool corner cost could count country couple cover crutch crutches cry cup cut dad daily dance dark data daughter day days dead dear decide deep diet different dinner dirty doctor dog done door double down dress drink drive drop dry during early easy eat eaten eating else email empty end enough evening ever every everyone everything example expensive explain eye face fact fall family far fast father fear feel feeling feet fell felt few field fight fill find fine finger finish fire first fish floor flower fly food foot forget forward frame free friend friends front frustrated fruit full fun funny game garden gave girl give given glad glass go going gone good grandchild grandmother grandfather great green ground group grow guess hair half hall hand hands happen happy hard hate head health hear heard heavy hello help here hill hold holiday home hope hospital hot hour hours house hundred hungry husband idea ill important information inside instead job join joke keep key kid kids kind kitchen knew know lady last late later laugh lazy learn least leave left lesson letter life light like line list listen little live long look lost lot loud love low lunch made make man many market married matter maybe meal mean meet message middle mind minute minutes miss mobile moment money month months more morning mother move movie much music must name near neck need never new news next nice night noise none noon nothing notice number nurse office often old once only open other outside over own pain paper parent park part party pass past pay people perhaps person phone pick picture piece place plan play please pocket point police poor possible pray pretty price problem pull push put question quick quiet quite radio rain read ready real reason remember rest return rich ride right road room round run sad safe said same school sea second see seen sell send sent set shop short show shower sick side sign since sister sit sitting sleep slow small smile snow some someone something sometimes son soon sorry sound speak stand start stay step stick still stop story street strong student study sun supper sure surgery table take taken talk tea teacher tell thank thing think third thought through throw ticket tired today together told tomorrow tonight took top touch town train travel tree trip true try turn type uncle under understand until upset use used usual visit voice wait wake walk walker walking wall want warm wash watch water way wear weather week weekend well went wet wheelchair while white whole wife will win window wish woman word work world worry worse worst write wrong year years yes yesterday young zimmer""".split()
# Emojis patients send instead of words.
EMOJI = {"👍": " ok ", "👌": " ok ", "🙏": " thanks ", "❤": " love ", "😍": " love ", "🥰": " love "}
# Words people stretch ("hiiii", "okayyy"): shortened to one letter if that gives one of these, else to two
# ("kneee" -> "knee").
SHORT_WORDS = {"hi", "hey", "hello", "ok", "okay", "yes", "no", "so", "thanks", "thank", "bye", "yay", "wow", "please"}


def unstretch(w: str) -> str:
    if not re.search(r"(.)\1{2,}", w):
        return w
    one = re.sub(r"(.)\1{2,}", r"\1", w)
    return one if one in SHORT_WORDS else re.sub(r"(.)\1{2,}", r"\1\1", w)
NEGATORS = {"no", "not", "without", "never", "don't", "dont", "didn't", "didnt", "haven't", "havent", "isn't",
            "isnt", "wasn't", "wasnt", "nor"}
# Everyday words mapped onto the words the rules use.
SYNONYMS = {"workout": "exercise", "workouts": "exercises", "train": "exercise", "training": "exercising",
            "lift": "raise", "lifts": "raises", "lifting": "raising", "lifted": "raised", "high": "height",
            "physio": "physiotherapist", "doc": "doctor", "vid": "video", "pic": "photo"}
# Common Malay words patients mix into English (Malaysian users). Single words; phrases are in
# MALAY_PHRASES. Body-part and symptom words map to the English the rules (and red flags) know.
MALAY = {"saya": "i", "aku": "i", "malam": "night", "pagi": "morning", "petang": "evening", "tengahari": "afternoon", "boleh": "can",
         "buat": "do", "senaman": "exercise", "bersenam": "exercise", "lutut": "knee", "bahu": "shoulder",
         "kaki": "leg", "tangan": "arm", "pinggang": "back", "belakang": "back", "letih": "tired",
         "penat": "tired", "pening": "dizzy", "dada": "chest", "tak": "not", "tidak": "not", "dapat": "get",
         "kod": "code", "lupa": "forgot", "bila": "when", "masa": "time", "tolong": "please", "bengkak": "swollen",
         "jatuh": "fell", "makan": "eat", "lepas": "after", "sebelum": "before", "tidur": "sleep"}
MALAY_PHRASES = {"kata laluan": "password", "terima kasih": "thank you", "macam mana": "how", "camne": "how",
                 "sesak nafas": "short of breath", "kencing manis": "diabetes", "darah tinggi": "high blood pressure",
                 "sakit jantung": "heart disease", "lemah badan": "weak"}
CONTRACTIONS = {"dont": "don't", "cant": "can't", "wont": "won't", "im": "i'm", "ive": "i've", "isnt": "isn't",
                "doesnt": "doesn't", "didnt": "didn't", "havent": "haven't", "whats": "what's", "thats": "that's",
                "u": "you", "ur": "your", "pls": "please", "plz": "please", "r": "are", "abt": "about"}


@lru_cache
def rules() -> dict:
    return json.loads(RULES_PATH.read_text(encoding="utf-8"))


def clean(text: str) -> str:
    t = text.lower().replace("’", "'").replace("%", " percent ")
    t = re.sub(r"<[^>]*>", " ", t)                     # pasted HTML / script tags
    for e, word in EMOJI.items():
        t = t.replace(e, word)
    # A clock time ("11pm", "7:30 am", "10 o'clock") becomes one token the timing rule knows.
    t = re.sub(r"\b\d{1,2}(?::\d{2})?\s*(?:am|pm|a\.m\.|p\.m\.|o'?\s?clock)(?![a-z])", " clocktime ", t)
    for phrase, english in MALAY_PHRASES.items():
        t = re.sub(rf"\b{phrase}\b", english, t)
    words = re.sub(r"[^a-z0-9' ]", " ", t).split()
    words = [unstretch(w) for w in words]
    return " ".join(SYNONYMS.get(w, CONTRACTIONS.get(w, MALAY.get(w, w))) for w in words)


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
        "follow_ups": [], "tailor": True, "time_aware": True,
        "action": {"key": "open_treatment", "label": "Open my treatment plan"} if in_plan else None,
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
         "follow_ups": [], "tailor": True, "time_aware": True,
         "action": {"key": "open_treatment", "label": "Open my treatment plan"}},
        {"key": "plan_progress", "title": "Progress and results", "show": True, "priority": 6,
         "keywords": ["results", "see results", "progress", "improve", "improving", "improvement", "how long until",
                      "when will", "getting better", "get better", "working", "is it working", "finish the plan",
                      "finished the plan", "complete the plan", "after this plan", "next plan", "recover", "recovery",
                      "is it helping", "plan helping", "helping me", "help me recover", "effective", "worth it", "making a difference", "any difference",
                      "fix", "cure", "heal", "do for me", "purpose", "aim", "goal", "benefit", "benefits",
                      "plan for", "normally again", "back to normal", "normal again", "like before",
                      "get back to normal", "giving up", "give up", "no motivation", "not motivated",
                      "demotivated", "discouraged", "finished all", "completed all", "finish all", "done all",
                      "all done", "finished my plan", "completed my plan",
                      "why this plan", "what does this plan do", "what next", "what's next", "next step",
                      "better now", "feel better", "feeling better"],
         "examples": ["when will I see results", "how do I know I am improving", "is the plan working",
                      "what happens when I finish this plan"],
         "answer": f"This plan aims to help you {plan['goal_text']}. Most people notice a difference after two to "
                   f"four weeks of regular sessions. Your progress bar moves forward each time you complete an "
                   f"exercise with good posture; when the plan is complete, request a new recommendation to move on.",
         "follow_ups": [], "tailor": False,
         "action": {"key": "open_history", "label": "See my results"}},
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
    # Everyday words are real words, never "typos" of a rule keyword ("stick" is not "sick",
    # "information" is not "inflammation").
    words = set(STOP) | set(NEGATORS) | set(COMMON_WORDS)
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


COMBO_NEGATORS = NEGATORS - {"can't", "cant", "cannot"}

# When both rules match, the first answers the actual question better than the second
# ("i have diabetes, what time is best" is about timing; the diabetes timing note is added).
PREFER = [("history_help", "posture_result"), ("best_time", "condition_advice"), ("doctor_said", "how_often"), ("doctor_said", "tired")]


def red_flag(text: str | None) -> bool:
    if not text:
        return False
    r = rules()
    for variant in {clean(text), correct(text)}:
        words = variant.split()
        for phrase in r["red_flags"]:
            for i in find_phrase(phrase, words):
                if not negated(words, i):
                    return True
        for anchors, symptoms, window in r.get("red_flag_combos", []):
            for anchor in anchors:
                for i in find_phrase(anchor, words):
                    if COMBO_NEGATORS & set(words[max(0, i - 2):i]):
                        continue                       # "no chest pain", "never had breathing trouble"
                    near = words[max(0, i - window):i + window + 1]
                    if any(find_phrase(s, near) for s in symptoms):
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
                   "arthritis": "ARTHRITIS", "osteoporosis": "OSTEOPOROSIS", "heart patient": "HEART_DISEASE",
                   "sugar level": "DIABETES", "my sugar": "DIABETES", "glucose": "DIABETES"}


def conditions_in(text: str | None) -> list[str]:
    if not text:
        return []
    words = clean(text).split()
    return list(dict.fromkeys(code for phrase, code in CONDITION_WORDS.items() if find_phrase(phrase, words)))


def period(hour: int) -> str:
    """Part of the patient's day by the phone's local hour."""
    if hour >= 22 or hour < 6:
        return "late_night"
    if hour < 9:
        return "early_morning"
    if hour < 18:
        return "daytime"
    return "evening"


def clock(hour: int, minute: int) -> str:
    h = hour % 12 or 12
    return f"{h}:{minute:02d} {'am' if hour < 12 else 'pm'}"


def time_notes(intent: dict, local: tuple[int, int] | None, conditions, limitations) -> list[str]:
    """Advice that depends on the time where the patient is (the phone's local time): rest late at
    night, and condition-specific timing (e.g. diabetes in the evening, blood pressure after waking)."""
    if local is None or not intent.get("time_aware"):
        return []
    r = rules()
    hour, minute = local
    p = period(hour)
    if p == "late_night":
        notes = [r["late_night_note"].format(time=clock(hour, minute))]
    elif intent.get("key") == "best_time" and p in r.get("now_notes", {}):
        notes = [r["now_notes"][p].format(time=clock(hour, minute))]
    else:
        notes = []
    for code in list(conditions or []) + list(limitations or []):
        note = r.get("time_notes", {}).get(code, {}).get(p)
        if note:
            notes.append(note)
    return notes


def tailor_notes(intent: dict, conditions, limitations, risk_level) -> list[str]:
    if not intent.get("tailor"):
        return []
    r = rules()
    if intent.get("key") == "condition_advice" and any(c in r.get("condition_detail", {}) for c in conditions or []):
        notes = []                    # the condition guidance is already the main answer
    elif intent.get("key") == "diet":
        notes = [r["diet_notes"][c] for c in (conditions or []) if c in r.get("diet_notes", {})]
    else:
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
    if correct(text) != clean(text):
        fixed = [(i["priority"], n, i) for i in intents if (n := keyword_match(text, i, corrected=True))]
        if not hits:
            hits = fixed
        else:
            # A misspelt exercise name ("sholder flexion") still names the exercise: it wins over the
            # general how-to rule the exact words matched. Only exercise names, so a real word the
            # rules do not know is never turned into another topic's keyword.
            named = [h for h in fixed if h[2]["key"].startswith("exercise:")]
            if named and not any(h[2]["key"].startswith("exercise:") for h in hits):
                hits = hits + named
    exercises = {h[2]["key"] for h in hits if h[2]["key"].startswith("exercise:")}
    if len(exercises) >= 2 and "plan_exercises" in {i["key"] for i in intents}:
        # "Which comes first, heel raise or sit to stand?" is about the plan's order.
        return next(i for i in intents if i["key"] == "plan_exercises"), "keyword"
    if len(clean(text).split()) <= 3:
        small = [h for h in hits if h[2].get("small_talk")]
        if small:                                    # "good morning", "help", "ok thanks"
            return max(small, key=lambda h: (h[0], h[1]))[2], "keyword"
    keys = {h[2]["key"] for h in hits}
    for better, general in PREFER:
        if better in keys and general in keys:
            hits = [h for h in hits if h[2]["key"] != general]
    if hits:
        return max(hits, key=lambda h: (h[0], h[1]))[2], "keyword"
    score, best = max(((fuzzy_score(text, i), i) for i in intents), key=lambda s: s[0])
    if score >= THRESHOLD:
        return best, "similar_question"
    best, score = overlap_match(plan_id, text)
    return (best, "keyword_overlap") if best is not None and score >= OVERLAP_THRESHOLD else (None, None)


def reply(plan_id: str | None, category: str | None, text: str | None,
          conditions: list[str] | None = None, limitations: list[str] | None = None,
          risk_level: str | None = None, local_time: tuple[int, int] | None = None) -> dict:
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
    all_conditions = list(dict.fromkeys((conditions or []) + mentioned))
    # Time first: "rest now, it is late" matters more than the condition reminders that follow.
    notes = time_notes(chosen, local_time, all_conditions, limitations)
    notes += tailor_notes(chosen, all_conditions, limitations, risk_level)
    base_answer = chosen["answer"]
    asked_first = list(dict.fromkeys(mentioned + all_conditions))   # the condition named in the question leads
    details = [r["condition_detail"][c] for c in asked_first if c in r.get("condition_detail", {})]
    if chosen["key"] == "condition_advice" and details:
        # A different answer for each condition (Table 4.2.2): the patient's own conditions first.
        base_answer = " ".join(details) + " " + r["condition_closing"]
    answer = base_answer + ("\n\n" + " ".join(notes) if notes else "")
    follow = [by_key[k] for k in chosen.get("follow_ups", []) if k in by_key]
    return {**base, "answer": answer, "category": chosen["key"], "title": chosen["title"], "is_matched": True,
            "matched_by": how, "follow_ups": _listing(follow), "notes": notes, "action": chosen.get("action")}
