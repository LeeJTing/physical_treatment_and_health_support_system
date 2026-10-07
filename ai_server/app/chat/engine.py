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
COMMON_WORDS = """she he her him his hers they them their mum mom mummy papa mama grandma grandpa wife son malay match
able about above accident across act action add after afternoon again age ago agree air all allow almost alone along already alright always amount angry animal answer anyone anything appointment area arm arms around ask asked asleep attack aunt away baby back bad bag ball bathroom bed bedroom before begin behind believe belly best better big bike bit blood board body bone bones book born both bottle bottom box boy brain bread break breakfast bring brother brought brush building bus busy buy call called came cane car card care careful carry case cat catch caught chair change cheap check child children choose church city class clean clear climb clinic close clothes cold colour come comfortable coming company computer cook cool corner cost could count country couple cover crutch crutches cry cup cut dad daily dance dark data daughter day days dead dear decide deep diet different dinner dirty doctor dog done door double down dress drink drive drop dry during early easy eat eaten eating else email empty end enough evening ever every everyone everything example expensive explain eye face fact fall family far fast father fear feel feeling feet fell felt few field fight fill find fine finger finish fire first fish floor flower fly food foot forget forward frame free friend friends front frustrated fruit full fun funny game garden gave girl give given glad glass go going gone good grandchild grandmother grandfather great green ground group grow guess hair half hall hand hands happen happy hard hate head health hear heard heavy hello help here hill hold holiday home hope hospital hot hour hours house hundred hungry husband idea ill important information inside instead job join joke keep key kid kids kind kitchen knew know lady last late later laugh lazy learn least leave left lesson letter life light like line list listen little live long look lost lot loud love low lunch made make man many market married matter maybe meal mean meet message middle mind minute minutes miss mobile moment money month months more morning mother move movie much music must name near neck need never new news next nice night noise none noon nothing notice number nurse office often old once only open other outside over own pain paper parent park part party pass past pay people perhaps person phone pick picture piece place plan play please pocket point police poor possible pray pretty price problem pull push put question quick quiet quite radio rain read ready real reason remember rest return rich ride right road room round run sad safe said same school sea second see seen sell send sent set shop short show shower sick side sign since sister sit sitting sleep slow small smile snow some someone something sometimes son soon sorry sound speak stand start stay step stick still stop story street strong student study sun supper sure surgery table take taken talk tea teacher tell thank thing think third thought through throw ticket tired today together told tomorrow tonight took top touch town train travel tree trip true try turn type uncle under understand until upset use used usual visit voice wait wake walk walker walking wall want warm wash watch water way wear weather week weekend well went wet wheelchair while white whole wife will win window wish woman word work world worry worse worst write wrong year years yes yesterday young zimmer""".split()
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
MALAY = {"saya": "i", "aku": "i", "lemah": "weak", "mula": "start", "nak": "want", "tukar": "change", "sesuai": "best", "untuk": "for", "malam": "night", "pagi": "morning", "petang": "evening", "tengahari": "afternoon", "boleh": "can",
         "buat": "do", "senaman": "exercise", "bersenam": "exercise", "lutut": "knee", "bahu": "shoulder",
         "kaki": "leg", "tangan": "arm", "pinggang": "back", "belakang": "back", "letih": "tired",
         "penat": "tired", "pening": "dizzy", "dada": "chest", "tak": "not", "tidak": "not", "dapat": "get",
         "kod": "code", "lupa": "forgot", "bila": "when", "masa": "time", "tolong": "please", "bengkak": "swollen",
         "jatuh": "fell", "terjatuh": "fell", "tadi": "just now", "mengecil": "shrank", "otot": "muscles", "ketat": "tight", "bernafas": "breathe", "nafas": "breath",
         "susah": "hard", "duduk": "sitting", "sambil": "while",
         "seminggu": "a week", "sehari": "a day", "berapa": "how many", "kali": "times", "sakit": "pain", "pengsan": "fainted", "emak": "mother",
         "mak": "mother", "ibu": "mother", "ayah": "father", "bapa": "father", "nenek": "grandma",
         "atuk": "grandpa", "suami": "husband", "isteri": "wife", "makan": "eat", "lepas": "after", "sebelum": "before", "tidur": "sleep"}
MALAY_PHRASES = {"selamat pagi": "good morning", "selamat petang": "good afternoon",
                 "selamat tengahari": "good afternoon", "selamat malam": "good night", "apa itu": "what is",
                 "apa maksud": "what does mean", "kata laluan": "password", "terima kasih": "thank you", "macam mana": "how", "camne": "how",
                 "sesak nafas": "short of breath", "kencing manis": "diabetes", "darah tinggi": "high blood pressure",
                 "sakit jantung": "heart disease", "lemah badan": "weak",
                 # round 14 (elderly users)
                 "tahun lepas": "last year", "tahun lalu": "last year", "bulan lepas": "last month",
                 "bulan lalu": "last month", "minggu lepas": "last week", "takut jatuh": "afraid of falling",
                 "risau jatuh": "worried about falling", "otot mengecil": "muscles shrank",
                 "otot kecil": "muscles shrank", "kaki kurus": "legs are thin", "tulisan kecil": "text too small",
                 "huruf kecil": "text too small", "duduk hospital": "in hospital", "masuk hospital": "in hospital",
                 "keluar hospital": "out of hospital", "masuk wad": "in hospital",
                 # laptop safety pass 8: after a fall
                 "tak boleh jalan": "can't walk", "tidak boleh jalan": "can't walk", "tak boleh bangun": "can't get up",
                 "tidak boleh bangun": "can't get up", "tak boleh berdiri": "can't stand",
                 "tidak boleh berdiri": "can't stand", "sakit kepala": "headache", "muntah": "vomiting",
                 "mengantuk": "drowsy", "lebam": "bruised",
                 # laptop safety pass 9
                 "tergelincir": "slipped", "bilik air": "bathroom", "pagi tadi": "this morning",
                 "tadi pagi": "this morning", "berdarah": "bleeding", "dah lama": "for a long time",
                 "lama dah": "for a long time", "bila baca": "when reading"}
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
                      "better now", "feel better", "feeling better", "when can i stop", "can i stop now",
                      "still need to continue", "need to continue", "continue or not", "better already",
                      "already better", "how long more", "walk normally", "walk again", "walk properly",
                      "how long before", "did all", "did all my", "done my exercises"],
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
PREFER = [("condition_advice", "pain_mild"), ("recording_help", "app_help"), ("plan_progress", "how_often"), ("for_someone_else", "posture_result"), ("weakness_balance", "equipment"), ("video_quality", "posture_result"),
          ("partial_reps", "plan_exercises"), ("recording_help", "equipment"), ("recording_help", "plan_and_reminders"), ("plan_progress", "plan_and_reminders"), ("recording_help", "plan_exercises"),
          ("history_help", "missed_session"), ("reminders_help", "joint_noise"), ("how_often", "plan_exercises"), ("posture_result", "plan_exercises"),
          ("how_often", "diagnosis"), ("history_help", "posture_result"), ("history_help", "plan_progress"), ("best_time", "condition_advice"), ("doctor_said", "how_often"), ("doctor_said", "tired"),
          # round 14 (elderly users)
          ("muscle_loss", "getting_started"), ("muscle_loss", "safety"), ("muscle_loss", "diagnosis"),
          ("muscle_loss", "equipment"), ("muscle_loss", "weakness_balance"), ("muscle_loss", "plan_progress"),
          ("muscle_loss", "best_time"), ("muscle_loss", "for_someone_else"),
          ("fear_of_falling", "safety"), ("fear_of_falling", "equipment"), ("fear_of_falling", "how_often"),
          ("fear_of_falling", "weakness_balance"), ("fear_of_falling", "for_someone_else"),
          ("fear_of_falling", "difficulty"),
          ("text_size", "recording_help"), ("text_size", "app_help"), ("language", "text_size"),
          ("family_help", "for_someone_else"), ("family_help", "plan_progress"), ("family_help", "recording_help"),
          ("family_help", "app_help"), ("partial_reps", "difficulty"), ("partial_reps", "posture_result"),
          ("recording_help", "fear_of_falling"), ("missed_session", "muscle_loss")]


# As PREFER, unless one of the words is there (laptop pass 8: "doctor said i have sarcopenia" is about
# muscle loss, but "the doctor told me to rest after hospital" is the doctor's advice).
PREFER_UNLESS = [("muscle_loss", "doctor_said", ["rest", "berehat", "stop", "not to", "don't", "avoid", "no exercise",
                                                 "bed rest", "wait", "until"])]


# Phrases that look like a fall but are not one ("I fell asleep", "I have fallen behind").
NOT_A_FALL = [("fell asleep", "slept"), ("fallen asleep", "slept"), ("fell behind", "behind"),
              ("fallen behind", "behind"), ("falling behind", "behind"), ("fell in love", "loved"),
              ("fallen in love", "loved"), ("tripped the alarm", "set off the alarm"),
              ("tripped the switch", "set off the switch"), ("tripped the breaker", "set off the breaker"),
              # laptop safety pass 4
              ("slipped up", "made a mistake"), ("slipped me", "gave me"), ("slipped into", "eased into"),
              ("fell for", "believed"), ("fell off the guest list", "was left off the list"),
              ("fell off the list", "was left off the list"), ("tripped over my words", "stumbled over my words"),
              ("tripped over my tongue", "stumbled over my words"), ("found her balance", "balanced"),
              ("found his balance", "balanced"), ("found my balance", "balanced"), ("found her feet", "settled"),
              ("found his feet", "settled"), ("fell cinta", "loved"), ("jatuh cinta", "loved"),
              ("collapsed onto the sofa", "sat on the sofa"), ("collapsed onto the bed", "lay on the bed"),
              ("collapsed onto the couch", "sat on the couch"), ("collapsed on the sofa", "sat on the sofa"),
              ("collapsed on the bed", "lay on the bed")]
# "I nearly hit my head" / "almost fell" do not make an accident an emergency. Symptoms still count
# ("I almost blacked out" is a warning sign itself).
NEAR_MISS = {"nearly", "almost"}
# Signs no cancel phrase may hide ("doing her exercise and now she is lying on the floor not moving").
HARD_SIGNS = ["not moving", "not answering", "not responding", "unconscious", "can't move", "cannot move",
              "cant move", "bleeding", "blue lips", "not breathing", "tak sedar"]
ACCIDENT_WORDS = ("fell", "fall", "fallen", "hit", "slipped", "slip", "tripped", "trip", "collapsed")
# Round 14 (elderly users): a fall long ago is history, not an emergency ("I fell last year and now I'm
# scared"), unless it still hurts; and "what if I can't get up after a fall" is a question about falling.
FALL_WORDS = {"fell", "fall", "falls", "fallen", "falling", "jatuh", "tripped", "slipped"}
PAST_TIME = ["last year", "years ago", "year ago", "months ago", "month ago", "last month", "long time ago",
             "long ago", "in the past year", "in the past few years", "years back"]
# Words that make a fall recent whatever else is said ("i fell in the past hour", "kalau dia jatuh tadi").
RECENT = ["just now", "tadi", "right now", "today", "this morning", "this afternoon", "this evening", "tonight",
          "last night", "yesterday", "semalam", "earlier", "moment ago", "minutes ago", "minute ago", "hour ago",
          "hours ago", "past hour", "just fell", "just fallen", "just had a fall", "just collapsed", "just slipped",
          "baru fell"]
STILL_HURT = ["hurt", "hurts", "hurting", "pain", "painful", "sakit", "swollen", "swelling", "bruise", "bruised",
              "still can't", "still cannot", "on the floor", "lying", "confused", "confusion", "keliru", "drowsy",
              "sleepy", "vomit", "vomiting", "headache", "headaches", "not the same", "been the same", "not himself",
              "not herself", "getting worse", "worse since", "limp", "limping", "numb", "numbness",
              "can't put weight", "cannot put weight", "can't bear weight", "cannot bear weight", "still cant", "still unable", "still limping",
              "still sore", "can't walk", "cannot walk", "cant walk", "bleeding"]
OLD_ACCIDENT_WORDS = FALL_WORDS | {"hit", "trip", "slip", "banged", "knocked"}
HYPOTHETICAL = ["what if i", "what if you", "what if she", "what if he", "if i", "if you", "if i ever",
                "in case i", "in case you", "kalau saya", "kalau", "supposing i", "suppose i", "how do i",
                "how to", "how can i", "if", "what if", "suppose", "supposing", "in case"]


def _hypothetical(words: list[str], i: int) -> bool:
    """The words just before position i make it a question about what to do ("what if i can't get up")."""
    before = f" {' '.join(words[max(0, i - 3):i])} "
    return any(before.endswith(f" {h} ") for h in HYPOTHETICAL)


# Laptop pass 9: a time word counts only in the fall's own sentence ("my mum fell years ago; today she
# started the plan" is an old fall), and "earlier in my life" is not "earlier today".
CLAUSE_BREAK = re.compile(r"[.;!?]+|\bbut\b|\btapi\b")
PAST_PHRASES = [("earlier in my life", "long ago"), ("earlier years", "long ago"), ("years earlier", "long ago"),
                ("when i was young", "long ago"), ("when i was younger", "long ago"), ("as a child", "long ago"),
                ("as a kid", "long ago")]
# A fall told with no "I" or name in front ("fell down just now, knee berdarah", "atuk tergelincir pagi
# tadi"): urgent when its own sentence says it was recent.
RECENT_FALL_VERBS = {"fell", "fallen", "slipped", "tripped", "collapsed"}
PEOPLE = {"i", "he", "she", "dia", "mother", "father", "mum", "mom", "dad", "grandma", "grandpa", "grandmother",
          "grandfather", "husband", "wife", "son", "daughter", "we", "they", "uncle", "aunt", "patient"}
# What may follow "slipped"/"tripped" in a fall ("slipped in the bathroom"), not "slipped the note under".
SLIP_NEXT = {"in", "on", "at", "dalam", "di", "over", "down", "and", "while", "when", "near", "outside", "inside",
             "just", "this", "today", "yesterday", "earlier", "tadi", "semalam", "from", "off"}
# Long-standing symptoms are not new warning signs (laptop pass 9 debatable cases).
CHRONIC = {"numb": ["years ago", "for years", "since the operation", "since my operation", "since surgery",
                    "since the surgery", "since my surgery", "for a long time", "long time", "always", "since birth",
                    "since my stroke"],
           "vomit": ["after eating", "right after eating", "after a meal", "after meals", "full stomach",
                     "after lunch", "after dinner", "after breakfast", "lepas makan"]}
CHRONIC["numbness"] = CHRONIC["numb"]
CHRONIC["vomiting"] = CHRONIC["vomit"]


def _clauses(text: str) -> list[list[str]]:
    out = []
    for part in CLAUSE_BREAK.split(text.lower()):
        p = f" {clean(part)} "
        for a, c in NOT_A_FALL + PAST_PHRASES:
            p = p.replace(f" {a} ", f" {c} ")
        if p.strip():
            out.append(p.split())
    return out


def _when(phrase: str, clauses: list[list[str]], words: list[str]) -> tuple[bool, bool]:
    """(old, recent) for a fall phrase, judged in the sentence it is in; a symptom anywhere keeps it urgent."""
    if any(find_phrase(h, words) for h in STILL_HURT + HARD_SIGNS):
        return False, True
    own = [c for c in clauses if find_phrase(phrase, c)] or [words]
    recent = any(find_phrase(p, c) for c in own for p in RECENT)
    old = not recent and any(find_phrase(p, c) for c in own for p in PAST_TIME)
    return old, recent


def _recent_fall(clauses: list[list[str]]) -> bool:
    for c in clauses:
        if not any(find_phrase(p, c) for p in RECENT):
            continue
        for i, w in enumerate(c):
            if w not in RECENT_FALL_VERBS:
                continue
            k = i - 1
            while k >= 0 and c[k] in ("just", "baru", "has", "had", "have", "suddenly"):
                k -= 1
            if k >= 0 and c[k] not in PEOPLE:
                continue                               # "the phone fell", "the price has fallen today"
            if NEGATORS & set(c[max(0, i - 2):i]) or _hypothetical(c, i):
                continue
            if w in ("slipped", "tripped") and i + 1 < len(c) and c[i + 1] not in SLIP_NEXT:
                continue                               # "slipped the note under the door this morning"
            return True
    return False


# A blood pressure reading of 180/110 or more (the HYPERTENSION advice: do not exercise that day).
BP_READING = re.compile(r"\b(\d{2,3})\s*/\s*(\d{2,3})\b(?!\s*(?:min|mins|minute|minutes|reps|rep|sets|set|"
                        r"km|steps|points|marks|%|days|times|seconds|secs))")
# A low blood sugar reading with a symptom ("sugar 3.0 feeling shaky"): under 4.0 mmol/L or 70 mg/dL.
SUGAR_READING = re.compile(r"\b(?:sugar|glucose|gula|bgl)\D{0,15}?(\d+(?:\.\d+)?)")
LOW_SUGAR_SIGNS = ("shaky", "shaking", "shake", "sweaty", "sweating", "dizzy", "confused", "weak", "faint",
                   "pening", "menggeletar", "menggigil", "berpeluh", "lemah", "keliru", "trembling", "blur")


def low_sugar(text: str) -> bool:
    low = text.lower()
    if not any(w in low for w in LOW_SUGAR_SIGNS):
        return False
    for v in SUGAR_READING.findall(low):
        x = float(v)
        if x < 4.0 or 20 <= x < 70:
            return True
    return False


def high_bp(text: str) -> bool:
    for sys_, dia in BP_READING.findall(text):
        s_, d_ = int(sys_), int(dia)
        if 70 <= s_ <= 280 and 40 <= d_ <= 180 and s_ > d_ and (s_ >= 180 or d_ >= 110):
            return True
    return False


def crisis(text: str | None) -> bool:
    """Thoughts of suicide or self-harm: checked before everything else."""
    if not text:
        return False
    padded = f" {clean(text)} "
    for a, b in NOT_A_CRISIS:
        padded = padded.replace(f" {a} ", f" {b} ")
    words = padded.split()
    for p in rules().get("crisis", []):
        for i in find_phrase(p, words):
            # "I don't want to die from a fall" is a fear, not a crisis. Only a negation DIRECTLY in
            # front counts: "no, i want to die" and "not eating, not sleeping, want to die" are crises
            # (laptop pass 5).
            prev = words[i - 1] if i >= 1 else ""
            if prev in CRISIS_NEGATORS or words[max(0, i - 2):i] == ["do", "not"]:
                continue
            return True
    return False


CRISIS_NEGATORS = {"don't", "dont", "never", "not"}
# "end everything for today, I'm done with the session" is about the session.
NOT_A_CRISIS = [("end everything for today", "stop for today"), ("end things for today", "stop for today")]

# Too many pills, with or without the word overdose (laptop safety passes 5 and 6): an emergency
# even when it was not on purpose (a paracetamol overdose can be fatal with no early symptoms).
# Read word by word: a taking verb, then within 8 words a medicine, with an amount that is large
# (8+ tablets, strips of 10, a whole bottle, in one go, all of them...). Normal use ("took all my
# pills today as prescribed", "took 10 minutes to swallow the tablets") is not an overdose.
OD_VERBS = {"took", "taken", "swallowed", "ate", "eaten", "makan", "telan", "drank", "drunk", "minum", "finished",
            "habis", "habiskan"}
OD_SUBSTANCES = {"pill", "pills", "tablet", "tablets", "panadol", "paracetamol", "ubat", "medicine", "medicines",
                 "medication", "capsule", "capsules", "syrup", "insulin", "warfarin", "biji", "painkiller",
                 "painkillers", "strip", "strips", "papan", "blister", "blisters", "ones"}
OD_NUMBER_WORDS = {"eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20,
                   "thirty": 30, "forty": 40, "fifty": 50, "lapan": 8, "sembilan": 9, "sepuluh": 10, "belas": 11,
                   "puluh": 20}
OD_UNITS_NOT_PILLS = {"minute", "minutes", "min", "mins", "hour", "hours", "day", "days", "time", "times", "mg",
                      "ml", "second", "seconds", "week", "weeks", "year", "years", "steps", "step"}
OD_STRIPS = {"strip", "strips", "papan", "kepingan", "sheet", "sheets", "blister", "blisters"}
OD_LARGE = ["whole bottle", "whole box", "whole pack", "whole strip", "a bottle", "one bottle", "satu botol",
            "the bottle", "a whole", "handful", "in one go", "at once", "all of them", "all of", "all my", "all the",
            "semua", "banyak", "lots of", "a lot of", "too many", "too much", "every pill", "the rest of"]
# Words between an amount and what it counts ("a bottle OF HIS pills", "all OF MY MUM'S pills").
OD_FILLERS = {"of", "the", "my", "his", "her", "their", "a", "an", "mum's", "dad's", "mother's", "father's",
              "wife's", "husband's", "sleeping", "pain", "heart", "bp", "blood", "pressure", "white", "blue", "red",
              "yellow", "little", "small", "big", "saya", "dia"}
OD_SINGLE = ["a pill", "one pill", "1 pill", "a tablet", "one tablet", "1 tablet", "satu biji", "sebiji",
             "a capsule", "one capsule"]
OD_NORMAL_USE = ["as prescribed", "like the doctor said", "the doctor told", "as usual", "every day", "everyday",
                 "daily", "before the session", "after the session", "before exercise", "after exercise",
                 "before the exercise", "after the exercise", "every morning", "every night"]
OD_NOT_TAKING = [("took me off", "removed"), ("took him off", "removed"), ("took her off", "removed"),
                 ("taken off", "removed")]
OD_CHILD = {"grandson", "granddaughter", "grandchild", "child", "kid", "baby", "toddler", "cucu", "anak"}
OD_DOUBLE = ["double my insulin", "double insulin", "double dose of insulin", "twice my insulin",
             "extra insulin", "insulin twice", "insulin two times", "insulin 2 times", "double my warfarin",
             "double warfarin", "extra warfarin", "warfarin twice", "double my blood thinner"]
OD_BOXES = ["medicine box", "pill box", "pillbox", "medicine cabinet", "kotak ubat"]
OVERDOSE_ANSWER = ("Taking too many pills can be dangerous even if you feel fine now. Call 999 or go to the nearest "
                   "emergency department now, and take the medicine packets with you; do not wait for symptoms. "
                   "If this was on purpose, or you are thinking of harming yourself, you are not alone: "
                   "Befrienders KL 03-7627 2929 (24 hours) or Talian HEAL 15555 (8 am to midnight).")
# Household chemicals swallowed (laptop pass 7): Dettol, bleach, floor cleaner, pesticide...
POISONS = ["dettol", "clorox", "bleach", "floor cleaner", "cleaner", "pesticide", "insecticide", "racun",
           "kerosene", "minyak tanah", "antifreeze", "weed killer", "detergent", "toilet cleaner", "lysol"]
POISON_VERBS = {"drank", "drink", "drinks", "swallowed", "swallow", "ate", "eaten", "minum", "telan", "took", "had"}
POISON_ANSWER = ("Swallowing a cleaning product, pesticide or other chemical is an emergency. Call 999 now or go "
                 "to the nearest emergency department, and take the bottle with you. Do not try to make them "
                 "vomit. If it was on purpose, or you are thinking of harming yourself, you are not alone: "
                 "Befrienders KL 03-7627 2929 (24 hours) or Talian HEAL 15555 (8 am to midnight).")


def _is_medicine(w: str) -> bool:
    return w in OD_SUBSTANCES or w.startswith("pill") or w.startswith("tablet") or w.startswith("painkiller")


def _counts_medicine(words: list[str], j: int, stop: int) -> bool:
    """Does the amount ending at position j count medicine? The next real word after it must be a
    medicine word, or nothing ("took all of them"): "a bottle of water", "all the steps" do not."""
    k = j + 1
    while k < stop and words[k] in OD_FILLERS:
        k += 1
    if k >= stop or _is_medicine(words[k]) or words[k] in ("them", "it", "everything", "lagi"):
        return True
    # one describing word may come first ("a bottle of COUGH syrup"), not more ("a bottle of water")
    return k + 1 < stop and _is_medicine(words[k + 1])


def _amount(words: list[str], lo: int, hi: int) -> int:
    """Largest tablet count stated between positions lo and hi (strips count as 10 tablets)."""
    best = 0
    for j in range(lo, hi):
        w = words[j]
        n = int(w) if w.isdigit() else OD_NUMBER_WORDS.get(w, 0)
        if w == "dua" and j + 1 < len(words) and words[j + 1] in ("puluh", "belas"):
            n = 20 if words[j + 1] == "puluh" else 12
        if not n:
            continue
        nxt = words[j + 1] if j + 1 < len(words) else ""
        if nxt in OD_UNITS_NOT_PILLS:
            continue                                     # "10 minutes", "500 mg", "ten steps"
        if nxt in OD_STRIPS:
            n *= 10
        if nxt == "or" and j + 2 < hi:                   # "9 or 10 of the white ones"
            continue
        if not _counts_medicine(words, j, hi):
            continue
        best = max(best, n)
    return best


def poisoning(text: str | None) -> bool:
    if not text:
        return False
    words = re.findall(r"[a-z0-9']+", text.lower())
    for i, w in enumerate(words):
        if w in POISON_VERBS:
            seg = f" {' '.join(words[i + 1:i + 6])} "
            if any(f" {p} " in seg for p in POISONS):
                return True
    return False


def overdose(text: str | None) -> bool:
    if not text:
        return False
    low = text.lower()
    words = re.findall(r"[a-z0-9']+", low)
    padded = f" {' '.join(words)} "
    for a, b in OD_NOT_TAKING:
        padded = padded.replace(f" {a} ", f" {b} ")
    words = padded.split()
    if any(f" {d} " in padded for d in OD_DOUBLE):
        return True
    if any(f" {n} " in padded for n in OD_NORMAL_USE):
        return False
    for i, w in enumerate(words):
        if w not in OD_VERBS:
            continue
        # One clause only: "ate all the biscuits and took my pills" is two things.
        stop = min(len(words), i + 12)
        for j in range(i + 1, stop):
            if words[j] in OD_CLAUSE_BREAKS or words[j] in OD_VERBS:
                stop = j
                break
        seg_words = words[i + 1:stop]
        seg = f" {' '.join(seg_words)} "
        has_medicine = any(_is_medicine(x) for x in seg_words[:8])
        if any(f" {b} " in seg for b in OD_BOXES):
            return True                                  # "swallowed something from my medicine box"
        if w in ("swallowed", "telan") and _amount(words, i + 1, stop) >= 8:
            return True                                  # "swallowed 9 or 10 of the white ones"
        if not has_medicine:
            continue
        if any(c in OD_CHILD for c in words[max(0, i - 3):i]):
            return True                                  # "my grandson ate my pills"
        if _amount(words, i + 1, stop) >= 8:
            return True
        single = any(f" {s} " in seg for s in OD_SINGLE)
        for p in OD_LARGE:
            if single and p in ("at once", "in one go"):
                continue                                 # "took a pill at once"
            idx = seg.find(f" {p} ")
            if idx < 0:
                continue
            end_word = len(seg[:idx + len(p) + 1].split()) - 1   # index of the amount's last word
            if p in ("at once", "in one go") or _counts_medicine(seg_words, end_word, len(seg_words)):
                return True
    return False


OD_CLAUSE_BREAKS = {"and", "then", "but", "dan", "lepas", "after", "before", "so", "because", "while"}


def red_flag(text: str | None) -> bool:
    if not text:
        return False
    if high_bp(text) or low_sugar(text):
        return True
    r = rules()
    # Neutralise phrases that look like a fall first, then spell-correct the result: correction can
    # break the phrase ("guest list" -> "guess list"), and skipping correction hid typos next to it
    # ("fell for a scam and then she colapsed", laptop pass 5).
    padded = f" {clean(text)} "
    for a, b in NOT_A_FALL + PAST_PHRASES:
        padded = padded.replace(f" {a} ", f" {b} ")
    base = padded.strip()
    clauses = _clauses(text)
    if _recent_fall(clauses):
        return True
    for variant in {base, correct(base)}:
        words = variant.split()
        for phrase in r["red_flags"]:
            for i in find_phrase(phrase, words):
                before = set(words[max(0, i - 2):i])
                if NEGATORS & before:
                    continue
                if NEAR_MISS & before and any(w in phrase.split() for w in ACCIDENT_WORDS):
                    continue
                if OLD_ACCIDENT_WORDS & set(phrase.split()):
                    old, recent = _when(phrase, clauses, words)
                    if old:
                        continue                       # "i fell last year", "hit my head years ago"
                    if FALL_WORDS & set(phrase.split()) and _hypothetical(words, i) and not recent:
                        continue                       # "if i fall", not "what if he fell? he's on the floor"
                if phrase in CHRONIC and any(find_phrase(c, words) for c in CHRONIC[phrase]) \
                        and not any(find_phrase(s, words) for s in ("suddenly", "sudden", "tiba tiba")):
                    continue                           # "numbness since the operation 3 years ago"
                return True
        for combo in r.get("red_flag_combos", []):
            anchors, symptoms, window = combo[:3]
            if len(combo) > 3 and any(find_phrase(c, words) for c in combo[3]) \
                    and not any(find_phrase(h, words) for h in HARD_SIGNS):
                continue                               # a planning question, or doing the exercise
            for anchor in anchors:
                fall = bool(FALL_WORDS & set(anchor.split()))
                if fall and _when(anchor, clauses, words)[0]:
                    continue                           # "she fell last year and couldn't stand for a week"
                for i in find_phrase(anchor, words):
                    if COMBO_NEGATORS & set(words[max(0, i - 2):i]):
                        continue                       # "no chest pain", "never had breathing trouble"
                    lo = max(0, i - window)
                    near = words[lo:i + window + 1]
                    for s in symptoms:
                        for j in find_phrase(s, near):
                            if fall and (_hypothetical(words, i) or _hypothetical(words, lo + j)) \
                                    and not _when(anchor, clauses, words)[1]:
                                continue               # "what if i can't get up after a fall"
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
                   "sugar level": "DIABETES", "my sugar": "DIABETES", "glucose": "DIABETES",
                   "pregnant": "PREGNANCY", "pregnancy": "PREGNANCY", "expecting a baby": "PREGNANCY",
                   "mengandung": "PREGNANCY", "hamil": "PREGNANCY", "hip replacement": "JOINT_REPLACEMENT",
                   "knee replacement": "JOINT_REPLACEMENT", "joint replacement": "JOINT_REPLACEMENT",
                   "replacement surgery": "JOINT_REPLACEMENT", "new hip": "JOINT_REPLACEMENT",
                   "new knee": "JOINT_REPLACEMENT", "replaced hip": "JOINT_REPLACEMENT",
                   "replaced knee": "JOINT_REPLACEMENT", "wound": "SURGERY_WOUND", "stitches": "SURGERY_WOUND",
                   "incision": "SURGERY_WOUND", "cast": "INJURY", "plaster": "INJURY",
                   "fracture": "INJURY", "fractured": "INJURY", "broken bone": "INJURY", "broke my": "INJURY",
                   "sprain": "INJURY", "sprained": "INJURY"}


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
    lims = list(limitations or [])
    # One line for both sides (phone test, 8 Oct): "go gently with your right leg ... left leg".
    both = {"LEFT_LEG_MOBILITY": ("RIGHT_LEG_MOBILITY", "Go gently with both legs and keep a support within reach."),
            "LEFT_ARM_MOBILITY": ("RIGHT_ARM_MOBILITY", "Only move your arms within a range that feels comfortable.")}
    for left, (right, line) in both.items():
        if left in lims and right in lims:
            lims = [x for x in lims if x not in (left, right)]
            notes.append(line)
    notes += [r["limitation_notes"][x] for x in lims if x in r["limitation_notes"]]
    if risk_level in r["risk_notes"]:
        notes.append(r["risk_notes"][risk_level])
    return notes


# ---------------------------------------------------------------------------
# Reply
# ---------------------------------------------------------------------------

def _listing(items):
    return [{"key": i["key"], "title": i["title"]} for i in items]


# A mistake name counts as a question about it only with one of these ("what does hips sag mean",
# "the result said trunk lean"), so "I keep leaning on the chair" is not answered with a definition.
GLOSSARY_CUES = ["mean", "means", "meaning", "what is", "what's", "whats", "what does", "what do", "said",
                 "says", "say", "saying", "result", "told", "mistake", "feedback", "explain", "maksud"]


def glossary_match(text: str) -> dict | None:
    words = clean(text).split()
    if not any(find_phrase(c, words) for c in GLOSSARY_CUES):
        return None
    # Exact names only: the topic matcher treats "raise" and "lift" alike, but "heel raises" is not
    # the mistake "heels lift".
    padded = f" {' '.join(words)} "
    hits = [(len(p), key) for p, key in rules().get("glossary", {}).items() if f" {p} " in padded]
    if not hits:
        return None
    key = max(hits)[1]                                   # the longest name ("shoulder shrug" over "shrug")
    return next((i for i in rules()["intents"] if i["key"] == key), None)


def match(plan_id: str | None, text: str) -> tuple[dict | None, str | None]:
    """The rule a typed question resolves to, and how it was matched."""
    g = glossary_match(text)
    if g is not None:
        return g, "glossary"
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
    ex = [h for h in hits if h[2]["key"].startswith("exercise:")]
    if len({h[2]["key"] for h in ex if h[1] >= 2}) >= 2 and "plan_exercises" in {i["key"] for i in intents}:
        # Two exercises named in full ("heel raise or sit to stand") ask about the plan's order.
        return next(i for i in intents if i["key"] == "plan_exercises"), "keyword"
    if len({h[2]["key"] for h in ex}) > 1:
        # The most specific name wins ("marching on the spot" over "marching") ...
        longest = max(h[1] for h in ex)
        hits = [h for h in hits if not h[2]["key"].startswith("exercise:") or h[1] == longest]
    named = {h[2]["key"] for h in hits if h[2]["key"].startswith("exercise:")}
    in_plan = {h[2]["key"] for h in hits if h[2]["key"].startswith("exercise:") and h[2]["show"]}
    if len(in_plan) == 1 and len(named) > 1:
        # "march" names march in place and seated marching: the one in the patient's plan is meant.
        hits = [h for h in hits if not h[2]["key"].startswith("exercise:") or h[2]["show"]]
    exercises = {h[2]["key"] for h in hits if h[2]["key"].startswith("exercise:")}
    if len(exercises) >= 2 and "plan_exercises" in {i["key"] for i in intents}:
        # "Which comes first, heel raise or sit to stand?" is about the plan's order.
        return next(i for i in intents if i["key"] == "plan_exercises"), "keyword"
    if len(clean(text).split()) <= 3:
        small = [h for h in hits if h[2].get("small_talk")]
        if small:                                    # "good morning", "help", "ok thanks"
            return max(small, key=lambda h: (h[0], h[1]))[2], "keyword"
    keys = {h[2]["key"] for h in hits}
    if "difficulty" in keys:
        # "My arm cannot go up to shoulder height" is about not managing it, not how the exercise goes.
        hits = [h for h in hits if not h[2]["key"].startswith("exercise:")]
        keys = {h[2]["key"] for h in hits}
    for better, general in PREFER:
        if better in keys and general in keys:
            hits = [h for h in hits if h[2]["key"] != general]
    words = clean(text).split()
    for better, general, unless in PREFER_UNLESS:
        if better in keys and general in keys and not any(find_phrase(u, words) for u in unless):
            hits = [h for h in hits if h[2]["key"] != general]
    if hits:
        return max(hits, key=lambda h: (h[0], h[1]))[2], "keyword"
    score, best = max(((fuzzy_score(text, i), i) for i in intents), key=lambda s: s[0])
    if score >= THRESHOLD:
        return best, "similar_question"
    best, score = overlap_match(plan_id, text)
    return (best, "keyword_overlap") if best is not None and score >= OVERLAP_THRESHOLD else (None, None)


# Follow-ups that point back at the previous answer ("how many reps for that one?").
REFERENCES = ["it", "that", "this", "that one", "this one", "that exercise", "this exercise", "the exercise",
              "same one", "the same"]
# A follow-up may replace these general answers with the exercise discussed just before.
FOLLOW_GENERAL = {"how_to", "plan_exercises", "how_often", "difficulty"}


def follow_up(text: str | None, chosen: dict | None, previous: str | None, by_key: dict) -> dict | None:
    """The previous exercise rule when the question refers back to it and nothing more specific matched."""
    if not text or not previous or not previous.startswith("exercise:") or previous not in by_key:
        return None
    if chosen is not None and chosen["key"] not in FOLLOW_GENERAL:
        return None
    words = clean(text).split()
    return by_key[previous] if any(find_phrase(r, words) for r in REFERENCES) else None


def reply(plan_id: str | None, category: str | None, text: str | None,
          conditions: list[str] | None = None, limitations: list[str] | None = None,
          risk_level: str | None = None, local_time: tuple[int, int] | None = None,
          previous_category: str | None = None) -> dict:
    r = rules()
    by_key = {i["key"]: i for i in intents_for(plan_id)}
    base = {"categories": _listing(categories_for(plan_id)), "rules_version": r["version"]}

    if crisis(text):
        return {**base, "answer": r["crisis_answer"], "category": "crisis", "title": "You are not alone",
                "is_matched": True, "matched_by": "crisis", "follow_ups": [], "notes": [], "action": None}
    if overdose(text):
        return {**base, "answer": OVERDOSE_ANSWER, "category": "overdose", "title": "Too many pills",
                "is_matched": True, "matched_by": "overdose", "follow_ups": [], "notes": [], "action": None}
    if poisoning(text):
        return {**base, "answer": POISON_ANSWER, "category": "poisoning", "title": "Swallowed a chemical",
                "is_matched": True, "matched_by": "poisoning", "follow_ups": [], "notes": [], "action": None}
    if red_flag(text):
        return {**base, "answer": r["red_flag_answer"], "category": "red_flag", "title": "Urgent safety advice",
                "is_matched": True, "matched_by": "red_flag", "follow_ups": [], "notes": [], "action": None}

    chosen, how = None, None
    if category and category in by_key:
        chosen, how = by_key[category], "category"
    elif text and text.strip():
        chosen, how = match(plan_id, text)
        followed = follow_up(text, chosen, previous_category, by_key)
        if followed is not None:
            chosen, how = followed, "follow_up"

    if chosen is None:
        return {**base, "answer": r["not_recognised"], "category": None, "title": None, "is_matched": False,
                "matched_by": None, "follow_ups": [], "notes": [], "action": None}

    mentioned = conditions_in(text) if chosen["key"] in ("condition_advice", "safety") else []
    all_conditions = list(dict.fromkeys((conditions or []) + mentioned))
    # Time first: "rest now, it is late" matters more than the condition reminders that follow.
    notes = time_notes(chosen, local_time, all_conditions, limitations)
    notes += tailor_notes(chosen, all_conditions, limitations, risk_level)
    base_answer = chosen["answer"]
    # A condition named in the question is answered on its own (phone test, 8 Oct: with the profile's
    # conditions added the answer ran to 230 words); otherwise the profile's conditions are used.
    asked_first = mentioned if any(c in r.get("condition_detail", {}) for c in mentioned) else all_conditions
    details = [r["condition_detail"][c] for c in asked_first if c in r.get("condition_detail", {})]
    if chosen["key"] == "condition_advice" and details:
        # A different answer for each condition (Table 4.2.2): the patient's own conditions first.
        base_answer = " ".join(details) + " " + r["condition_closing"]
    answer = base_answer + ("\n\n" + " ".join(notes) if notes else "")
    follow = [by_key[k] for k in chosen.get("follow_ups", []) if k in by_key]
    return {**base, "answer": answer, "category": chosen["key"], "title": chosen["title"], "is_matched": True,
            "matched_by": how, "follow_ups": _listing(follow), "notes": notes, "action": chosen.get("action")}
