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
import unicodedata
from functools import lru_cache
from pathlib import Path

from rapidfuzz import fuzz, process

from .layout import layout
from rapidfuzz.distance import OSA

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
    two = re.sub(r"(.)\1{2,}", r"\1\1", w)
    for v in (two, one):                                 # the word it is: "goooood" good, "youuu" you (3.90)
        if v in SHORT_WORDS or v in dictionary():
            return v
    return two
NEGATORS = {"no", "not", "without", "never", "don't", "dont", "didn't", "didnt", "haven't", "havent", "isn't",
            "isnt", "wasn't", "wasnt", "nor"}
# Everyday words mapped onto the words the rules use.
SYNONYMS = {"pane": "pain", "panes": "pains", "workout": "exercise", "workouts": "exercises", "train": "exercise", "training": "exercising",
            "lift": "raise", "lifts": "raises", "lifting": "raising", "lifted": "raised", "high": "height",
            "physio": "physiotherapist", "doc": "doctor", "vid": "video", "pic": "photo"}
# Common Malay words patients mix into English (Malaysian users). Single words; phrases are in
# MALAY_PHRASES. Body-part and symptom words map to the English the rules (and red flags) know.
MALAY = {"apa": "what", "saya": "i", "aku": "i", "lemah": "weak", "mula": "start", "nak": "want", "tukar": "change", "sesuai": "best", "untuk": "for", "malam": "night", "pagi": "morning", "petang": "evening", "tengahari": "afternoon", "boleh": "can",
         "buat": "do", "senaman": "exercise", "bersenam": "exercise", "senam": "exercise", "lutut": "knee", "bahu": "shoulder",
         "kaki": "leg", "tangan": "arm", "pinggang": "back", "belakang": "back", "letih": "tired",
         "penat": "tired", "pening": "dizzy", "dada": "chest", "tak": "not", "tidak": "not", "dapat": "get",
         "kod": "code", "lupa": "forgot", "bila": "when", "masa": "time", "tolong": "please", "bengkak": "swollen",
         "pitam": "fainted", "senget": "crooked", "herot": "crooked", "pelat": "slurred", "kebas": "numb",
         "lumpuh": "paralysed",
         # 3.87: aches in everyday Malay, Malaysian Chinese and Tamil ("lenguh badan", "my leg very suan",
         # "mutti vali": knee pain)
         "lenguh": "sore", "sengal": "aching", "suan": "sore", "sien": "bored", "paiseh": "sorry",
         "kancheong": "anxious", "vali": "pain", "mutti": "knee", "kaal": "leg", "thalai": "head",
         "mudhugu": "back", "kazhuthu": "neck", "romba": "very",
         "jatuh": "fell", "terjatuh": "fell", "tergelincir": "slipped", "tersandung": "tripped",
         "tersadung": "tripped", "tergolek": "fell", "rebah": "collapsed", "tadi": "just now", "mengecil": "shrank", "otot": "muscles", "ketat": "tight", "bernafas": "breathe", "nafas": "breath",
         "susah": "hard", "duduk": "sitting", "sambil": "while",
         "seminggu": "a week", "sehari": "a day", "berapa": "how many", "kali": "times", "sakit": "pain", "pengsan": "fainted", "emak": "mother",
         "mak": "mother", "ibu": "mother", "ayah": "father", "bapa": "father", "nenek": "grandma",
         "atuk": "grandpa", "suami": "husband", "isteri": "wife", "makan": "eat", "lepas": "after", "sebelum": "before", "tidur": "sleep"}
MALAY_PHRASES = {# 3.54 (15 Oct): everyday and Malay names for the profile's conditions (longest first)
                 "sakit buah pinggang": "kidney disease", "penyakit buah pinggang": "kidney disease",
                 "penyakit jantung": "heart disease", "sakit jantung": "heart disease", "angin ahmar": "stroke",
                 "sakit sendi": "arthritis", "radang sendi": "arthritis", "tulang rapuh": "osteoporosis",
                 "penyakit lelah": "asthma", "sakit lelah": "asthma", "ada lelah": "have asthma",
                 "ada semput": "have asthma", "bp tinggi": "high blood pressure", "high bp": "high blood pressure",
                 "baru bersalin": "just gave birth", "lepas bersalin": "just gave birth",
                 # 3.87: aches and feelings in everyday Malay and Malaysian Chinese
                 "dah tak larat": "no energy", "tak larat": "no energy", "tidak larat": "no energy",
                 "urat tegang": "muscles are tight", "suan tong": "sore", "pai seh": "sorry", "kan cheong": "anxious",
                 "lau sai": "diarrhoea", "cirit birit": "diarrhoea", "sakit perut": "stomach ache",
                 "selamat pagi": "good morning", "selamat petang": "good afternoon",
                 "selamat tengahari": "good afternoon", "selamat malam": "good night", "apa itu": "what is",
                 "apa maksud": "what does mean", "kata laluan": "password", "terima kasih": "thank you",
                 # 3.59: "macam mana nak buat" is "how to do", not "how want do"; getting up from a chair
                 "macam mana nak": "how to", "camne nak": "how to", "susah nak bangun": "hard to get up",
                 "susah bangun": "hard to get up", "tak boleh bangun dari kerusi": "can't get up from the chair",
                 "tidak boleh bangun dari kerusi": "can't get up from the chair",
                 "bangun dari kerusi": "get up from the chair",
                 "bangun dari katil": "get up from bed", "macam mana": "how", "camne": "how",
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
                 "lama dah": "for a long time", "bila baca": "when reading",
                 # laptop safety pass 10
                 "tak boleh bernafas": "can't breathe", "tidak boleh bernafas": "can't breathe",
                 "tak dapat bernafas": "can't breathe", "tidak dapat bernafas": "can't breathe",
                 "sukar bernafas": "hard to breathe", "susah bernafas": "hard to breathe",
                 "dah ok": "fine now", "sekarang ok": "fine now", "hari ni": "today", "hari ini": "today",
                 "hampir jatuh": "nearly fell", "nyaris jatuh": "nearly fell",
                 # PC safety pass 14: stroke signs, fainting, bleeding
                 "nak pitam": "feel like fainting", "rasa nak pitam": "feel like fainting",
                 "mulut senget": "mouth crooked", "muka senget": "face crooked", "mulut herot": "mouth crooked",
                 "muka herot": "face crooked", "cakap pelat": "slurred speech", "percakapan pelat": "slurred speech",
                 "hilang kesedaran": "lost consciousness", "tak sedarkan diri": "unconscious",
                 "tidak sedarkan diri": "unconscious", "darah tak berhenti": "bleeding won't stop",
                 "darah tidak berhenti": "bleeding won't stop", "banyak darah": "bleeding a lot",
                 "berdarah banyak": "bleeding a lot",
                 # 3.54 (15 Oct, generated warning signs): a racing heart, a knock to the head, bleeding
                 "darah banyak keluar": "bleeding a lot", "keluar banyak darah": "bleeding a lot",
                 "jantung berdebar": "heart pounding", "jantung berdegup kencang": "heart racing",
                 "jantung laju": "heart racing", "jantung berdenyut laju": "heart racing",
                 "dada berdebar": "heart pounding", "kepala terhantuk": "hit my head",
                 "terhantuk kepala": "hit my head", "kepala terhentak": "hit my head",
                 # 3.67: "bp" alone ("my bp is high today", "bp 120/80"); last, so "high bp" keeps its phrase.
                 "low bp": "low blood pressure", "bp": "blood pressure"}
CONTRACTIONS = {"dont": "don't", "cant": "can't", "wont": "won't", "im": "i'm", "ive": "i've", "isnt": "isn't",
                "doesnt": "doesn't", "didnt": "didn't", "havent": "haven't", "whats": "what's", "thats": "that's",
                "u": "you", "ur": "your", "pls": "please", "plz": "please", "r": "are", "abt": "about"}
# 3.55: short forms typed for whole words (respell reads them as the word)
SHORT_WORDS_TYPED = {"y": "why", "alot": "a lot", "sys": "says", "pln": "plan", "acc": "account", "pwd": "password", "pw": "password",
                     "tdy": "today", "tmr": "tomorrow", "tmrw": "tomorrow", "b4": "before", "ppl": "people",
                     "rly": "really", "noe": "know", "bcos": "because", "bcoz": "because", "coz": "because",
                     "wat": "what", "wht": "what", "hw": "how", "mins": "minutes", "min": "minutes",
                     "tq": "thank you", "thx": "thanks", "w": "with", "wif": "with", "dun": "don't",
                     "cnt": "can't", "nt": "not", "smtg": "something", "sth": "something", "bf": "before",
                     "lyk": "like", "gd": "good", "nite": "night", "tonite": "tonight", "pple": "people",
                     "ystd": "yesterday", "ytd": "yesterday", "msg": "message", "pic": "picture", "vid": "video",
                     # 3.80: "fasting mnth" was read as Malay "muntah" (vomiting)
                     "mnth": "month", "mth": "month", "mths": "months", "mnths": "months", "wk": "week",
                     "wks": "weeks", "yr": "year", "yrs": "years", "hrs": "hours", "hlp": "help", "hep": "help",
                     "lve": "love", "luv": "love", "cme": "come"}
# Malay as it is texted (3.59, the random typing test: "sya jatuh semalam", "xleh bangun", "jatuh td").
SHORT_WORDS_TYPED.update({
    "cot": "cost",                                   # 3.75: not "clot" (a blood clot is a condition now)
    "sya": "saya", "sy": "saya", "saa": "saya", "tk": "tak", "xleh": "tak boleh", "xblh": "tak boleh",
    "xboleh": "tak boleh", "xbole": "tak boleh", "xde": "tak ada", "xda": "tak ada", "xada": "tak ada",
    "xpe": "tak apa", "xpa": "tak apa", "xnak": "tak nak", "dgn": "dengan", "utk": "untuk", "yg": "yang",
    "sbb": "sebab", "sbab": "sebab", "skt": "sakit", "blh": "boleh", "bley": "boleh", "bleh": "boleh",
    "nk": "nak", "jgn": "jangan", "sgt": "sangat", "mcm": "macam", "kne": "kena", "dh": "dah", "lps": "lepas",
    "mkn": "makan", "tgk": "tengok", "bpe": "berapa", "brp": "berapa", "camne": "macam mana",
    "cmne": "macam mana", "cmana": "macam mana", "mcmana": "macam mana", "knp": "kenapa", "npe": "kenapa",
    "nape": "kenapa", "tgn": "tangan", "pg": "pagi", "ptg": "petang", "mlm": "malam", "smlm": "semalam",
    "td": "tadi", "tdi": "tadi", "skrg": "sekarang", "skrang": "sekarang", "skang": "sekarang", "ape": "apa",
    "lg": "lagi", "org": "orang", "sdh": "sudah", "blm": "belum", "bkn": "bukan", "mmg": "memang",
    "ckp": "cakap", "dpt": "dapat", "byk": "banyak", "kpd": "kepada", "drpd": "daripada", "tlg": "tolong",
    "tlong": "tolong", "dr": "doctor", "dktr": "doktor"})


@lru_cache
def rules() -> dict:
    return json.loads(RULES_PATH.read_text(encoding="utf-8"))


@lru_cache(maxsize=20000)
def clean(text: str) -> str:
    t = re.sub(r"(\d)\s*%", r"\1 percent ", text.lower().replace("’", "'"))
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
    camera = f"Recording: {ex['camera'][0].lower() + ex['camera'][1:]}." if ex.get("camera") else ""
    aliases = ex["aliases"]
    return {
        "key": f"exercise:{key}", "title": f"How to do {ex['name']}", "show": bool(in_plan), "priority": 6,
        "keywords": aliases,
        "examples": [f"how do I do the {aliases[0]}", f"{aliases[0]} instructions", f"how many {aliases[0]}"],
        "answer": _exercise_text(ex["name"], ex["instruction"], extra, camera),
        "follow_ups": [], "tailor": True, "time_aware": True,
        "action": {"key": "open_treatment", "label": "Open my treatment plan"} if in_plan else None,
    }


def _exercise_text(name: str, instruction: str, extra: str, camera: str) -> str:
    """The exercise on lines (3.66, Elwin's report "should display more neatly"): its name, each step as a
    point, then safety, the plan's targets and how to film it."""
    steps, safety = instruction, ""
    if "Safety:" in instruction:
        steps, safety = (s.strip() for s in instruction.split("Safety:", 1))
    points = [s.strip() for s in re.split(r"(?<=[.!])\s+", steps) if s.strip()]
    lines = [name] + [f"{k}) {p}" for k, p in enumerate(points, 1)]
    if safety:
        lines.append(f"Safety: {safety}")
    lines += [x.strip() for x in (extra, camera) if x.strip()]
    return "\n".join(lines)


def plan_intents(plan: dict) -> list[dict]:
    lines = "\n".join(f"{e['order']}) {e['name']}: {e['repetitions']} repetitions (about {e['duration']})"
                       for e in plan["exercises"])
    return [
        # Priority 3: "my plan" appears in many questions about other topics, which should win.
        {"key": "plan_exercises", "title": "What is in my plan", "show": True, "priority": 3,
         "keywords": ["plan", "what exercises", "which exercises", "exercises in my plan", "my plan", "in my plan",
                      "my exercises", "my exercise list", "exercises today", "today's exercises",
                      "this plan", "exercise list", "list of exercises", "what order", "which order", "first exercise",
                      "next exercise", "how many reps", "how many repetitions", "repetitions", "reps", "sets",
                      "every session", "each session", "all the exercises", "all exercises", "all three",
                      "comes first", "which first", "which one first", "order"],
         "examples": ["what exercises are in my plan", "which exercise do I do first", "how many repetitions",
                      "what is in this plan"],
         "answer": f"Your plan, {plan['plan_name']}, has {len(plan['exercises'])} exercises, done in this order:\n"
                   f"{lines}\nDo it {plan['frequency_per_week']} times a week.",
         "follow_ups": [], "tailor": True, "time_aware": True,
         "action": {"key": "open_treatment", "label": "Open my treatment plan"}},
        {"key": "plan_progress", "title": "Progress and results", "show": True, "priority": 6,
         "keywords": ["results", "see results", "progress", "improve", "improving", "improvement", "how long until",
                      "when will", "getting better", "get better", "is it working", "is this working", "it working",
                      "plan working", "exercise working", "exercises working", "working for me", "even working",
                      "really working", "actually working", "be stronger", "arms stronger", "legs stronger",
                      "get stronger", "finish the plan",
                      "finished the plan", "complete the plan", "after this plan", "next plan", "recover", "recovery",
                      "is it helping", "plan helping", "helping me", "help me recover", "effective", "worth it", "making a difference", "any difference",
                      "fix", "cure", "heal", "do for me", "purpose", "aim", "goal", "benefit", "benefits",
                      "plan for", "normally again", "back to normal", "normal again", "like before",
                      "get back to normal", "giving up", "give up", "no motivation", "not motivated",
                      "demotivated", "discouraged", "finished all", "completed all", "finish all", "done all",
                      "all done", "finished my plan", "completed my plan",
                      "why this plan", "what does this plan do", "what next", "what's next", "next step",
                      "better now", "feel better", "feeling better", "when can i stop", "can i stop now",
                      "when can stop", "when to stop", "when stop", "point of this exercise", "point of this plan",
                      "point of doing", "what is the point of", "what's the point of this",
                      "still need to continue", "need to continue", "continue or not", "better already",
                      "already better", "how long more", "walk normally", "walk again", "walk properly",
                      "how long before", "did all", "did all my", "done my exercises",
                      # 3.79: "it's been 2 weeks and no change"
                      "no change", "no improvement", "not improving", "not getting better", "still the same",
                      "same as before", "tak ada perubahan", "takde perubahan", "tiada perubahan"],
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
    items = [{**i, "answer": layout(i["answer"])} for i in plan_intents(plan)] if plan else []   # 3.68
    items += [exercise_intent(k, ex, plan) for k, ex in r["exercises"].items()]
    items += r["intents"]
    return tuple(items)


def intents_for(plan_id: str | None) -> list[dict]:
    return list(_intents_for(plan_id))


def categories_for(plan_id: str | None, restriction: str | None = None) -> list[dict]:
    """The question categories the app lists (FR500_18): plan topics first, then general ones. A
    restricted user (3.49: aged 65 and over) gets "Why plans stop at 65" first and no plan topics."""
    shown = [i for i in intents_for(plan_id) if i["show"]]
    rest = rules().get("restrictions", {}).get(restriction or "")
    if not rest:
        return shown
    first = [i for i in rules()["intents"] if i["key"] == "age_limit"]
    return first + [i for i in shown if not _restricted(i["key"], rest)]


def _restricted(key: str, rest: dict) -> bool:
    return key in rest["replace"] or key.startswith("plan_")


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
    # The free-word emergency rules' words too (round 15: "prevent", an exception there, was "corrected"
    # to "parent", so "how to prevent pain after a fall" read as an emergency).
    for combo in r.get("red_flag_combos", []):
        phrases += combo[0] + combo[1] + (combo[3] if len(combo) > 3 else [])
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
        if w not in vocab and len(w) >= 2 and not w.isdigit() and w not in dictionary():
            likely = _likeliest(w) if len(w) >= 4 else None
            if likely is not None:
                w = likely
            elif not (len(w) >= 4 and _near_known(w)):
                # Sorted: a tie must not depend on the set's order (it changes every run); a warning-sign
                # word first, "fell" before "fall" ("flwl").
                candidates = sorted((v for v in vocab if v[0] == w[0] and abs(len(v) - len(w)) <= 1), key=_tie_order)
                hit = process.extractOne(w, candidates, scorer=fuzz.ratio, score_cutoff=80) if candidates else None
                w = hit[0] if hit else w
        out.append(w)
    return " ".join(out)


# 3.55 (15 Oct, the 10 000-message random test): a slip inside a Malay word ("pittam", "bernfas") kept it
# from being translated, and joined words ("heartracing", "takboleh", "haspengsan") from being read.
# respell() runs on the message as typed: an unknown word becomes the closest English or Malay word
# the rules know (same first letter, at most one letter longer or shorter, 80 % alike), or is split
# into two known words. Common Malay words are known too, so "jauh" (far) never becomes "jatuh" (fall).
COMMON_MALAY = set("""ada adik ayah abang akan aku anak apa awak bagi baik balik banyak baru belum besar betul bila
boleh buat bulan cuba dah dalam dan dapat dari dekat depan dengan dia dua emak esok gerak hari hendak hidup ibu ini
itu jalan jangan jauh jumpa juga kakak kalau kami kan kat kata kecil keluar kena kerja kita kuat lagi lain lama
lambat laju lepas lebih lemah lima macam mahu main makan mak malam mana masa mati minggu minum mula mungkin naik
nanti nenek ni nak orang pagi pakai panas pergi petang pula pun rasa rumah sahaja saja sakit sama sampai sangat
satu saya sebab sedikit sejuk selalu semalam semua senang siapa sikit sini situ suami sudah susah tadi tahu tak
takut tangan tapi tengok terus tiga tidak tiap tolong tu tua turun ulang untuk wak yang
lah leh lor meh ah ya kot""".split())


@lru_cache(maxsize=1)
def dictionary() -> frozenset:
    """The most common English and Malay words (common_words.txt, build_wordlist.py): never respelled."""
    return frozenset((Path(__file__).with_name("common_words.txt")).read_text(encoding="utf-8").split())


@lru_cache(maxsize=1)
def rare_words() -> frozenset:
    """English words ranked 20 000-50 000 (rare_words.txt, build_wordlist.py): real words, so never turned
    into a warning-sign word ("pruning", "antifreeze"), though other corrections stay possible."""
    path = Path(__file__).with_name("rare_words.txt")
    return frozenset(path.read_text(encoding="utf-8").split()) if path.exists() else frozenset()


@lru_cache(maxsize=1)
def _respell_vocab() -> frozenset:
    v = set(vocabulary()) | COMMON_MALAY | set(MALAY) | set(SYNONYMS) | set(CONTRACTIONS)
    for p in MALAY_PHRASES:
        v.update(p.split())
    for p in rules()["red_flags"]:
        v.update(p.split())
    for p in rules().get("glossary", {}):                # posture mistake names (3.56)
        v.update(p.replace("_", " ").split())
    for p in rules().get("crisis", []):                  # thoughts of suicide (3.57: "anymore")
        v.update(p.split())
    v |= ADDRESS_WORDS | HEALTH_SENSE_WORDS
    return frozenset(w for w in v if w)


# 3.57: how Malaysians address someone ("boss how to start"), and health words the topics do not name:
# known words, so never "another domain".
ADDRESS_WORDS = frozenset({"boss", "bro", "brother", "sis", "sister", "uncle", "aunty", "auntie", "kak", "akak",
                           "encik", "cik", "puan", "tuan", "dato", "datin", "madam", "sir", "dear", "friend"})
HEALTH_SENSE_WORDS = frozenset({"hearing", "deaf", "eyesight", "vision", "blind", "glasses", "spectacles", "memory",
                                "forgetful", "dementia", "hearing aid", "cataract", "tinnitus"})


def _exact_split(w: str, vocab) -> list[str] | None:
    """Two known words typed without the space, the parts as even as possible; never "no" first, except
    "not" before a word of 4+ letters ("notspread")."""
    best = None
    for i in range(2, len(w) - 1):
        a, b = w[:i], w[i:]
        negator_ok = a not in NEGATORS or (a == "not" and len(b) >= 4)
        if a in vocab and b in vocab and negator_ok and min(len(a), len(b)) >= 2:
            if best is None or abs(len(a) - len(b)) < abs(len(best[0]) - len(best[1])):
                best = (a, b)
    return list(best) if best else None


def _split_joined(w: str, vocab: frozenset) -> list[str] | None:
    """"heartracing" -> heart racing; "takboleh" -> tak boleh (both parts known, the first not "no");
    "slurredspech" -> slurred speech (the second part with a slip of its own)."""
    best = None
    for i in range(2, len(w) - 1):
        a, b = w[:i], w[i:]
        if a in vocab and b in vocab and a not in NEGATORS and min(len(a), len(b)) >= 2:
            if best is None or abs(len(a) - len(b)) < abs(len(best[0]) - len(best[1])):
                best = (a, b)
    if best:
        return list(best)
    for i in range(2, len(w) - 2):
        a, b = w[:i], w[i:]
        if a in vocab and a not in NEGATORS and len(b) >= 3:
            fixed = _likeliest(b)
            if fixed and typo_cost(b, fixed) <= 0.8:
                return [a, fixed]
        if b in vocab and len(a) >= 3:                   # "pianduring" -> pain during
            fixed = _likeliest(a)
            if fixed and fixed not in NEGATORS and typo_cost(a, fixed) <= 0.8:
                return [fixed, b]
    return None


# Words of warning signs: a one-letter slip is corrected even in a short word ("dafa", "dda" -> dada).
SAFETY_WORDS = frozenset({"dada", "nafas", "bernafas", "pitam", "pengsan", "jatuh", "darah", "chest", "faint",
                          "fainted", "breath", "breathe", "bleed", "bleeding", "heart", "stroke", "collapse",
                          "collapsed", "dizzy", "pening", "pitam", "sesak", "ketat", "jantung", "kepala",
                          "numb", "kebas", "lumpuh", "senget", "pelat", "laju", "berdebar", "bangun", "weak",
                          "side", "fell", "fall", "susah", "muka", "tadi", "saya", "ayah", "hurt", "hurts",
                          "pain", "racing", "pounding", "terhantuk", "swollen", "vomit", "muntah", "sakit",
                          "hard", "head", "move", "talk", "speech", "drooping", "faint", "blood",
                          # thoughts of suicide, an overdose (3.55)
                          "suicide", "die", "dead", "death", "living", "live", "life", "kill", "killing",
                          "bunuh", "diri", "mati", "wake", "gone", "burden", "pills", "pill", "tablets",
                          "overdose", "end", "point", "anymore", "want", "wish", "better", "hurt", "harm",
                          "myself", "cut", "cutting", "poison", "bleach", "swallowed"})


# Keys next to each other on a phone keyboard (QWERTY rows): a slip onto one is the commonest typo.
_ROWS = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
KEY_NEIGHBOURS = {ch: set(r[max(0, i - 1):i]) | set(r[i + 1:i + 2]) for r in _ROWS for i, ch in enumerate(r)}


@lru_cache(maxsize=200000)
def typo_cost(typed: str, word: str) -> float:
    """How likely [typed] is a slip of [word]: an edit distance where a neighbouring key, a doubled letter
    and two swapped letters cost 0.5, any other change 1 (3.55). "psin" -> pain 0.5, pin 1."""
    n, m = len(typed), len(word)
    d = [[0.0] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        d[i][0] = float(i)
    for j in range(1, m + 1):
        d[0][j] = float(j)
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            a, b = typed[i - 1], word[j - 1]
            cost = d[i - 1][j - 1] + (0 if a == b else 0.5 if a in KEY_NEIGHBOURS.get(b, ()) else 1.0)
            cost = min(cost, d[i - 1][j] + (0.5 if i >= 2 and typed[i - 2] == a else 1.0),   # extra letter
                       d[i][j - 1] + 0.8)                     # dropped letter: the commonest slip ("ofen")
            if i > 1 and j > 1 and a == word[j - 2] and typed[i - 2] == b:
                cost = min(cost, d[i - 2][j - 2] + 0.5)                                     # swapped
            d[i][j] = cost
    return d[n][m]


# Words of an emergency: when a slip is (nearly) as likely to be one of these as a harmless word
# ("fel": fell or feel; "wrst": worst or wrist; "pased": passed or paused; "sakt": sakit or salt), the
# emergency word is read, since a needless safety answer is the safer mistake (3.55).
URGENT_WORDS = frozenset({"fell", "fall", "fallen", "falling", "jatuh", "pitam", "pengsan", "dada", "nafas",
                          "bernafas", "chest", "faint", "fainted", "breath", "breathe", "bleed", "bleeding",
                          "heart", "stroke", "collapse", "collapsed", "sakit", "die", "dead", "suicide", "kill",
                          "bunuh", "mati", "pills", "overdose", "poison", "blood", "darah", "worst", "passed",
                          "want", "wish", "live", "living", "hurts", "hurt", "wants", "diri", "muka", "pain"})
URGENT_MARGIN = 0.3
RARE_SLIP = 0.8          # a rarer real word is respelled only this close (3.60; 0.5 in 3.57-3.59)


def _tie_order(v: str) -> tuple:
    """Order for equally close words: warning-sign words first, "fell" first of them, then a to z."""
    return v not in URGENT_WORDS, v != "fell", v


def _closest(w: str, vocab, cutoff: float) -> str | None:
    cands = sorted((v for v in vocab if v[0] == w[0] and abs(len(v) - len(w)) <= 1 and len(v) >= 4), key=_tie_order)
    if 4 <= len(w) <= 6:
        # One swap, drop, extra or changed letter (OSA distance 1) when only one known word is that close.
        near = [v for v in cands if OSA.distance(w, v) <= 1]
        if len(near) == 1:
            return near[0]
    hit = process.extractOne(w, cands, scorer=fuzz.ratio, score_cutoff=cutoff) if cands else None
    return hit[0] if hit else None


FEELING_WORDS = {"lazy", "tired", "sakit", "pain", "sick", "unwell", "dizzy", "good", "bad", "better", "worse",
                 "weak", "ok", "okay", "fine", "sore", "sad", "happy", "so", "very", "really", "penat",
                 "pening", "sleepy", "cold", "hot", "lonely", "stressed", "great", "nothing", "like",
                 "hopeless", "useless", "anxious", "angry", "upset", "bored", "frustrated", "scared", "afraid",
                 "nervous", "worried", "empty"}


@lru_cache(maxsize=20000)
def respell(text: str) -> str:
    """The message with its unknown words mended, in lower case, punctuation kept."""
    low = text.lower().replace("’", "'")
    parts = re.split(r"([a-z0-9']+)", low)
    typed = parts[1::2]
    mended = _malay_two(typed, [_respell_words(w) for w in typed])
    for k, (was, now) in enumerate(zip(typed, mended)):
        # A slip read as fell/fall before a feeling word was "feel" ("fel lazy today", "fel sakit"):
        # only that word, and only when it was not typed as fell/fall.
        if now in ("fell", "fall") and was not in ("fell", "fall") and k + 1 < len(mended) \
                and mended[k + 1] in FEELING_WORDS:
            mended[k] = "feel"
    # 3.59: an unknown or rarer word within three words of a symptom is read as a symptom word one slip
    # away ("chet pain", "herat pounding", "dada skit", "chest pina", "leer kersa dan demam"); alone it
    # is not ("pruning", "chet" stay as typed).
    near = [set(m.split()) for m in mended]
    known = vocabulary()
    for k, was in enumerate(typed):
        before = [m for m in mended[max(0, k - 2):k]]
        if before and (before[-1] in CHEST_WORDS or (len(before) == 2 and before[0] in CHEST_WORDS
                                                     and before[1] in ("very", "so", "is", "rasa", "feels", "feel",
                                                                       "really", "sangat", "macam"))):
            chest = _chest_reading(was)
            if chest:
                mended[k] = chest                        # "chest very tijt": tight (3.84)
                continue
        sign = _sign_reading(was)
        if not sign or near[k] & SIGN_WORDS:
            continue
        # A closer word of the rules wins ("frint arm raise" is front), but not over the symptom word's own
        # letters scrambled ("chest pina" is pain, not "pins" of pins and needles, 3.78).
        if mended[k] in known and typo_cost(was, mended[k]) < typo_cost(was, sign) and sorted(was) != sorted(sign):
            continue
        if any(near[j] & SIGN_CONTEXT for j in range(max(0, k - 3), min(len(typed), k + 4)) if j != k):
            mended[k] = sign
    parts[1::2] = mended
    return "".join(parts)


# Symptoms and the body parts they are felt in (3.59), narrower than SAFETY_WORDS.
SIGN_WORDS = frozenset({"chest", "dada", "heart", "jantung", "pain", "sakit", "nafas", "bernafas", "breath",
                        "breathe", "pitam", "pengsan", "faint", "fainted", "dizzy", "pening", "numb", "kebas",
                        "bleeding", "darah", "blood", "fell", "fall", "jatuh", "pounding", "racing", "berdebar",
                        "tightness", "ketat", "sesak", "leher", "neck", "stiff", "keras", "demam", "fever", "vomit",
                        "muntah", "swollen", "weak", "lumpuh", "stroke", "collapse", "collapsed", "hurts",
                        "hurt", "sore", "aches"})
# 3.60: and the body part it is felt in ("my knee huts" -> hurts; "it huts" stays as typed).
SIGN_CONTEXT = SIGN_WORDS | {"hurting", "ache", "aching", "tight", "beating", "fast", "laju", "sudden", "pressure",
                             "suddenly", "knee", "knees", "back", "hip", "hips", "shoulder", "shoulders", "leg",
                             "legs", "arm", "arms", "ankle", "foot", "feet", "wrist", "elbow", "lutut", "kaki",
                             "tangan", "pinggang", "bahu", "belakang", "pinggul", "buku"}


@lru_cache(maxsize=20000)
def _sign_reading(w: str) -> str | None:
    """The symptom word one slip from an unknown or rarer word (same first letter), if any."""
    if len(w) < 3 or not w.isalpha() or w in SIGN_WORDS or w in _respell_vocab() or w in dictionary():
        return None
    scored = sorted((typo_cost(w, v), _tie_order(v)) for v in SIGN_WORDS
                    if v[0] == w[0] and abs(len(v) - len(w)) <= 1)
    if scored and scored[0][0] <= 1.0:
        return scored[0][1][2]
    # The same letters in another order ("pina" -> pain, 3.62).
    same = sorted(v for v in SIGN_WORDS if len(w) >= 4 and v[0] == w[0] and sorted(v) == sorted(w))
    return same[0] if same else None


# 3.84: beside "chest", "dada" or "heart" a symptom is near certain, so a word two slips from one of these is
# read as it ("chest very tijt" was "tilt", "chest piian" the Malay "puan").
CHEST_WORDS = {"chest", "dada", "heart", "jantung"}
CHEST_SIGNS = ("pain", "pains", "tight", "sakit", "ketat", "sesak", "berdebar")


@lru_cache(maxsize=5000)
def _chest_reading(w: str) -> str | None:
    if len(w) < 3 or not w.isalpha() or w in dictionary() or w in CHEST_SIGNS or w in _respell_vocab():
        return None                                      # a known word is what was typed ("dada senak")
    scored = sorted((typo_cost(w, v), v) for v in CHEST_SIGNS if v[0] == w[0] and abs(len(v) - len(w)) <= 1)
    return scored[0][1] if scored and scored[0][0] <= 2.0 else None


# 3.64 (the Malay texting test, chat_malay_texting_set.py: 58 % right, warning signs 50 %): Malay is
# often texted without its vowels ("sy jth semalam", "ssk nfs", "pnt hidup", "kaki saya lmh").
MALAY_SIGN_WORDS = {"dada", "nafas", "bernafas", "pitam", "pengsan", "jatuh", "darah", "sesak", "ketat", "jantung",
                    "kepala", "kebas", "lumpuh", "senget", "pelat", "laju", "berdebar", "bangun", "susah", "muka",
                    "tadi", "saya", "ayah", "sakit", "muntah", "terhantuk", "lemah", "pening", "bengkak", "leher",
                    "keras", "demam", "mati", "bunuh", "diri", "hidup", "penat", "takut", "keluar", "banyak",
                    "tinggi", "senaman", "bersenam", "lutut", "kaki", "tangan", "bahu", "belakang", "pinggang",
                    "tukar", "peringatan", "lambat", "terima", "kasih", "murung", "sedih", "emak"}
# Short forms in English that have no vowel either: never read as Malay.
ENGLISH_NO_VOWEL = {"pls", "plz", "thx", "msg", "hmm", "brb", "btw", "idk", "tbh", "omg", "lol", "nth", "ppl",
                    "mrs", "hrs", "kms", "kgs", "cms", "mls", "sms", "gps", "cpr", "ecg", "ekg", "mri", "bmi", "bpm",
                    "rpm", "xls", "pdf", "jpg", "png", "mp", "tv", "pc", "dr", "mr", "ms", "bp", "cm", "kg", "km",
                    "mm", "ml", "hr", "st", "nd", "rd", "th", "ty", "np", "bf", "gf", "hb", "hm", "sth", "smth",
                    "smtg", "wnt", "hw", "wht", "cnt", "dnt", "nvm", "pwd", "pw", "tmr", "tdy", "ytd", "bcz"}
NO_VOWEL_RE = re.compile(r"[aeiou]")


def _skeleton(w: str) -> str:
    """The first letter and the consonants after it ("sakit" -> "skt", "emak" -> "emk")."""
    return w[0] + NO_VOWEL_RE.sub("", w[1:])


@lru_cache(maxsize=1)
def _malay_by_skeleton() -> dict:
    """{skeleton of 3+ letters: the one Malay word it can be}; when several, the warning-sign word if
    exactly one is ("skt": sakit, not sikit)."""
    words = set(COMMON_MALAY) | set(MALAY) | MALAY_SIGN_WORDS | {w for p in MALAY_PHRASES for w in p.split()}
    by: dict[str, set] = {}
    for w in words:
        if len(w) >= 3 and w.isalpha() and NO_VOWEL_RE.search(w[1:]):
            by.setdefault(_skeleton(w), set()).add(w)
    out = {}
    for s, ws in by.items():
        if len(s) < 3:
            continue
        signs = ws & (URGENT_WORDS | MALAY_SIGN_WORDS) if len(ws) > 1 else ws
        if len(ws) == 1 or len(signs) == 1:
            out[s] = sorted(signs)[0]
    return out


# Two-letter Malay short forms, read only in a message with other Malay in it ("dd skt", "saya nak mt").
# Not "dr" (doctor, except in "bunuh dr"), "kl" (Kuala Lumpur), "mk" (muka or mak).
MALAY_TWO = {"dd": "dada", "mt": "mati", "rs": "rasa", "kk": "kaki", "br": "baru", "jg": "juga", "bg": "bagi",
             "sm": "sama", "ms": "masa", "lj": "laju", "lp": "lupa", "jt": "jatuh", "ml": "mula"}
# Two short forms that only make sense together ("mk sngt": muka senget, the face drooping).
MALAY_PAIRS = {("mk", "sngt"): ("muka", "senget"), ("mk", "senget"): ("muka", "senget"),
               ("mk", "snget"): ("muka", "senget"), ("kt", "lln"): ("kata", "laluan"),
               ("kt", "laluan"): ("kata", "laluan"), ("kata", "lln"): ("kata", "laluan"),
               ("trm", "khs"): ("terima", "kasih"), ("trm", "ksh"): ("terima", "kasih"),
               ("terima", "khs"): ("terima", "kasih"), ("terima", "ksh"): ("terima", "kasih")}
# 3.83: "lah" typed as "lha" or "lsh" ("pitamlha", "ddlsh"), split off like "lah"; 3.92: "alh", "lh", and the
# question particle "kah" ("tkt jthalh", "kata laluanlh", "tkr kt llnkah").
PARTICLE_ENDINGS = ("lah", "lha", "lsh", "alh", "kah", "lh")


def _without_particle(w: str) -> str:
    for s in PARTICLE_ENDINGS:
        if w.endswith(s) and len(w) > len(s):
            return w[:-len(s)]
    return w


def _malay_two(typed: list[str], mended: list[str]) -> list[str]:
    malay = set(COMMON_MALAY) | set(MALAY) | MALAY_SIGN_WORDS | {w for p in MALAY_PHRASES for w in p.split()}
    if not any(x in malay for m in mended for x in m.split()) \
            and not any(_without_particle(w) in malay for w in typed):           # "pitamlha" alone (3.83)
        return mended
    out = list(mended)
    bare = [_without_particle(w) for w in typed]          # "mtlah", "drlah", "pglah", "pitamlha"
    for k, w in enumerate(bare):
        as_typed = typed[k]
        nxt = bare[k + 1] if k + 1 < len(bare) else ""
        mended_nxt = mended[k + 1] if k + 1 < len(mended) else ""
        if (w, nxt) in MALAY_PAIRS or (w, mended_nxt) in MALAY_PAIRS:
            out[k], out[k + 1] = MALAY_PAIRS.get((w, nxt)) or MALAY_PAIRS[(w, mended_nxt)]
            continue                                     # (3.83: also with the next word's slip mended: "mk sneget")
        if k and ((bare[k - 1], w) in MALAY_PAIRS or (bare[k - 1], mended[k]) in MALAY_PAIRS):
            continue
        if w == "dr" and k and (bare[k - 1] in ("bunuh", "bnh") or out[k - 1] == "bunuh"):
            out[k] = "diri"                              # "bunuh drlah": suicide (3.83: before "dr" = doctor)
            continue
        if w == "mat" and k and bare[k - 1] in ("nk", "nak") and (as_typed != w or k == len(bare) - 1):
            out[k] = "mati"                              # "saya nk matlah" (3.83), not "nak mat yoga"
            continue
        if w == "x" and nxt.isalpha() and not (k and bare[k - 1].isdigit()):
            out[k] = "tak"                               # "x boleh", "x nak": tak (3.64)
            continue
        if w != as_typed and w in SHORT_WORDS_TYPED:
            out[k] = SHORT_WORDS_TYPED[w]                # "pglah", "lglah"
            continue
        if w.startswith("x") and len(w) >= 3 and mended[k] == as_typed:
            likely = _likeliest(w[1:]) if len(w) >= 5 else None                 # "xbokeh": tak boleh (3.83)
            rest = SHORT_WORDS_TYPED.get(w[1:]) or MALAY_TWO.get(w[1:]) or _malay_texted(w[1:]) or (
                w[1:] if w[1:] in COMMON_MALAY or w[1:] in MALAY_SIGN_WORDS else None) or (
                likely if likely in COMMON_MALAY or likely in MALAY_SIGN_WORDS else None)
            if rest:
                out[k] = "tak " + rest                   # "xnk", "xbole", "xbngn"
                continue
        if w in MALAY_TWO and (mended[k] == as_typed or w != as_typed):     # (3.83: "ljlah" is laju lah)
            nxt = typed[k + 1] if k + 1 < len(typed) else ""
            if (w == "ms" and nxt in ("", "pain", "sakit")) or (w == "ml" and k and bare[k - 1].isdigit()):
                out[k] = w                               # "i have ms": MS; "500 ml"
            else:
                out[k] = MALAY_TWO[w]
        elif w != as_typed and as_typed not in dictionary() and as_typed not in COMMON_MALAY:
            # "lah" split off a word ("pitamlha", 3.83), also with a slip in it ("kelluarlah": keluar, 3.84)
            known = set(COMMON_MALAY) | MALAY_SIGN_WORDS | SAFETY_WORDS | set(MALAY)
            once = re.sub(r"(.)\1+", r"\1", w)
            r = (w if w in known else _malay_texted(w) or _malay_texted(once)
                 or (_likeliest(w) if len(w) >= 4 else None))    # (3.92: "khslah" kasih, "jthhlah" jatuh)
            if r in known:
                out[k] = r
        elif w == as_typed and len(w) >= 5 and w.endswith("ah") and mended[k] == as_typed \
                and _malay_texted(w[:-2]) in MALAY_SIGN_WORDS:
            out[k] = _malay_texted(w[:-2])               # "ptmah": pitam ah (3.83)
    for k in range(len(out) - 1):                        # a pair seen once its second word is mended (3.92:
        if (bare[k], out[k + 1]) in MALAY_PAIRS:         # "mk swngetlah": muka senget)
            out[k], out[k + 1] = MALAY_PAIRS[(bare[k], out[k + 1])]
    return out


def _malay_texted(w: str) -> str | None:
    """The Malay word a vowel-less word of 3+ letters was texted for, if there is just one."""
    if len(w) < 3 or not w.isalpha() or NO_VOWEL_RE.search(w[1:]) or w in ENGLISH_NO_VOWEL or w in _respell_vocab():
        return None
    return _malay_by_skeleton().get(w)


def _respell_part(w: str) -> str | None:
    """One part of a joined word: known, or the likeliest known word."""
    vocab = _respell_vocab()
    if w in vocab or w in dictionary():
        return w
    return _likeliest(w)


def _respell_words(token: str) -> str:
    vocab = _respell_vocab()
    out = []
    for w in [token]:
        if w in SHORT_WORDS_TYPED:
            out.append(SHORT_WORDS_TYPED[w])
            continue
        texted = _malay_texted(w[:-3] if len(w) > 5 and w[-3:] == "lah" else w)
        if texted:
            out.append(texted)                           # "jth" -> jatuh, "sktlah" -> sakit (3.64)
            continue
        if len(w) > 5 and w[-3:] in ("lah", "kah") and (w[:-3] in vocab or w[:-3] in COMMON_MALAY
                                                       or w[:-3] in SAFETY_WORDS):
            out.append(w[:-3])                           # "bangunlah" -> bangun; "bolehkah" -> boleh (3.59)
            continue
        if w in vocab or w in dictionary() or len(w) < 3 or not w.replace("'", "").isalpha():
            out.append(w)                                # a known or a real word is what was typed
            continue
        if len(w) >= 4 and w[-1] == w[-2] and (w[:-1] in FEELING_WORDS or w[:-1] in SAFETY_WORDS)                 and not any(OSA.distance(w, u) <= 1 for u in URGENT_WORDS if u != w[:-1]):
            out.append(w[:-1])                           # "sadd", "painn" (3.90); not "feell": fell is as near
            continue
        likely = _likeliest(w)
        easy = likely is not None and typo_cost(w, likely) <= 0.8
        exact = _exact_split(w, vocab)
        if exact and not easy:
            out.extend(exact)                            # "beenthe" -> been the, not "breathe"
            continue
        rest = _joined_rest(w, vocab) if not easy else None
        if rest is not None:
            out.extend([w[0], rest])                     # "ifell" -> i fell; "isee" -> i see; "abit"
            continue
        if "'" in w:                                     # "suddenlycan't" -> suddenly can't
            head, tail = w.split("'", 1)
            for k in range(3, len(head) - 1):
                if head[:k] in vocab and head[k:] + "'" + tail in vocab:
                    out.extend([head[:k], head[k:] + "'" + tail])
                    break
            else:
                for k in range(1, len(tail) - 2):        # "can'tbreathe" -> can't breathe
                    if head + "'" + tail[:k] in vocab and tail[k:] in vocab:
                        out.extend([head + "'" + tail[:k], tail[k:]])
                        break
                else:
                    out.append(w)
            continue
        if len(w) == 3:                                  # "dda" -> dada; "wek" stays (week or weak)
            out.append(_three_letters(w) or w)
            continue
        # The known word the slip most likely came from (typo_cost); on a tie a warning-sign word ("heatr":
        # heart, not heat; "ptaam": pitam, not padam), since a needless safety answer is the safer
        # mistake. Then the older 80 %-alike rule; only then two joined words ("herat" is heart, not
        # "her at").
        fixed = _likeliest(w)
        if fixed is None and not _near_known(w) and len(w) >= 7:
            fixed = _closest(w, SAFETY_WORDS, 80) or _closest(w, vocab, 80)
        if fixed:
            out.append(fixed)
            continue
        joined = _split_joined(w, vocab)
        if joined:
            out.extend(joined)
            continue
        out.append(_closest(w, SAFETY_WORDS, 74) or w)
    return " ".join(out)


@lru_cache(maxsize=1)
def _dictionary_by_letter() -> dict:
    out: dict[str, list[str]] = {}
    for w in dictionary():
        out.setdefault(w[0], []).append(w)
    return out


@lru_cache(maxsize=1)
def _word_use() -> dict:
    """How often each word appears in the rules' keywords, example questions and warning signs."""
    count: dict[str, int] = {}
    phrases = list(rules()["red_flags"]) + [p for i in rules()["intents"] for p in i["keywords"] + i["examples"]]
    phrases += [p.replace("_", " ") for p in rules().get("glossary", {})]
    for p in phrases:
        for w in clean(p).split():
            count[w] = count.get(w, 0) + 1
    return count


@lru_cache(maxsize=20000)
def _likeliest(w: str) -> str | None:
    vocab = _respell_vocab() | SAFETY_WORDS
    limit = 1.0 if len(w) < 7 else 1.5
    spread = 1 if len(w) < 6 else 2
    cands = {v for v in vocab if v[0] == w[0] and abs(len(v) - len(w)) <= spread and len(v) >= 4}
    words = {v for v in _dictionary_by_letter().get(w[0], ()) if abs(len(v) - len(w)) <= spread and len(v) >= 4}
    scrambled = sorted(v for v in cands & SAFETY_WORDS if len(w) >= 4 and sorted(v) == sorted(w))
    if scrambled and w not in rare_words():
        return scrambled[0]                              # "skiat": sakit, not "sikat" (3.86)
    scored = sorted((typo_cost(w, v), v not in SAFETY_WORDS, v) for v in cands)
    # Two slips in a warning-sign word ("ptsm", "piam" -> pitam), when all but one of the typed letters
    # are in it in order ("psum" is not "pain"); never from a real but rarer word.
    two_slips = [] if len(w) < 4 or w in rare_words() else [
        s for s in scored if not s[1] and s[0] <= 1.5 and _in_order(w, s[2]) >= len(w) - 1]
    if w in rare_words():
        # A real but rarer word: never a warning sign (unless beside one: respell, 3.59), and only one
        # slip of another word ("hurst", "huts" -> hurts; "flor" -> floor; "pruning" is not "purging").
        scored = [s for s in scored if s[1] and s[0] <= RARE_SLIP]
    scored = [s for s in scored if s[1] or s[0] <= 1.0]  # warning-sign words: one slip at most here
    best_known = scored[0][0] if scored else 9.0
    extra = sorted((typo_cost(w, v), True, v) for v in words - cands)
    # Nearly as likely as the likeliest reading of all (the rules' words and common words alike):
    # "psun" is pain (not paun), but "paln" stays plan, "passwrd" password, "wamr" warm.
    overall = min(best_known, extra[0][0] if extra else 9.0)
    urgent_first = [s for s in scored if s[2] in URGENT_WORDS and s[0] <= min(limit, overall + URGENT_MARGIN)]
    if urgent_first:
        return min(urgent_first, key=lambda s: (s[0], s[2] != "fell", -_word_use().get(s[2], 0)))[2]
    if extra and extra[0][0] <= best_known - 0.5 and extra[0][0] <= 0.8:
        # A common word fits clearly better (by half a slip) than any of the rules' words ("meaming" ->
        # meaning); otherwise the rules' word ("sqat" is squat, not swat).
        if len(extra) == 1 or extra[1][0] > extra[0][0]:
            return extra[0][2]
    if not scored or scored[0][0] > limit:
        return two_slips[0][2] if two_slips else None
    urgent = [s for s in scored if s[2] in URGENT_WORDS and s[0] <= min(limit, scored[0][0] + URGENT_MARGIN)]
    if urgent:
        return min(urgent, key=lambda s: (s[0], s[2] != "fell", -_word_use().get(s[2], 0)))[2]
    best = [s for s in scored if s[0] == scored[0][0]]
    if len(best) > 1 and best[0][1]:                     # the top ones are all harmless words:
        use = _word_use()                                # the one the rules use most ("plan", not "palm")
        best.sort(key=lambda s: -use.get(s[2], 0))
        if use.get(best[0][2], 0) == use.get(best[1][2], 0):
            return None                                  # still equally likely: leave it
    return best[0][2]


def _three_letters(w: str) -> str | None:
    vocab = _respell_vocab() | SAFETY_WORDS
    scored = sorted((typo_cost(w, v), v not in SAFETY_WORDS, v) for v in vocab
                    if v[0] == w[0] and len(v) == 4)
    if not scored or scored[0][0] > 1.0:
        return None
    urgent = [s for s in scored if s[2] in URGENT_WORDS and s[0] <= min(1.0, scored[0][0] + URGENT_MARGIN)]
    if urgent:                                           # "fel" -> fell, "fll" -> fell, "wnt" -> want
        return min(urgent, key=lambda s: (s[0], s[2] != "fell", -_word_use().get(s[2], 0)))[2]
    if len(scored) > 1 and scored[1][0] == scored[0][0]:
        return None
    return scored[0][2] if (not scored[0][1] or scored[0][0] <= 0.5) else None


def _near_known(w: str) -> bool:
    """A known word within one slip: the word is then left alone rather than guessed loosely."""
    vocab = _respell_vocab()
    return any(typo_cost(w, v) <= 1.0 for v in vocab if v[0] == w[0] and abs(len(v) - len(w)) <= 1 and len(v) >= 4)


def _in_order(a: str, b: str) -> int:
    """Letters of [a] found in [b] in the same order (longest common subsequence)."""
    prev = [0] * (len(b) + 1)
    for x in a:
        cur = [0]
        for j, y in enumerate(b):
            cur.append(prev[j] + 1 if x == y else max(prev[j + 1], cur[j]))
        prev = cur
    return prev[-1]


def _joined_rest(w: str, vocab) -> str | None:
    """"ifell" -> fell, "abit" -> bit: "i" or "a" typed onto a known word (with at most one easy slip
    after "i"); never a "no" word."""
    rest = w[1:]
    if w[0] not in "ia" or len(w) < 4 or len(rest) < 3 or rest in NEGATORS:
        return None
    if rest in vocab or rest in dictionary():
        return rest
    if w[0] == "i":
        fix = _likeliest(rest)
        if fix and typo_cost(rest, fix) <= 0.5 and fix not in NEGATORS:
            return fix
    return None


def _plain(text: str) -> str:
    return " ".join(re.sub(r"[^a-z0-9' ]", " ", text.lower().replace("’", "'")).split())


def content_words(text: str) -> str:
    return " ".join(w for w in correct(text).split() if w not in STOP)


# 3.76: words whose stem means something else ("fasting" is not "walk fast", "travelling" not "how far the
# knee travels", "raining" not "rain forest").
STEM_KEPT = {"fasting", "travelling", "traveling", "raining"}


@lru_cache(maxsize=8192)
def stem(w: str) -> str:
    """Crude suffix stripping so burn / burns / burning and raise / raises / raising compare equal.
    The same function is applied to the rules and the question, so only consistency matters."""
    if len(w) <= 3 or "'" in w or w in STEM_KEPT:
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


NEGATION_FILLER = {"have", "has", "had", "got", "any", "feel", "felt", "get", "really", "much", "chest", "knee",
                   "back", "leg", "legs", "arm", "arms", "hip", "shoulder", "real", "a"}


def negated(words: list[str], i: int) -> bool:
    """A negator in the two words before position i ('no chest pain', 'not dizzy'), or further back
    across filler words ('i don't have chest pain', 'i do not have any pain')."""
    if NEGATORS & set(words[max(0, i - 2):i]):
        return True
    k = i - 1
    while k >= 0 and i - k <= 4 and words[k] in NEGATION_FILLER:
        k -= 1
    return k >= 0 and i - k <= 4 and words[k] in NEGATORS


COMBO_NEGATORS = NEGATORS - {"can't", "cant", "cannot"}


def _combo_negated(words: list[str], i: int) -> bool:
    """A negator in the two words before position i ("no chest pain", "no fever"), but not "not just" /
    "not only" (more, not less: "not just tight, it is crushing") nor an answer word before the person's
    own words ("No, my chest really hurts"; PC check, 9 Oct)."""
    before = words[max(0, i - 2):i]
    if not (COMBO_NEGATORS | {"doesn't", "doesnt", "aren't", "arent", "hasn't", "hasnt"}) & set(before):
        return False
    if len(before) == 2 and before[0] == "not" and before[1] in ("just", "only"):
        return False
    if len(before) == 2 and before[0] == "no" and before[1] in ("my", "his", "her", "the", "our"):
        return False
    return True

# When both rules match, the first answers the actual question better than the second
# ("i have diabetes, what time is best" is about timing; the diabetes timing note is added).
ASKING_FOR_DIAGNOSIS = ["is it a", "is it an", "is this a", "is this an", "could it be", "do i have", "might be",
                        "maybe", "how do i know", "what is wrong", "should i see"]
DOCTOR_SAID_TO = ["rest", "not to", "no exercise", "stop", "avoid", "don't", "dont", "do not", "should not",
                  "shouldn't", "cannot", "can't", "only", "pause", "jangan", "tak boleh", "bed"]
PREFER = [# 3.91: sleeping badly is not the best time to exercise; "how much protein" is not the app's price.
          ("sleep", "tired"), ("diet", "app_facts"), ("difficulty", "how_often"),
          ("low_mood", "bot_identity"),
          # 3.86: "fever today, exercise?" is about the fever, not today's exercise.
          ("tired", "treatment_nav"),
          # 3.79: a tablet computer is not a pill; "contact support" is not holding on to a support.
          ("app_facts", "medication"), ("app_facts", "safety"),
          # 3.78: the kind of symptom over the general pain answer.
          ("cramp", "pain_or_discomfort"), ("cramp", "pain_mild"), ("cramp", "tired"), ("cramp", "weakness_balance"),
          ("pins_needles", "pain_or_discomfort"), ("pins_needles", "tired"), ("pins_needles", "weakness_balance"),
          ("stiffness", "pain_or_discomfort"), ("stiffness", "pain_mild"), ("neck_not_covered", "stiffness"),
          ("stitch", "pain_or_discomfort"), ("stitch", "pain_sharp"), ("muscle_strain", "pain_or_discomfort"),
          ("muscle_strain", "diagnosis"), ("muscle_strain", "pain_sharp"), ("joint_noise", "pain_or_discomfort"),
          ("condition_advice", "stiffness"),
          # 3.76: a situation named ("haze", "puasa", "my period", "after my operation") over a general topic.
          ("haze", "pain_sharp"), ("haze", "pain_or_discomfort"), ("haze", "equipment"), ("haze", "other_activity"),
          ("haze", "hot_weather"), ("fasting", "best_time"), ("fasting", "diet"), ("fasting", "eating_concern"),
          ("weather", "tired"), ("weather", "equipment"), ("weather", "best_time"), ("travel", "missed_session"),
          ("travel", "plan_and_reminders"), ("travel", "equipment"), ("travel", "plan_progress"),
          ("travel", "plan_exercises"), ("fasting", "missed_session"), ("surgery", "diagnosis"), ("surgery", "safety"),
          ("surgery", "plan_progress"), ("surgery", "treatment_nav"), ("condition_advice", "surgery"),
          ("period", "pain_or_discomfort"), ("period", "pain_mild"), ("period", "pain_sharp"), ("period", "tired"),
          ("period", "diet"), ("alcohol_smoking", "diet"), ("alcohol_smoking", "tired"), ("after_treatment", "diet"),
          ("after_treatment", "condition_advice"), ("after_treatment", "muscle_loss"), ("after_treatment", "tired"),
          ("after_treatment", "pain_or_discomfort"),
          # 3.74: "how many calories did i burn" is not burning pain; "hot temperature outside" is the weather.
          ("calories", "pain_or_discomfort"), ("calories", "equipment"),
          ("hot_weather", "health_readings"), ("tired", "health_readings"), ("calories", "posture_result"),
          ("calories", "plan_progress"),
          # 3.67: "send message to my son", "order food for me" are things the chatbot cannot do.
          ("cannot_do", "for_someone_else"), ("cannot_do", "diet"), ("cannot_do", "family_help"),
          ("app_problem", "app_help"), ("app_problem", "recording_help"),
          ("greeting", "thanks"), ("other_activity", "reminders_help"),
          # 3.66 (Elwin's reports): "i m ur father" is said to the bot; "meds" are medicines; "you are useless"
          # is about the answer.
          ("bot_identity", "for_someone_else"), ("report_answer", "low_mood"),
          ("condition_advice", "pain_mild"), ("recording_help", "app_help"), ("plan_progress", "how_often"), ("for_someone_else", "posture_result"), ("weakness_balance", "equipment"), ("video_quality", "posture_result"),
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
          ("recording_help", "fear_of_falling"), ("missed_session", "muscle_loss"),
          ("eating_concern", "missed_session"), ("eating_concern", "diet"), ("eating_concern", "best_time"),
          ("eating_concern", "tired"), ("eating_concern", "motivation"), ("eating_concern", "difficulty"),
          ("eating_concern", "low_mood"), ("eating_concern", "medication"), ("bladder_leak", "difficulty"),
          ("bladder_leak", "pain_or_discomfort"),
          # round 15 (9 Oct features): the neck is not covered, whatever is asked about it; several plans
          ("neck_not_covered", "pain_or_discomfort"), ("neck_not_covered", "pain_mild"),
          ("neck_not_covered", "condition_advice"), ("neck_not_covered", "plan_exercises"),
          ("neck_not_covered", "how_to"), ("neck_not_covered", "getting_started"), ("neck_not_covered", "body_map"),
          ("multiple_plans", "plan_exercises"), ("multiple_plans", "plan_and_reminders"),
          ("multiple_plans", "plan_progress"), ("body_map", "plan_exercises"), ("body_map", "getting_started"),
          ("wrong_exercise", "posture_result"), ("wrong_exercise", "how_to"), ("wrong_exercise", "difficulty"),
          # round 16 (account and Exit, 9 Oct): "every time" in "log in every time" is not about pain
          ("session_expired", "pain_sharp"), ("exit_exercise", "difficulty"), ("exit_exercise", "plan_and_reminders"),
          ("exit_exercise", "history_help"), ("exit_exercise", "recording_help"), ("exit_exercise", "posture_result"),
          ("google_setup", "account_help"), ("change_password", "account_help"), ("session_expired", "account_help"),
          ("wrong_exercise", "recording_help"),
          # round 18 (3.51, 14 Oct): privacy, deleting, terms, under 18, a doctor's OK, reporting an answer
          ("privacy_data", "account_help"), ("privacy_data", "recording_help"), ("privacy_data", "video_quality"),
          ("delete_account", "account_help"), ("delete_account", "privacy_data"), ("terms_help", "account_help"),
          ("terms_help", "condition_advice"), ("terms_help", "privacy_data"), ("guardian_consent", "app_help"),
          ("guardian_consent", "for_someone_else"), ("guardian_consent", "profile_help"),
          ("guardian_consent", "posture_result"), ("guardian_consent", "terms_help"),
          ("doctor_clearance", "age_limit"), ("doctor_clearance", "condition_advice"),
          ("doctor_clearance", "doctor_said"), ("doctor_clearance", "getting_started"),
          # round 19 (3.52): app features
          ("plan_reasons", "plan_exercises"), ("plan_reasons", "multiple_plans"), ("plan_reasons", "posture_result"),
          ("plan_reasons", "safety"), ("risk_level", "profile_help"), ("risk_level", "safety"),
          ("safety_limits", "safety"), ("safety_limits", "how_often"), ("safety_limits", "profile_help"),
          ("planning_questions", "plan_progress"), ("planning_questions", "body_map"),
          ("planning_questions", "difficulty"), ("guide_animation", "body_map"), ("guide_animation", "how_to"),
          ("guide_animation", "app_help"), ("health_connect", "app_help"), ("health_connect", "profile_help"),
          ("app_facts", "app_help"), ("app_facts", "plan_progress"), ("app_facts", "bot_identity"),
          ("app_facts", "account_help"), ("guardian_consent", "app_facts"),
          ("posture_result", "plan_exercises"), ("plan_and_reminders", "plan_exercises"),
          ("best_time", "diet"), ("medication", "condition_advice"), ("tired", "diagnosis"),
          # 3.55 (random test): the specific answer over the general one
          ("fall_alert", "safety"), ("exit_exercise", "goodbye"), ("exit_exercise", "app_help"),
          ("app_facts", "safety"), ("motivation", "plan_progress"),
          ("partial_reps", "posture_result"), ("partial_reps", "plan_exercises"),
          ("treatment_nav", "plan_exercises"), ("video_quality", "recording_help"),
          ("plan_reasons", "plan_progress"), ("family_help", "for_someone_else"),
          ("family_help", "bot_identity"), ("muscle_loss", "weakness_balance"), ("bladder_leak", "pain_mild"),
          ("bladder_leak", "pain_or_discomfort"), ("plan_and_reminders", "plan_exercises"),
          ("plan_and_reminders", "pain_or_discomfort"), ("google_setup", "account_help"),
          ("app_help", "condition_advice"), ("fear_of_falling", "pain_or_discomfort"),
          ("privacy_data", "how_often"), ("health_log_reminder", "condition_advice"),
          ("health_log_reminder", "reminders_help"), ("eating_concern", "diet"), ("fear_of_falling", "safety"),
          ("safety", "posture_result"), ("hot_weather", "treatment_nav"), ("change_password", "forgot_password"),
          ("doctor_said", "best_time"), ("doctor_said", "low_mood"),
          ("text_size", "pain_swelling"), ("missed_session", "plan_exercises"), ("age_limit", "plan_exercises"),
          ("age_limit", "safety"), ("reminder_late_or_off", "reminders_help"), ("adjusted_targets", "posture_result"),
          ]


# As PREFER, unless one of the words is there (laptop pass 8: "doctor said i have sarcopenia" is about
# muscle loss, but "the doctor told me to rest after hospital" is the doctor's advice).
# As PREFER, but only when one of the words is there (3.67: "so frustrated, my score is always low" is the
# posture result; "very lonely since my wife passed away" stays low mood).
PREFER_IF = [("posture_result", "low_mood", ["score", "scores", "result", "results", "marks", "accuracy", "percent"]),
             # 3.74: "how many calories should i eat" is food
             ("diet", "calories", ["eat", "eating", "food", "makan", "diet", "meal", "meals", "drink"]),
             # 3.91: "now 2am cannot sleep, can i exercise" asks about exercising now (rest, it is late)
             ("best_time", "sleep", ["exercise", "exercises", "exercising", "senaman", "senam", "workout"])]
PREFER_UNLESS = [# 3.78: "a stitch in my side" is not a surgical wound's stitches.
                 ("stitch", "condition_advice", ["wound", "operation", "surgery", "dressing", "removed", "cut",
                                                 "incision", "oozing", "bleeding"]),
                 # 3.75: "i have a slipped disc, can i exercise" is the condition; "is it a slipped disc" a diagnosis.
                 ("low_mood", "diagnosis", ASKING_FOR_DIAGNOSIS), ("neck_not_covered", "diagnosis", ASKING_FOR_DIAGNOSIS),
                 # "my doctor said i have gout" is about gout; "my doctor said to rest" the doctor's advice.
                 ("condition_advice", "doctor_said", DOCTOR_SAID_TO), ("neck_not_covered", "doctor_said", DOCTOR_SAID_TO),
                 # 3.74: "i have done my exercises" is done for today, "finished the plan" the plan's end.
                 ("session_done", "plan_progress", ["plan", "plans", "programme", "program", "pelan"]),
                 ("session_done", "treatment_nav", ["where", "which", "what", "find", "plan", "plans"]),
                 # 3.67: "protein shake" is food, "my legs shake" weakness; "i'm bored" motivation, "too easy" not
                 # (not "shaking": it shares its stem with "shake")
                 ("diet", "weakness_balance", ["leg", "legs", "hand", "hands", "arm", "arms", "knee", "knees",
                                               "body", "wobbly"]),
                 # "video upload failed" is recording help; "my video's score" stays the posture result
                 ("recording_help", "posture_result", ["score", "result", "results", "accuracy", "percent", "marks",
                                                       "mistake", "mistakes", "repetition", "repetitions", "reps"]),
                 ("motivation", "difficulty", ["easy", "too easy", "harder", "more difficult", "too hard"]),
                 # 3.50: "I have cancer, can I exercise?" is condition advice; "do I have cancer?" stays diagnosis
                 ("condition_advice", "diagnosis", ["do i have", "could it be", "could this be", "is it cancer",
                                                    "is this cancer", "might be", "do you think", "am i getting",
                                                    "be cancer", "lump", "signs of", "symptoms of"]
                  + ASKING_FOR_DIAGNOSIS),
                 # (3.55: "bed rest weak" is muscle loss; "told me to rest" is the doctor's advice)
                 ("muscle_loss", "doctor_said", ["to rest", "rest for", "rest until", "berehat", "stop", "not to",
                                                 "don't", "avoid", "no exercise", "wait", "until"]),
                 # 3.55: "my exercises" is the plan's list, unless it asks how to do them
                 ("plan_exercises", "how_to", ["rest", "between", "correct", "correctly", "properly", "how to",
                                               "how do", "how should", "form", "technique"]),
                 # 3.55: "help me" is asking what I can do, unless it is about the plan helping
                 ("bot_identity", "plan_progress", ["recover", "plan", "exercise", "exercises", "working", "progress",
                                                    "is it", "are they", "will it"]),
                 # 3.55: "go gym" is another activity, unless it asks what to use
                 ("other_activity", "equipment", ["mat", "need", "chair", "equipment", "ball", "band", "weights",
                                                  "dumbbell", "use"]),
                 # 3.55: "exercise steps" are how to do it, unless it is about the step itself
                 ("how_to", "equipment", ["high", "tall", "height", "stair", "stairs", "box", "platform",
                                          "step up", "step-up", "what step", "which step", "need a step"]),
                 # round 15: "afraid of getting hurt after a fall" is the fear, unless something hurts now
                 ("fear_of_falling", "pain_or_discomfort", ["pain", "painful", "sakit", "ache", "aching", "sore",
                                                            "swollen"]),   # not "hurts": it stems to "hurt"
                 # PC pass 14: "gasping a bit after climbing stairs" is effort, unless something hurts
                 ("tired", "pain_mild", ["pain", "painful", "sore", "ache", "aching", "hurt", "sakit", "stiff",
                                         "swollen", "tender"])]


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
             "long ago", "in the past year", "in the past few years", "years back", "dulu", "once"]
# Words that make a fall recent whatever else is said ("i fell in the past hour", "kalau dia jatuh tadi").
RECENT = ["just now", "tadi", "right now", "today", "little while ago", "a while ago", "past hour",
          "morning again", "again this morning", "again today", "today again",
          "an hour ago", "semalam", "this morning", "this afternoon", "this evening", "tonight",
          "last night", "yesterday", "semalam", "earlier", "moment ago", "minutes ago", "minute ago", "hour ago",
          "hours ago", "past hour", "just fell", "just fallen", "just had a fall", "just collapsed", "just slipped",
          "baru fell"]
STILL_HURT = ["hurt", "hurts", "hurting", "pain", "painful", "sakit", "swollen", "swelling", "bruise", "bruised",
              "still can't", "still cannot", "on the floor", "lying", "confused", "confusion", "keliru", "drowsy",
              "sleepy", "vomit", "vomiting", "headache", "headaches", "not the same", "been the same", "not himself",
              "not herself", "getting worse", "worse since", "limp", "limping", "numb", "numbness",
              "sleeping all day", "sleeps all day", "sleep all day", "sleeping a lot", "sleeps a lot",
              "asleep all the time", "sleep je", "sleep sahaja", "can't remember", "cannot remember", "forgetful",
              "doesn't recognise", "doesn't recognize", "not recognise", "not recognize",
              "can't put weight", "cannot put weight", "can't bear weight", "cannot bear weight", "still cant", "still unable", "still limping",
              "still sore", "can't walk", "cannot walk", "cant walk", "bleeding"]
OLD_ACCIDENT_WORDS = FALL_WORDS | {"hit", "trip", "slip", "banged", "knocked"}
HYPOTHETICAL = ["what if i", "what if you", "what if she", "what if he", "if i", "if you", "if i ever",
                "in case i", "in case you", "kalau saya", "kalau", "supposing i", "suppose i", "how do i",
                "how to", "how can i", "if", "what if", "suppose", "supposing", "in case"]


def _hypothetical(words: list[str], i: int) -> bool:
    """The words just before position i make it a question about what to do ("what if i can't get up");
    also told of a family member ("what if my father can't get up after a fall", 3.73)."""
    j = i
    if j >= 1 and words[j - 1].removesuffix("'s") in PERSON_NOUNS:
        j -= 1
        if j >= 1 and words[j - 1] in ("my", "our"):
            j -= 1
    before = f" {' '.join(words[max(0, j - 3):j])} "
    return any(before.endswith(f" {h} ") for h in HYPOTHETICAL)


# 3.73: the people a family member asks about.
PERSON_NOUNS = frozenset("""mother father mum mom mummy mommy mama mamma dad daddy papa mak emak ibu ayah abah bapa
husband wife spouse suami isteri grandmother grandfather grandma grandpa granny nenek atuk tok son daughter
brother sister uncle aunt aunty auntie friend neighbour neighbor patient parent grandson granddaughter
partner""".split())


# Laptop pass 9: a time word counts only in the fall's own sentence ("my mum fell years ago; today she
# started the plan" is an old fall), and "earlier in my life" is not "earlier today".
# 3.62: also a comma before a new person ("she has fallen, she fell last year too": two falls, one now).
CLAUSE_BREAK = re.compile(r"[.;!?]+|\bbut\b|\btapi\b|\band then\b|,\s*and\b|,\s*(?=(?:i|she|he|my|mum|mom|mother|dad|father|"
                          r"saya|dia|mak|emak|ayah|abah|nenek|atuk)\b)")   # 3.70: "and then" starts a new event
PAST_PHRASES = [("earlier in my life", "long ago"), ("earlier years", "long ago"), ("years earlier", "long ago"),
                ("when i was young", "long ago"), ("when i was younger", "long ago"), ("as a child", "long ago"),
                ("as a kid", "long ago")]
# A fall told with no "I" or name in front ("fell down just now, knee berdarah", "atuk tergelincir pagi
# tadi"): urgent when its own sentence says it was recent.
RECENT_FALL_VERBS = {"fell", "fallen", "slipped", "tripped", "collapsed"}
PEOPLE = {"i", "he", "she", "dia", "mother", "father", "mum", "mom", "dad", "grandma", "grandpa", "grandmother",
          "grandfather", "husband", "wife", "son", "daughter", "we", "they", "uncle", "aunt", "patient"}
# What may follow "slipped"/"tripped" in a fall ("slipped in the bathroom"), not "slipped the note under".
AGAIN_FILLER = {"again", "lagi", "and", "it", "happened", "the", "same", "thing", "once", "more", "she", "he", "i",
                "dia", "saya", "did", "so", "then", "now", "sekali",
                "ah", "leh", "lor", "meh", "huh", "pls", "please"}       # 3.85: "it happened again today ah"
TIME_FILLER = AGAIN_FILLER | {"it", "was", "that", "this", "about", "around", "already", "la", "lah", "maybe", "like",
                              "only", "yes", "ya", "a", "an", "few", "some", "two", "three", "2", "3", "4", "5"}
# Good-news words may follow a past time only ("that was last year, now fine"; not "today i'm fine").
CALM_FILLER = {"fine", "ok", "okay", "good", "better", "is", "she's", "he's", "i'm", "all"}
SLIP_NEXT = {"in", "on", "at", "dalam", "di", "over", "down", "and", "while", "when", "near", "outside", "inside",
             "just", "this", "today", "yesterday", "earlier", "tadi", "semalam", "from", "off"}
# Long-standing symptoms are not new warning signs (laptop pass 9 debatable cases).
CHRONIC = {"numb": ["years ago", "for years", "since the operation", "since my operation", "since surgery",
                    "since the surgery", "since my surgery", "for a long time", "long time", "always", "since birth",
                    "since my stroke", "because of diabetes", "because of my diabetes", "from diabetes",
                    "due to diabetes", "diabetic", "neuropathy", "since years", "for many years"],
           "vomit": ["after eating", "right after eating", "after a meal", "after meals", "full stomach",
                     "after lunch", "after dinner", "after breakfast", "lepas makan"]}
CHRONIC["numbness"] = CHRONIC["numb"]
for _p in ['cannot talk properly', "can't talk properly", 'cannot speak properly', "can't speak properly", 'cannot get my words out', "can't get my words out", 'cannot get the words out', "can't get the words out", 'words come out wrong', 'words are jumbled', 'talking funny', 'speech is strange']:
    CHRONIC[_p] = CHRONIC["numb"]                   # "cannot talk properly since my stroke" is not new
CHRONIC["vomiting"] = CHRONIC["vomit"]


# Events that are history when told with a past time in their own sentence (laptop pass 12).
HISTORY_EVENTS = {"heart attack", "had a seizure", "had a fit", "convulsion", "convulsions"}
YEAR = re.compile(r"^(19|20)[0-9][0-9]$")


def _past_event(phrase: str, clauses: list[list[str]]) -> bool:
    own = [c for c in clauses if find_phrase(phrase, c)]
    return bool(own) and all(
        (any(find_phrase(p, c) for p in PAST_TIME + ["history of", "previous", "previously", "before"])
         or any(YEAR.match(w) for w in c))
        and not any(find_phrase(p, c) for p in RECENT + ["having", "now", "right now"]) for c in own)


def _clauses(text: str) -> list[list[str]]:
    out = []
    for part in CLAUSE_BREAK.split(text.lower()):
        p = f" {clean(part)} "
        for a, c in NOT_A_FALL + PAST_PHRASES:
            p = p.replace(f" {a} ", f" {c} ")
        if not p.strip():
            continue
        words = p.split()
        # A sentence that only says when belongs to the one before ("My mum fell. It was years ago.").
        when = {w for ph in RECENT + PAST_TIME for w in ph.split() if find_phrase(ph, words)}
        recent = any(find_phrase(ph, words) for ph in RECENT)
        filler = TIME_FILLER if recent else TIME_FILLER | CALM_FILLER
        if out and when and all(w in when or w in filler for w in words):
            out[-1] = out[-1] + words
        else:
            out.append(words)
    return out


def _when(phrase: str, clauses: list[list[str]], words: list[str]) -> tuple[bool, bool]:
    """(old, recent) for a fall phrase, judged in the sentence it is in; a symptom anywhere keeps it urgent."""
    if any(find_phrase(h, words) for h in STILL_HURT + HARD_SIGNS):
        return False, True
    own = [c for c in clauses if find_phrase(phrase, c)] or [words]
    recent = any(find_phrase(p, c) for c in own for p in RECENT)
    old = not recent and all(any(find_phrase(p, c) for p in PAST_TIME) for c in own)
    return old, recent


def _person_fell(c: list[str], i: int, times: set[str]) -> bool:
    """c[i] is a fall verb told of a person, or at the start of its sentence once time words are skipped
    ("pagi tadi jatuh lagi"); not "the phone fell", "slipped the note", "if i fell"."""
    w = c[i]
    if w not in RECENT_FALL_VERBS:
        return False
    k = i - 1
    while k >= 0 and (c[k] in ("just", "baru", "has", "had", "have", "suddenly", "lah", "la", "ah", "leh", "so",
                                "then", "and", "also", "plus", "but", "tapi", "dan", "ok", "okay") or c[k] in times):
        k -= 1
    if k >= 0 and c[k] not in PEOPLE:
        return False                                   # "the phone fell", "the price has fallen today"
    if NEGATORS & set(c[max(0, i - 2):i]) or _hypothetical(c, i):
        return False
    if w in ("slipped", "tripped") and i + 1 < len(c) and c[i + 1] not in SLIP_NEXT:
        return False                                   # "slipped the note under the door this morning"
    return True


def _recent_fall(clauses: list[list[str]]) -> bool:
    """A person's fall that is recent, judged sentence by sentence (laptop passes 9 and 10)."""
    previous = None                                    # the last fall told: "old" (with a past time) or "new"
    for c in clauses:
        times = {w for p in RECENT for w in p.split() if find_phrase(p, c)}
        past = any(find_phrase(p, c) for p in PAST_TIME)
        again = bool({"again", "lagi"} & set(c))
        if any(_person_fell(c, i, times) for i in range(len(c))):
            if times or (again and not past):
                return True                            # "fell this morning", "now she fell again"
            previous = "old" if past else "new"
            continue
        if times and previous:
            # A sentence that says only when: "Fell. Just now.", "fell last month. today again."
            rest = [w for w in c if w not in times and w not in AGAIN_FILLER]
            if not rest and (previous == "new" or again):
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
    # PC safety pass 16: under 3.0 mmol/L is a severe low whether or not symptoms are told ("my glucose is 2.8").
    if any(float(v) < 3.0 for v in SUGAR_READING.findall(low)):
        return True
    if not any(w in low for w in LOW_SUGAR_SIGNS):
        return False
    for v in SUGAR_READING.findall(low):
        x = float(v)
        if x < 4.0 or 20 <= x < 70:
            return True
    return False


HIGH_SUGAR_SIGNS = ("vomit", "sick", "nausea", "thirsty", "drowsy", "confused", "breath", "unwell", "muntah",
                    "dahaga", "pening", "very weak", "keliru")


def high_sugar(text: str) -> bool:
    """A very high blood sugar reading with symptoms (laptop pass 11: 'my sugar is 25 and i feel very
    sick'): 20-35 mmol/L or 360-1000 mg/dL. 20-69 with a low-sugar sign is caught by low_sugar."""
    low = text.lower()
    if not any(w in low for w in HIGH_SUGAR_SIGNS):
        return False
    return any(20 <= float(v) <= 35 or 360 <= float(v) <= 1000 for v in SUGAR_READING.findall(low))


# 3.74 (numbers test, chat_numbers_set.py): oxygen and pulse readings. Oxygen (SpO2) of 92% or lower, or a
# pulse of 150 or more or 40 or less, needs help now ("spo2 88", "heart rate 160 after exercise"); "hr" counts
# only at the start ("1 hr 30 min" is a time).
OXYGEN_RE = re.compile(r"\b(?:oxygen|o2|spo2|sp02|saturation|sats|oksigen|oximeter)\b\D{0,20}?(\d{2,3})(?:\.\d)?"
                       r"(?!\s*(?:min|mins|minute|minutes|hours?|hrs?|litres?|liters?|l\b|lpm|years?|kg|cm|\d))")
PULSE_RE = re.compile(r"\b(?:heart ?rate|heart ?beat|pulse|pulse rate|nadi|kadar nadi|denyutan jantung)\b\D{0,20}?"
                      r"(\d{2,3})\b(?!\s*(?:%|percent|min|mins|minute|minutes|hours?|days?|years?|kg|cm|steps|reps|\.\d))|"
                      r"^\W*(?:(?:hi|hello|ok|okay|doc|um|uh)\s+)?(?:my\s+)?hr\s*(?:is\s*)?(\d{2,3})\b|"
                      r"\b(\d{2,3})\s*bpm\b")


def oxygen_reading(text: str) -> int | None:
    v = [int(x) for x in OXYGEN_RE.findall(text.lower()) if 50 <= int(x) <= 100]
    return min(v) if v else None


def pulse_reading(text: str) -> int | None:
    v = [int(n) for m in PULSE_RE.findall(text.lower()) for n in m if n and 25 <= int(n) <= 250]
    return v[0] if v else None


def low_oxygen(text: str) -> bool:
    v = oxygen_reading(text)
    return v is not None and v <= 92


def odd_pulse(text: str) -> bool:
    v = pulse_reading(text)
    return v is not None and (v >= 150 or v <= 40)


def _bp_reading(text: str) -> bool:
    """A blood pressure reading that could be real ("120/80"; not a pain score "10/10", 3.74)."""
    return any(70 <= int(s) <= 280 and 40 <= int(d) <= 180 and int(s) > int(d) for s, d in BP_READING.findall(text))


def high_bp(text: str) -> bool:
    for sys_, dia in BP_READING.findall(text):
        s_, d_ = int(sys_), int(dia)
        if 70 <= s_ <= 280 and 40 <= d_ <= 180 and s_ > d_ and (s_ >= 180 or d_ >= 110):
            return True
    return False


def crisis(text: str | None) -> bool:
    """Thoughts of suicide or self-harm: checked before everything else, also with slips mended
    ("suicdie", "i wsnt to die", "tired of livign", 3.55), and with an unknown word read as the word of
    a crisis phrase it is one slip from ("better if i was goe", "i wsant to die", 3.62); each part of a
    message that changes topic on its own too (3.70)."""
    return any(_crisis_whole(p) for p in [text] + _topic_parts(text))


def _crisis_whole(text: str | None) -> bool:
    if _also_respelled(_crisis, text):
        return True
    mended = _phrase_mend(text, "crisis")
    return mended is not None and _crisis(mended)


# 3.70 (the compound test, chat_compound_set.py): a warning sign joined to another question with "also",
# "another thing" or "plus" ("everything is blurry. another thing, is this app free") was read as one
# message and missed. Split only where the topic plainly changes, never at a full stop alone: "she fell.
# that was last year, now fine" stays one message.
TOPIC_CHANGE = re.compile(r"(?i)\b(?:also|another thing|one more thing|plus|by the way|btw|oh and|and also|"
                          r"lagi satu|satu lagi|other thing|anyway|and then)\b|\b(?:lah|leh|la)\s*,|\.{3,}|\u2026|"
                          r",?\s+and\s+(?=(?:what|how|can|should|is|are|do|does|why|when|where|which)\b)|"
                          r",\s*(?=what if\b)|\s(?=suddenly\b)")
# A part saying the fall was long ago or the person is fine now ("i fell... long time ago, now ok").
CALM_AFTER = ["now fine", "i'm fine", "im fine", "now ok", "ok now", "okay now", "better now", "recovered",
              "no injury", "not hurt", "wasn't hurt", "was not hurt", "long ago", "long time ago"]


def _topic_parts(text: str | None) -> list[str]:
    """The parts of [text] between topic changes, when there is more than one."""
    if not text:
        return []
    parts = [p.strip(" ,.;!?") for p in TOPIC_CHANGE.split(text)]
    parts = [p for p in parts if len(p.split()) >= 2]
    return parts if len(parts) > 1 else []


def _crisis(text: str | None) -> bool:
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
            if p.split()[0] in ("wish", "wishes", "wished") and OTHER_WORDS & set(p.split()) and prev in ("i", "we"):
                continue                               # "i wish he was dead" is anger at him (3.73)
            return True
    return False


CRISIS_NEGATORS = {"don't", "dont", "never", "not"}
SELF_WORDS = {"i", "i'm", "im", "me", "my", "myself", "i've", "i'd", "i'll", "saya", "aku"}
OTHER_WORDS = {"he", "she", "dia", "him", "his", "her", "himself", "herself", "he's", "she's"}


def _crisis_about_other(text: str | None) -> bool:
    """The crisis words are told of someone else ("my dad wishes he was dead", "my mother keeps saying she
    wants to die"), not the user's own (3.73): the nearest person before the first crisis phrase."""
    words = clean(text or "").split()
    hits = sorted((i, p) for p in rules().get("crisis", []) for i in find_phrase(p, words))
    if not hits:
        return False
    i, p = hits[0]
    said = set(p.split())
    if said & SELF_WORDS:
        return False                                     # "kill myself", "wish i was dead"
    if said & OTHER_WORDS:
        return True                                      # "kill himself", "wish she was dead"
    for w in reversed(words[max(0, i - 6):i]):
        if w in SELF_WORDS:
            return False
        if w in OTHER_WORDS or w.removesuffix("'s") in PERSON_NOUNS:
            return True
    return False
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
             "double warfarin", "extra warfarin", "warfarin twice", "double my blood thinner",
             # PC safety pass 16: three or more times a dose, and extra sleeping pills. A regular medicine
             # taken twice by mistake stays a pharmacist question (decided in laptop pass 6).
             "three times my dose", "3 times my dose", "four times my dose", "4 times my dose",
             "five times my dose", "5 times my dose", "three times the dose", "3 times the dose", "triple dose",
             "triple my dose", "extra sleeping pills", "extra sleeping tablets",
             # Malay puts the amount after the medicine ("makan ubat terlalu banyak")
             "ubat terlalu banyak", "terlebih makan ubat", "terlebih ubat", "ubat berlebihan", "telan ubat banyak"]
OD_BOXES = ["medicine box", "pill box", "pillbox", "medicine cabinet", "kotak ubat"]
OVERDOSE_ANSWER = ("Taking too many pills can be dangerous even if you feel fine now.\n"
                   "1) Call 999 or go to the nearest emergency department now; do not wait for symptoms.\n"
                   "2) Take the medicine packets with you.\n"
                   "If this was on purpose, or you are thinking of harming yourself, you are not alone: "
                   "Befrienders KL 03-7627 2929 (24 hours) or Talian HEAL 15555 (8 am to midnight).")
# Household chemicals swallowed (laptop pass 7): Dettol, bleach, floor cleaner, pesticide...
POISONS = ["dettol", "clorox", "bleach", "floor cleaner", "cleaner", "pesticide", "insecticide", "racun",
           "kerosene", "minyak tanah", "antifreeze", "weed killer", "detergent", "toilet cleaner", "lysol",
           # PC safety pass 16
           "cleaning liquid", "cleaning fluid", "cleaning product", "dishwashing liquid", "pencuci", "sabun cecair"]
POISON_VERBS = {"drank", "drink", "drinks", "swallowed", "swallow", "ate", "eaten", "minum", "telan", "took", "had",
                "terminum", "tertelan"}
POISON_ANSWER = ("Swallowing a cleaning product, pesticide or other chemical is an emergency.\n"
                 "1) Call 999 now or go to the nearest emergency department.\n"
                 "2) Take the bottle with you.\n"
                 "3) Do not try to make them vomit.\n"
                 "If it was on purpose, or you are thinking of harming yourself, you are not alone: "
                 "Befrienders KL 03-7627 2929 (24 hours) or Talian HEAL 15555 (8 am to midnight).")


@lru_cache(maxsize=1)
def _drug_names() -> frozenset:
    """Medicines by name (3.77: "amlodipine", "metformin", "arcoxia"), from the rules."""
    return frozenset(rules().get("drug_names", []))


def _is_medicine(w: str) -> bool:
    return w in OD_SUBSTANCES or w in _drug_names() or w.startswith("pill") or w.startswith("tablet") \
        or w.startswith("painkiller")


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
    return _also_respelled(_poisoning, text)


def _poisoning(text: str | None) -> bool:
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
    return _also_respelled(_overdose, text)


def _overdose(text: str | None) -> bool:
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


@lru_cache(maxsize=4)
def _phrase_index(kind: str) -> dict:
    """{first letter: [(phrase words, position, word)]} for the words of 3+ letters of the crisis or
    warning-sign phrases of two or more words (the other words are the evidence: "pening" alone is not)."""
    index: dict[str, list] = {}
    for p in rules().get("crisis" if kind == "crisis" else "red_flags", []):
        # As typed ("peeat hidup" is penat), and as the message is read once cleaned ("penat hduup": "penat" is
        # read as "tired", 3.85).
        for ws in dict.fromkeys([tuple(p.split()), tuple(clean(p).split())]):
            if len(ws) < 2:
                continue
            for k, w in enumerate(ws):
                if len(w) >= 3 and w.isalpha():
                    index.setdefault(w[0], []).append((ws, k, w))
    return index


@lru_cache(maxsize=20000)
def _phrase_mend(text: str | None, kind: str) -> str | None:
    """The message with one unknown word (not a rules word, not a real word) replaced by the word of a
    crisis or warning-sign phrase it is one slip from, when the rest of that phrase is there as typed;
    None when there is no such phrase (3.62: "better if i was goe", "blajed out", "peeat hidup"). 3.85:
    two slips in a word of 4+ letters too ("bledig a lot", "herrat pounding", "penat hduup", "sucde thoughts"):
    the rest of the phrase, as typed, is the evidence."""
    if not text:
        return None
    words = clean(text).split()
    known = vocabulary()
    for i, w in enumerate(words):
        if len(w) < 2 or not w.isalpha() or w in known or w in rare_words():
            continue                                     # a real word, even a rarer one ("pruning"), stays
        texted = not NO_VOWEL_RE.search(w[1:])             # the rest of the phrase says it is Malay ("bunuh dr")
        if w in dictionary() and not texted:
            continue
        for ws, k, p in _phrase_index(kind).get(w[0], ()):
            if not (_skeleton(p) == w and texted) and (
                    len(w) < 3 or w in dictionary() or abs(len(p) - len(w)) > 2
                    or typo_cost(w, p) > (1.0 if len(p) < 4 else 1.5 if len(p) < 6 else 2.0)):
                continue
            if p in ("fell", "fall", "fallen") and typo_cost(w, "feel") <= typo_cost(w, p):
                continue                                 # "i fele so lazy": feel, as in respell (3.64)
            start = i - k
            if start < 0 or start + len(ws) > len(words):
                continue
            # The other words as typed, or texted without vowels too ("ssk nfs": sesak nafas).
            others = [j for j in range(len(ws)) if j != k]
            if all(words[start + j] == ws[j] or (words[start + j] == _skeleton(ws[j]) and len(ws[j]) >= 3)
                   for j in others):
                mended = words[:start] + list(ws) + words[start + len(ws):]
                return " ".join(mended)
    return None


def _also_respelled(check, text: str | None) -> bool:
    """A safety check on the message as typed, then on the message with its slips mended (3.55)."""
    if not text:
        return False
    if check(text):
        return True
    again = respell(text)
    return _plain(again) != _plain(text) and check(again)


def red_flag(text: str | None) -> bool:
    if not text:
        return False
    if _red_flag_whole(text):
        return True
    parts = _topic_parts(text)                           # each part on its own too (3.70)
    for k, part in enumerate(parts):
        if not _red_flag_whole(part):
            continue
        others = clean(" ".join(parts[:k] + parts[k + 1:])).split()
        if FALL_WORDS & set(clean(part).split()) and not FALL_WORDS & set(others) \
                and any(find_phrase(p, others) for p in PAST_TIME + CALM_AFTER):
            continue                                     # "i fell... long time ago, now ok" (not another fall's)
        return True
    return False


def _red_flag_whole(text: str) -> bool:
    if _red_flag_typed(text):
        return True
    mended = _phrase_mend(text, "red_flags")             # one unknown word of a warning-sign phrase (3.62)
    return mended is not None and _red_flag_typed(mended)


def _red_flag_typed(text: str) -> bool:
    if _reading_flag(text):
        return True                                      # as typed: respelling may rename the reading ("sats", 3.74)
    again = respell(text)
    base = again if _plain(again) != _plain(text) else text
    # "ok fell over this morning", "sorry jatuh tahun lepas, tapi tadi lagi": a filler in front is not
    # who fell (3.56).
    bare = _LEADING_FILLER_RE.sub("", base)
    return _red_flag(base) or (bare != base and bool(bare.strip()) and _red_flag(bare))


def _reading_flag(text: str) -> bool:
    """A blood pressure, sugar, oxygen or pulse reading that needs help now."""
    return high_bp(text) or low_sugar(text) or high_sugar(text) or low_oxygen(text) or odd_pulse(text)


def _red_flag(text: str) -> bool:
    if _reading_flag(text):
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
                if phrase in HISTORY_EVENTS and _past_event(phrase, clauses):
                    continue                           # "i had a heart attack last year"
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
                    if _combo_negated(words, i):
                        continue                       # "no chest pain", "never had breathing trouble"
                    lo = max(0, i - window)
                    near = words[lo:i + window + 1]
                    for s in symptoms:
                        for j in find_phrase(s, near):
                            if _combo_negated(near, j):
                                continue               # "neck pain is better, no fever"
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


def _real_word(w: str) -> bool:
    """The stem (stem()) of an English or Malay word, common or rarer: not a stray letter or a string of
    them."""
    if len(w) <= 1:
        return False
    known = (dictionary(), rare_words(), _respell_vocab())
    return any(w + s in k for s in ("", "s", "e", "ed", "es", "ing", "ings") for k in known)


def overlap_match(plan_id: str | None, text: str) -> tuple[dict | None, float]:
    """Best rule by weighted share of the question's words found in the rule's vocabulary."""
    q = _stems(text)
    docs, idf = _overlap_index(plan_id)
    known = {t for t in q if t in idf}
    if not known:
        return None, 0.0
    unknown_weight = math.log(len(docs) + 1) + 1          # an unseen word weighs like the rarest word
    # ... if it is a real word ("transfers"); a stray letter or letters typed by mistake ("... at a time k",
    # "looks bigger bycx") are not evidence against the match (3.60).
    total = sum(idf[t] if t in idf else unknown_weight if _real_word(t) else 0.0 for t in q)
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
                   "heart problem": "HEART_DISEASE", "heart attack": "HEART_DISEASE", "pacemaker": "HEART_DISEASE",
                   "stent": "HEART_DISEASE", "stroke": "STROKE", "asthma": "ASTHMA", "asthmatic": "ASTHMA",
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
                   "sprain": "INJURY", "sprained": "INJURY",
                   # 3.50 (11 Oct): the conditions added to the health profile
                   "rheumatoid": "RHEUMATOID_ARTHRITIS", "copd": "COPD", "lung disease": "COPD",
                   "chronic lung": "COPD", "emphysema": "COPD", "cancer": "CANCER", "chemo": "CANCER",
                   "chemotherapy": "CANCER", "radiotherapy": "CANCER", "kanser": "CANCER", "barah": "CANCER",
                   "kidney disease": "KIDNEY_DISEASE", "kidney problem": "KIDNEY_DISEASE",
                   "dialysis": "KIDNEY_DISEASE", "buah pinggang": "KIDNEY_DISEASE", "parkinson": "PARKINSONS",
                   "parkinsons": "PARKINSONS", "multiple sclerosis": "MULTIPLE_SCLEROSIS",
                   "foot ulcer": "FOOT_ULCER", "diabetic foot": "FOOT_ULCER", "wound on my foot": "FOOT_ULCER",
                   # 3.54 (15 Oct): everyday names (Malay ones arrive translated by MALAY_PHRASES)
                   "osteoarthritis": "ARTHRITIS", "weak bones": "OSTEOPOROSIS", "brittle bones": "OSTEOPOROSIS",
                   "thin bones": "OSTEOPOROSIS", "gave birth": "PREGNANCY", "just had a baby": "PREGNANCY",
                   "after delivery": "PREGNANCY", "parkinson's": "PARKINSONS", "have ms": "MULTIPLE_SCLEROSIS",
                   "with ms": "MULTIPLE_SCLEROSIS", "for ms": "MULTIPLE_SCLEROSIS", "got ms": "MULTIPLE_SCLEROSIS",
                   "ms exercise": "MULTIPLE_SCLEROSIS", "ms can": "MULTIPLE_SCLEROSIS", "ada ms": "MULTIPLE_SCLEROSIS"}


@lru_cache(maxsize=1)
def _condition_phrases() -> tuple:
    """CONDITION_WORDS and (3.75) the conditions the profile does not list, cleaned as messages are ("bahu
    beku" -> "shoulder beku")."""
    phrases = {**CONDITION_WORDS, **rules().get("condition_words", {})}
    return tuple((p, code) for phrase, code in phrases.items() for p in dict.fromkeys([phrase, clean(phrase)]))


def conditions_in(text: str | None) -> list[str]:
    if not text:
        return []
    words = clean(text).split()
    found = list(dict.fromkeys(code for phrase, code in _condition_phrases() if find_phrase(phrase, words)))
    if "RHEUMATOID_ARTHRITIS" in found and "ARTHRITIS" in found:
        found.remove("ARTHRITIS")                  # "rheumatoid arthritis" is the one condition
    return found


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
                 "says", "say", "saying", "result", "told", "mistake", "feedback", "explain", "maksud",
                 # 3.54: "how to fix bent knee", "why heels lift", "how do i stop body swing"
                 "fix", "correct", "why", "how to", "how do i", "stop", "avoid", "improve", "kenapa", "betulkan"]


@lru_cache(maxsize=1)
def _glossary_clean() -> dict[str, str]:
    """Mistake names as typed ("heels lift", "heels_lift") and as clean() leaves them ("low knee lift"
    -> "low knee raise"), except a cleaned name that is also an exercise name ("heel raise")."""
    exercise_names = {clean(a) for e in rules().get("exercises", {}).values() for a in [e["name"]] + e["aliases"]}
    out = {p.replace("_", " "): k for p, k in rules().get("glossary", {}).items()}
    out.update({c: k for p, k in rules().get("glossary", {}).items()
                if (c := clean(p)) not in exercise_names and c not in out})
    return out


def _plain_words(text: str) -> list[str]:
    """Lower case, letters and digits only, without clean()'s synonyms."""
    return re.sub(r"[^a-z0-9 ]", " ", text.lower().replace("_", " ")).split()


def glossary_match(text: str) -> dict | None:
    words = clean(text).split()
    names = _glossary_clean()
    plain = _plain_words(text)
    for w in (" ".join(plain), " ".join(words)):          # the name alone ("heels lift?", "not closed")
        if w in names:
            return next((i for i in rules()["intents"] if i["key"] == names[w]), None)
    if not any(find_phrase(c, words) for c in GLOSSARY_CUES):
        return None
    # Exact names only: the topic matcher treats "raise" and "lift" alike, but "heel raises" is not
    # the mistake "heels lift". Names are compared after the same cleaning as the message (3.54).
    padded = f" {' '.join(words)} "
    padded_plain = f" {' '.join(plain)} "
    hits = [(len(p), key) for p, key in names.items() if f" {p} " in padded or f" {p} " in padded_plain]
    if not hits:
        return None
    key = max(hits)[1]                                   # the longest name ("shoulder shrug" over "shrug")
    return next((i for i in rules()["intents"] if i["key"] == key), None)


def _spans(text: str, phrases: list[str]) -> list[tuple[int, int]]:
    words = clean(text).split()
    return [(i, i + len(clean(p).split())) for p in phrases for i in find_phrase(p, words)]


_GENERIC_NAME_WORDS = {"exercise", "exercises", "the", "a", "my", "senaman", "workout", "move", "movement"}


def _near_exercise_name(text: str, intents: list[dict]):
    """3.54: an exercise name typed with a slip inside it ("sit-tostand", "wall pus-up"): the closest
    multi-word name of at least 8 letters, when it is 88 % alike (RapidFuzz partial ratio)."""
    t = clean(text)
    best = None
    for i in intents:
        if not i["key"].startswith("exercise:"):
            continue
        for alias in i["keywords"]:
            # Only the name's own words: "hand exercise" must not match any "... exercise".
            core = " ".join(w for w in alias.split() if w not in _GENERIC_NAME_WORDS)
            if len(core.replace(" ", "")) < 7 or " " not in core or len(t) < len(core) - 2:
                continue
            # Within a longer message, the best-matching part of it; a message no longer than the name is
            # compared whole ("ste up" is step up, not the end of "wrist up").
            score = fuzz.partial_ratio(core, t) if len(t) > len(core) else fuzz.ratio(core, t)
            if score >= 88 and (best is None or score > best[0]):
                best = (score, (i["priority"], len(alias.split()), i))
    return best[1] if best else None


def _inside_exercise_names(text: str, hits: list) -> list:
    """Drop a general rule whose every keyword found lies inside an exercise's name ("marching while
    sitting" is not the "while sitting" question, "balance stand" is not about balance; PC probe of
    exercise questions, 9 Oct). A keyword found outside the name keeps the rule ("I lose my balance in
    the balance stand")."""
    names = [s for h in hits if h[2]["key"].startswith("exercise:") for s in _spans(text, h[2]["keywords"])]
    if not names:
        return hits
    out = []
    for h in hits:
        if not h[2]["key"].startswith("exercise:"):
            own = _spans(text, h[2]["keywords"])
            if own and all(any(a <= i and j <= b and (b - a) > (j - i) for a, b in names) for i, j in own):
                continue
        out.append(h)
    return out


# 3.70: a story first, then the question ("i had nasi lemak for breakfast, how high should i lift my
# arms"): the question decides, unless the first part is about the body, a symptom, an exercise or the app,
# or the whole message is about how the person is (then the whole message decides).
QUESTION_START = re.compile(r"^(?:can|could|should|how|what|when|where|which|why|is|are|do|does|did|will|would|"
                            r"may|must|any|boleh|macam mana|berapa|bila|kenapa|apa|i want|i need|please|pls|help)\b")
STORY_BREAK = re.compile(r"[.!?;]+|,|\band then\b|\bso\b|\banyway\b|\blah\b")
ABOUT_THE_PERSON = {"pain_or_discomfort", "pain_mild", "pain_sharp", "pain_swelling", "low_mood", "tired",
                    "weakness_balance", "fear_of_falling", "condition_advice", "medication", "diagnosis",
                    "hot_weather", "safety", "doctor_said", "doctor_clearance", "muscle_loss", "joint_noise",
                    "eating_concern", "missed_session", "motivation", "bladder_leak", "for_someone_else",
                    "family_help", "partial_reps", "age_limit", "wrong_exercise", "adjusted_targets",
                    # 3.76: a situation told first ("air quality is bad, can i still exercise")
                    "haze", "fasting", "weather", "travel", "surgery", "period", "alcohol_smoking", "after_treatment"}
# A question that points back at the story ("i only did half of each movement, does it count").
POINTS_BACK = {"it", "this", "that", "them", "these", "those", "so", "one"}


def _question_after_story(text: str) -> str | None:
    """The last part of [text] when it is a question of 3+ words and what comes before it is a story with no
    word about the body, a symptom, an exercise or the app."""
    parts = [p.strip() for p in STORY_BREAK.split(text.lower()) if p.strip()]
    if len(parts) < 2:
        return None
    last = parts[-1]
    before = " ".join(parts[:-1])
    if len(last.split()) < 3 or not QUESTION_START.search(last):
        return None
    if POINTS_BACK & set(last.split()):
        return None                                      # "does it count" needs the story
    words, names = _rehab_anchors()
    plain = clean(respell(before))
    if set(plain.split()) & words or any(f" {n} " in f" {plain} " for n in names):
        return None
    return last


# 3.88 (compound test): a scene told first, then the point ("the weather is very hot today, i missed 2 weeks
# because i was in hospital", "my daughter helped me set up the phone, how is my risk calculated", "i just
# finished my breakfast, so thank you doctor"): the later part's own topic is answered. The scene stays when the
# later part is about it (hot weather and jogging; "can she do it"). {scene: topics that keep the scene}
SCENES = {"hot_weather": {"safety", "best_time", "other_activity", "how_to", "how_often", "equipment", "difficulty",
                          "weather"},
          "weather": {"safety", "best_time", "other_activity", "how_to", "how_often", "equipment", "difficulty",
                      "hot_weather"},
          "family_help": {"for_someone_else"}, "for_someone_else": {"family_help"},
          "diet": {"best_time", "eating_concern", "calories"}}
THIRD_PERSON = {"she", "he", "her", "him", "his", "they", "them", "their", "dia"}


def _point_after_scene(plan_id: str | None, text: str, scene: dict) -> tuple[dict | None, str | None] | None:
    parts = [p.strip() for p in STORY_BREAK.split(text.lower()) if len(p.split()) >= 2]
    if len(parts) < 2:
        return None
    for part in reversed(parts[1:]):
        c, h = _match_whole(plan_id, part)
        if c is None or (c.get("small_talk") and c["key"] not in ("thanks", "goodbye")) or c["key"] == "acknowledge":
            continue
        if c["key"] == scene["key"] or c["key"] in SCENES[scene["key"]]:
            return None                                  # the later part is about the scene too
        if scene["key"] == "for_someone_else" and THIRD_PERSON & set(part.split()):
            return None                                  # "...can she do this": still about her
        return c, h
    return None


# 3.72: "what is abduction", "what does flexion mean", "range of motion means?", "apa maksud BMI".
DEFINITION_RE = re.compile(r"^(?:what(?:'s| is| are| does| do)?|whats|define|meaning of|apa itu|apa maksud|maksud|"
                           r"what is the meaning of|what do you mean by|what does it mean by)\s+(?:a |an |the )?"
                           r"(?P<a>[a-z0-9' -]+?)(?:\s+(?:mean|means|meaning|stand for))?\s*\??$|"
                           r"^(?P<b>[a-z0-9' -]+?)\s+(?:means|meaning|mean|maksud|tu apa|itu apa|is what|means what)\s*\??$")


def _term_asked(text: str | None) -> str | None:
    """The TERMS word a definition question asks about, if any."""
    low = " ".join(re.sub(r"[^a-z0-9' ?-]", " ", (text or "").lower()).split())     # (3.93: "spo2")
    low = re.sub(r"^(?:um|uh|hi|hello|ok|okay|sorry|doc|excuse me)\s+", "", low)
    low = re.sub(r"\s+(?:lah|ah|leh|pls|please|huh)\s*\??$", "", low)
    m = DEFINITION_RE.match(low)
    if not m:
        return None
    word = (m.group("a") or m.group("b") or "").strip()
    r = rules()
    word = r.get("term_aliases", {}).get(word, word)
    return word if word in r.get("terms", {}) else None


# 3.73 (caregiver test, chat_caregiver_set.py): a family member asks about the person they help ("where to
# edit my dad's weight" was the equipment answer, "my mother failed the posture check" the how-to answer).
# The question is also read as if that person asked it ("where to edit my weight"); its topic wins unless it
# is only a general how-to, safety or plan answer ("can my mother do these exercises": she needs her own
# profile, the answer for a family member).
SUBJECT_BEFORE = frozenset("""if when can could does do did should will would is was has had that and but because so
what how why where while after before until since whether then now also said says say thinks think feel feels
scared afraid worried sure wonder know""".split())
THIRD_TO_FIRST = {"is": "am", "isn't": "am not", "has": "have", "hasn't": "haven't", "does": "do", "doesn't": "don't",
                  "feels": "feel", "gets": "get", "needs": "need", "wants": "want", "keeps": "keep", "hurts": "hurt",
                  "goes": "go", "tries": "try", "loses": "lose", "thinks": "think", "says": "say", "walks": "walk",
                  "uses": "use", "takes": "take", "sleeps": "sleep", "eats": "eat", "falls": "fall", "lives": "live",
                  "likes": "like", "knows": "know", "forgets": "forget", "finds": "find", "struggles": "struggle",
                  "refuses": "refuse", "complains": "complain", "stands": "stand", "sits": "sit", "seems": "seem",
                  "looks": "look", "gives": "give", "starts": "start", "stops": "stop", "misses": "miss",
                  "skips": "skip", "finishes": "finish", "holds": "hold", "lifts": "lift", "bends": "bend",
                  "moves": "move", "shakes": "shake", "limps": "limp", "exercises": "exercise", "records": "record",
                  "reaches": "reach", "works": "work", "wakes": "wake", "becomes": "become", "cries": "cry"}
BEFORE_I = {"does": "do", "is": "am", "has": "have", "doesn't": "don't", "isn't": "aren't", "hasn't": "haven't"}
VERB_AFTER_PERSON = {"can", "cannot", "can't", "will", "won't", "was", "fell", "had", "did", "didn't", "should", "could",
                     "would", "must", "always", "never", "still", "just", "also", "often", "keeps", "felt", "got"}
KEEP_FOR_OTHERS = {"family_help", "cannot_do", "word_meaning"}
GENERAL_FOR_OTHERS = {"how_to", "plan_exercises", "safety", "how_often", "difficulty", "start_plan", "app_help",
                      "getting_started", "for_someone_else", "family_help", "cannot_do"}


def _as_if_mine(text: str | None) -> str | None:
    """[text] as if the family member it is about had typed it, or None when it names no one else."""
    words = " ".join(re.sub(r"[^a-z0-9' ]", " ", (text or "").lower().replace("\u2019", "'")).split()).split()
    out = []
    k = 0
    while k < len(words):
        w = words[k]
        nxt = words[k + 1] if k + 1 < len(words) else ""
        prev = out[-1] if out else ""
        if w in ("my", "our") and nxt.removesuffix("'s") in PERSON_NOUNS:
            if nxt.endswith("'s"):
                new = "my"                               # "my dad's weight"
            else:
                after = words[k + 2] if k + 2 < len(words) else ""
                new = "i" if not out or prev in SUBJECT_BEFORE or prev in PURE_FILLERS | ADDRESS_WORDS \
                    or after in THIRD_TO_FIRST or after in VERB_AFTER_PERSON else "me"   # "help my mother stand up"
            k += 2
        elif w in ("he", "she", "dia", "he's", "she's"):
            new = "i" if w in ("he", "she", "dia") else "i'm"
            k += 1
        elif w == "him":
            new, k = "me", k + 1
        elif w in ("himself", "herself"):
            new, k = "myself", k + 1
        elif w == "his":
            new, k = "my", k + 1
        elif w == "her":
            new = "my" if nxt and nxt not in STOP else "me"  # "her knee", "help her", "for her to sit"
            k += 1
        else:
            if prev == "i" and w in THIRD_TO_FIRST:
                w = THIRD_TO_FIRST[w]                    # "my father is scared" -> "i am scared"
            out.append(w)
            k += 1
            continue
        if new in ("i", "i'm") and prev in BEFORE_I:
            out[-1] = BEFORE_I[prev]                     # "does my mother have" -> "do i have"
        out.append(new)
    mine = " ".join(out)
    return mine if mine != " ".join(words) else None


def match(plan_id: str | None, text: str) -> tuple[dict | None, str | None]:
    """The rule a typed question resolves to, and how it was matched (_match_any); none when the message,
    its words weighed together, is about another domain (3.61)."""
    if _term_asked(text):
        meaning = {i["key"]: i for i in intents_for(plan_id)}.get("word_meaning")
        if meaning is not None:
            return meaning, "definition"                 # "what does flexion mean" (3.72)
    chosen, how = _match_whole(plan_id, text)
    if chosen is not None and chosen["key"] in SCENES:
        point = _point_after_scene(plan_id, text, chosen)
        if point is not None:
            return point                                 # the point after a scene (3.88)
    mine = _as_if_mine(text) if chosen is None or chosen["key"] not in KEEP_FOR_OTHERS else None
    if mine:
        c2, h2 = _match_whole(plan_id, mine)
        if c2 is not None and c2 is not chosen and not c2.get("small_talk") and c2["key"] not in KEEP_FOR_OTHERS \
                and c2["key"] not in NO_CONTEXT and c2["key"] != "for_someone_else" \
                and (chosen is None or c2["key"] not in GENERAL_FOR_OTHERS) \
                and not (chosen is not None and how in ("keyword", "glossary")
                         and h2 in ("similar_question", "keyword_overlap")):
            chosen, how = c2, h2                         # the family member's own question (3.73)
    if chosen is None or chosen["key"] not in ABOUT_THE_PERSON:
        question = _question_after_story(text)
        if question:
            c2, h2 = _match_whole(plan_id, question)
            if c2 is not None and not c2.get("small_talk"):
                return c2, h2                            # the question after the story (3.70)
    return chosen, how


# 3.74 (numbers test, chat_numbers_set.py): what a number in the message measures, and the topic it calls
# for. A pain score sets how bad the pain is ("pain 8/10" is sharp pain, before: "pain 10/10" was read as a
# blood pressure); an age of 65 or more is the age limit ("my mother is 80" was the posture score, "80%"). The
# reading's topic wins only over a topic read loosely from the words around it (READING_WEAK).
PAIN_WORD_RE = re.compile(r"\b(?:pain|pains|painful|sakit|hurt|hurts|hurting|ache|aches|aching|sore|soreness|ngilu)\b")
PAIN_OUT_OF_RE = re.compile(r"\b(10|[0-9])\s*(?:/\s*10|out of 10|over 10|daripada 10)\b")
PAIN_LEVEL_RE = re.compile(r"\b(?:pain|sakit)\s*(?:level|score|scale|rating)?\s*(?:is\s*|of\s*)?(?:about\s*|like\s*|"
                           r"around\s*|maybe\s*)?(10|[0-9])\b(?!\s*(?:%|percent|min|mins|minute|minutes|hours?|hrs?|days?|"
                           r"weeks?|months?|years?|times|reps|sets|kg|cm|am|pm|o'?clock|\.\d))")
_UNITS_AFTER_AGE = (r"(?!\s*(?:kg|kgs|kilo|kilos|cm|m\b|%|percent|min|mins|minutes?|hours?|hrs?|days?|weeks?|months?|"
                    r"reps?|sets?|times|steps|km|lbs|pounds|feet|foot|ft|inch|inches|degrees?|bpm|/|\.\d|am\b|pm\b|'|\"))")
AGE_RE = re.compile(r"\b(?:i am|i'm|im|i m|age|aged|umur(?:\s+saya)?|usia|my age is|turned|turning|he is|she is|"
                    r"he's|she's|(?:my\s+)?(?:" + "|".join(sorted(PERSON_NOUNS)) + r")\s+is)\s+(?:only\s+|already\s+|"
                    r"almost\s+|nearly\s+)?(\d{1,3})(?!\d)" + _UNITS_AFTER_AGE)
AGE_OLD_RE = re.compile(r"\b(\d{1,3})\s*(?:years? old|yrs? old|y/o|yo|tahun)\b|\bin (?:my|his|her) ([1-9])0s\b")
BODY_RE = re.compile(r"\b(?:lost|gained|put on|turun|naik)\s+(?:about\s+|around\s+|almost\s+)?\d{1,2}(?:\.\d)?"
                     r"\s*(?:kg|kgs|kilo|kilos|kilograms|pounds|lbs)\b|"
                     r"\b(?:height|tinggi|i am|i'm|im)\s*(?:is\s*|saya\s*)?\d{3}(?:\.\d)?\s*(?:cm|centimetres?)\b|"
                     r"\b(?:height|tinggi)\s*(?:is\s*|saya\s*)?1?\d{2,3}\b|"
                     r"\b(?:i am|i'm|im)\s+\d{2,3}(?:\.\d)?\s*(?:kg|kgs|kilo|kilos|kilograms)\b|"
                     r"\b(?:i weigh|weigh|berat(?:\s+badan)?(?:\s+saya)?|weight)\s*(?:is\s*|about\s*)?\d{2,3}(?:\.\d)?"
                     r"\s*(?:kg|kgs|kilo|kilos)?\b")
WEATHER_RE = re.compile(r"\b(?:outside|outdoors?|weather|cuaca|room|sun|luar|today is|hari ni panas)\b")
TEMP_RE = re.compile(r"\b(?:temperature|temp|fever|suhu|demam)\b\D{0,15}?\b(3[4-9](?:\.\d)?|4[0-2](?:\.\d)?)(?!\d)")
WALK_RE = re.compile(r"\b\d[\d,]{2,6}\s*(?:steps|langkah)\b|"
                     r"\bwalk(?:ed|ing|s)?\s+(?:about\s+|around\s+|for\s+)?\d+(?:\.\d+)?\s*(?:km|kilometres?|kilometers?|"
                     r"miles?|min|mins|minutes|minit|hours?|hrs?|jam)\b|\bjalan(?:\s+kaki)?\s+\d+(?:\.\d+)?\s*km\b")
SLEEP_RE = re.compile(r"\b(?:slept|sleep|sleeping|tidur)\s+(?:(?:only|just|about|around|for|less than)\s+)*([1-5])\s*"
                      r"(?:hours?|hrs?|jam)\b|\b(?:only|just|got)\s+([1-5])\s*(?:hours?|hrs?|jam)\s+(?:of\s+)?"
                      r"(?:sleep|tidur)\b|\b([1-5])\s*(?:hours?|hrs?|jam)\s+(?:of\s+)?(?:sleep|tidur)\b")
DONE_RE = re.compile(r"\b(?:done|did|finished|completed|siap)\s+(?:it\s+|my\s+|the\s+)?\d{1,3}\s*(?:reps?|repetitions?|"
                     r"sets?|times|rounds|kali)\b(?!\s*(?:a|per|every|each)\s+(?:day|week))")
READING_WEAK = frozenset({"acknowledge", "clarify", "posture_result", "condition_advice", "safety", "equipment",
                          "how_to", "plan_exercises", "how_often", "profile_help", "for_someone_else", "treatment_nav",
                          "plan_and_reminders", "guardian_consent", "age_limit", "getting_started", "multiple_plans",
                          "health_readings", "word_meaning", "best_time"})
PAIN_KEYS = ("pain_mild", "pain_or_discomfort", "pain_sharp")
AGE_WEAK = frozenset({"acknowledge", "clarify", "posture_result", "safety", "for_someone_else", "guardian_consent",
                      "age_limit", "profile_help", "getting_started", "plan_exercises", "equipment"})


def _reading(text: str | None) -> tuple[str, frozenset] | None:
    """The topic a number in [text] calls for, and the topics it wins over; None without one."""
    low = " ".join((text or "").lower().replace("\u2019", "'").split())
    if PAIN_WORD_RE.search(low):
        m = PAIN_OUT_OF_RE.search(low) or PAIN_LEVEL_RE.search(low)
        if m and int(m.group(1)) > 0:
            n = int(m.group(1))
            return ("pain_sharp" if n >= 7 else "pain_or_discomfort" if n >= 4 else "pain_mild"), \
                READING_WEAK | {"pain_or_discomfort", "pain_mild", "pain_sharp", "difficulty", "exercise:*"}
    if oxygen_reading(low) is not None or pulse_reading(low) is not None or \
            (TEMP_RE.search(low) and not WEATHER_RE.search(low)):
        return "health_readings", READING_WEAK
    m = AGE_RE.search(low) or AGE_OLD_RE.search(low)
    a = int(m.group(1) or m.group(2) + "0") if m else 0
    if 5 <= a <= 110:
        if a >= 65:
            return "age_limit", AGE_WEAK
        if a < 18:
            return "guardian_consent", AGE_WEAK
        return "profile_help", frozenset({"acknowledge", "clarify", "posture_result", "guardian_consent", "age_limit"})
    if BODY_RE.search(low):
        return "profile_help", READING_WEAK
    if WALK_RE.search(low):
        return "other_activity", READING_WEAK
    if SLEEP_RE.search(low):
        return "tired", READING_WEAK
    if DONE_RE.search(low):
        return "session_done", frozenset({"acknowledge", "clarify", "plan_exercises", "how_to", "how_often",
                                          "equipment", "posture_result", "multiple_plans"})
    return None


def _match_whole(plan_id: str | None, text: str) -> tuple[dict | None, str | None]:
    """match() for the message as a whole."""
    core = [w for w in re.sub(r"[^a-z ]", " ", (text or "").lower()).split() if w not in _PARTICLE_FILLERS]
    if _yes_no(text):
        ack = {i["key"]: i for i in intents_for(plan_id)}.get("acknowledge")
        if ack is not None:
            return ack, "keyword"                        # "yes", "no", "nope", "tak" on their own (3.67)
    read = _reading(text)
    if read is not None:
        key, weak = read
        named = {i["key"]: i for i in intents_for(plan_id)}.get(key)
        chosen, how = _match_any(plan_id, text)
        kept = chosen is not None and key == "profile_help" and chosen["key"] == "guardian_consent" and how == "keyword"
        if named is not None and not kept and (chosen is None or chosen["key"] in weak
                                               or ("exercise:*" in weak and chosen["key"].startswith("exercise:"))):
            return named, "reading"                      # "pain 8/10", "i am 75", "spo2 96" (3.74)
        return chosen, how
    if len(core) <= 5 and WEIGHT_READING.search((text or "").lower()):
        profile = {i["key"]: i for i in intents_for(plan_id)}.get("profile_help")
        if profile is not None:
            return profile, "keyword"                    # "weight 70kg": the profile holds the weight (3.67)
    if len(core) <= 4 and (SUGAR_READING.search((text or "").lower()) or _bp_reading((text or "").lower())):
        advice = {i["key"]: i for i in intents_for(plan_id)}.get("condition_advice")
        if advice is not None:
            return advice, "keyword"                     # "sugar 3.2", "bp 120/80" (3.67)
    single = re.sub(r"(.)\1+", r"\1", core[0]) if len(core) == 1 else ""
    if single in ("med", "medic") or (len(single) >= 4 and single[0] == "m" and single not in dictionary()
                                      and typo_cost(single, "medic") <= 1.0):
        # "med" alone: medicine or medical help? (3.66); also "medci", "mdic", "medicccc" (3.89)
        helper = {i["key"]: i for i in intents_for(plan_id)}.get("med_help")
        if helper is not None:
            return helper, "keyword"
    chosen, how = _match_any(plan_id, text)
    if chosen is not None and not chosen.get("small_talk") and chosen["key"] != "cannot_do" \
            and _weighted_off_domain(text):
        return None, None
    return chosen, how


def _match_any(plan_id: str | None, text: str) -> tuple[dict | None, str | None]:
    """The rule a typed question resolves to, and how it was matched. When nothing, or only a loose
    likeness, matched, the respelled message is tried too (3.55: "hurs", "pasword", "bernfas")."""
    plain = " ".join(re.sub(r"[^a-z0-9' ]", " ", text.lower().replace("’", "'")).split())
    core = _without_fillers(plain)
    fillers = {w for f in LEADING_FILLERS + TRAILING_FILLERS for w in f.split()}
    removed = set(plain.split()) - set(core.split())
    if core and core != plain and (removed <= PURE_FILLERS or
                                   _recognised(plan_id, core, topics=True) >= _recognised(plan_id, plain, topics=True)):
        # "hi how often", "ok is it torn", "not helpful pls": the question without the greeting or the
        # word around it, when no topic word is lost ("doctor say no exercise" keeps "doctor").
        if not set(core.split()) <= fillers:
            c, h = match(plan_id, core)
            if c is not None:
                return c, h
    if set(plain.split()) <= fillers and len(plain.split()) > 1:
        # Only greetings and fillers ("hi doc", "sorry hi"): the small talk in it, "okay" and "say again?" last
        # ("ok thanks" is thanks, "sorry ok" okay, 3.86).
        found = [(c, h) for c, h in (_match_whole(plan_id, w) for w in plain.split())
                 if c is not None and (c.get("small_talk") or c["key"] in NO_CONTEXT)]
        if found:
            return min(found, key=lambda f: {"acknowledge": 1, "pardon": 2}.get(f[0]["key"], 0))
    chosen, how = _match(plan_id, text)
    if chosen is not None and not chosen.get("small_talk") and chosen["key"] != "cannot_do" and _off_domain(text):
        return None, None                        # about another domain: no rehabilitation topic guessed (3.57)
    again = respell(text)
    if _plain(again) != plain:
        # A slip was mended ("set remidner", "hw oftne"): the mended message wins when it matches more
        # of what was typed ("set reminder" over "set"), or when the message as typed matched nothing
        # or only loosely. A posture mistake's exact name stays ("shrugging" is not "struggling").
        c2, h2 = _match(plan_id, again)
        if how == "glossary":
            if h2 == "glossary" and c2 is not None and len(c2["key"]) > len(chosen["key"]):
                return c2, h2
            return chosen, how
        if c2 is not None and (chosen is None or how in ("similar_question", "keyword_overlap")
                               or _recognised(plan_id, again) >= _recognised(plan_id, text)
                               or (h2 == "glossary")):
            return c2, h2
    return chosen, how


@lru_cache(maxsize=1)
def _domain_words() -> tuple[frozenset, frozenset]:
    """(words of other domains the rules never use, words specific to rehabilitation), from CLINC150's
    training questions (other_domain_words.json, build_domain_words.py): a word used by at most 5 other
    domains and not by the rules is another domain's; a word of the rules' keywords used by at most 4
    other domains (4: "reminder"), and not one of the 349 used by 8 or more, is rehabilitation's."""
    path = Path(__file__).with_name("other_domain_words.json")
    if not path.exists():
        return frozenset(), frozenset()
    spread = json.loads(path.read_text(encoding="utf-8"))
    vocab = _respell_vocab()
    generic = {w for w, (s, _) in spread.items() if s >= 8}
    other = frozenset(w for w, (s, _) in spread.items() if s <= 5 and w not in vocab)
    kw = set()
    for i in rules()["intents"]:
        for k in i["keywords"]:
            kw.update(clean(k).split())
    for e in rules()["exercises"].values():
        for a in [e["name"]] + e["aliases"]:
            kw.update(clean(a).split())
    kw.update(w for p in rules().get("glossary", {}) for w in p.replace("_", " ").split())
    rehab = frozenset(w for w in kw if w not in generic and (w not in spread or spread[w][0] <= 4)
                      and len(w) >= 3 and w not in STOP)
    return other, rehab


# 3.61: the words' weights add up to more than OFF_DOMAIN_SCORE, or to more than OFF_DOMAIN_STRONG_SCORE with
# one word of weight OFF_DOMAIN_STRONG_WORD or more ("credit", "money", "car", "pay"). Measured: CLINC other
# domains 2443 -> 2961/3270, out-of-scope 745 -> 815/1100; the chatbot's own 995 questions and a 2 000-message
# sample of the random typing test unchanged (gate_variants, 20 Oct).
OFF_DOMAIN_SCORE = 7.0
OFF_DOMAIN_STRONG_WORD = 3.0
OFF_DOMAIN_STRONG_SCORE = 5.0
# Words clearly about rehabilitation besides the symptoms, body parts and exercise names: a message with
# one is never shut out by the word weights.
# 3.80: phrases that tie a message to this chatbot ("going on vacation, what about my plan").
ANCHOR_PHRASES = ("my plan", "my plans", "this plan", "the plan", "my treatment", "my exercises", "my exercise",
                  "the exercises", "my physio", "my physiotherapist", "pelan saya",
                  # 3.88: hot weather is this chatbot's topic too ("the weather is very hot today")
                  "very hot today", "so hot today", "weather is very hot", "weather is so hot", "weather is hot",
                  "hot weather", "cuaca panas")
ANCHOR_WORDS = frozenset({"exercise", "exercises", "exercising", "senaman", "bersenam", "physio",
                          "physiotherapy", "physiotherapist", "rehab", "rehabilitation", "posture", "reps",
                          "repetitions", "workout", "stretch", "stretching", "app", "reminder", "reminders"})


@lru_cache(maxsize=1)
def _domain_weights() -> dict:
    """{word stem: how much likelier in other domains' questions than in the rules} (build_domain_words)."""
    path = Path(__file__).with_name("domain_weights.json")
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


@lru_cache(maxsize=1)
def _rehab_anchors() -> tuple[frozenset, tuple]:
    """(symptom, body-part and rehabilitation words; exercise names and other names, whole: "heel raise",
    not "raise", which is also "raise my credit score")."""
    # "pressure" points to a symptom word beside it (3.62) but is no anchor: "tire pressure for my car".
    words = set(SIGN_WORDS) | {w for w in SIGN_CONTEXT if len(w) > 3 and w != "pressure"} | set(ANCHOR_WORDS)
    names = {clean(a) for e in rules()["exercises"].values() for a in [e["name"]] + e["aliases"]}
    names |= {clean(p) for p in ANCHOR_PHRASES}
    return frozenset(words - STOP), tuple(sorted(names, key=len, reverse=True))


def _weighted_off_domain(text: str) -> bool:
    """The message's words, weighed together, belong to another domain ("can you help me move money
    between accounts", "how can I raise my credit score", "a table for 3 at olive garden") and none is
    clearly about rehabilitation (3.61)."""
    weights = _domain_weights()
    if not weights:
        return False
    plain = clean(respell(text))
    words, names = _rehab_anchors()
    if set(plain.split()) & words or any(f" {n} " in f" {plain} " for n in names):
        return False
    # Weighed with its slips mended (3.62): "a new passwrd" is "password", a word of this chatbot.
    stems = {stem(w) for w in re.findall(r"[a-z][a-z']+", plain) if w not in STOP}
    found = [weights.get(s, 0.0) for s in stems]
    total = sum(found)
    return total > OFF_DOMAIN_SCORE or (bool(found) and max(found) >= OFF_DOMAIN_STRONG_WORD
                                         and total > OFF_DOMAIN_STRONG_SCORE)


def _off_domain(text: str) -> bool:
    """A word of another domain ("transfer", "flight", "nfl") and none of rehabilitation (3.57)."""
    other, rehab = _domain_words()
    words = set(_plain(text).split()) | set(_plain(respell(text)).split()) | set(clean(text).split())
    return bool(words & other) and not (words & rehab)


def _recognised(plan_id: str | None, text: str, topics: bool = False) -> int:
    """How much of a message the rules recognise: the matched keyword words over every rule (only the
    topics, without small talk, when [topics])."""
    return sum(keyword_match(text, i) for i in intents_for(plan_id) if not (topics and i.get("small_talk")))


# Words before or after a question that carry no topic of their own (3.55).
_LEADING_FILLER_RE = re.compile(r"^\s*(?:(?:ok|okay|sorry|hi|hello|hey|hai|hmm|erm|um|uh|oh|eh|doc|excuse me|"
                                r"please|pls)\b[\s,.!?]*)+", re.IGNORECASE)
LEADING_FILLERS = ["excuse me", "hi there", "hello there", "hi", "hello", "hey", "hai", "helo", "doc", "doctor",
                   "sorry", "erm", "erm,", "um", "uh", "hmm", "hm", "ok", "okay", "oh", "eh", "so", "and", "then",
                   "please", "pls", "plz", "assalamualaikum", "salam"]
TRAILING_FILLERS = ["lah", "la", "ah", "leh", "pls", "plz", "please", "ya", "yah", "huh", "eh", "ok", "thanks",
                    "thank you", "tq", "thx", "doc"]
# Words with no meaning of their own: always set aside around a question.
PURE_FILLERS = {"hmm", "hm", "erm", "um", "uh", "oh", "eh", "ok", "okay", "lah", "la", "ah", "leh", "ya", "yah",
                "huh", "pls", "plz", "please", "sorry", "excuse", "me", "hi", "hello", "hey", "hai", "helo"}


def _without_fillers(plain: str) -> str:
    words = plain.split()
    changed = True
    while changed and len(words) > 1:
        changed = False
        for f in LEADING_FILLERS:
            fw = f.split()
            if words[:len(fw)] == fw and len(words) > len(fw):
                words = words[len(fw):]
                changed = True
                break
        for f in TRAILING_FILLERS:
            fw = f.split()
            if words[-len(fw):] == fw and len(words) > len(fw):
                words = words[:-len(fw)]
                changed = True
                break
    return " ".join(words)


def _match(plan_id: str | None, text: str) -> tuple[dict | None, str | None]:
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
    if not any(h[2]["key"].startswith("exercise:") and h[1] >= 2 for h in hits):
        near = _near_exercise_name(text, intents)
        if near is not None and near[2]["key"] not in {h[2]["key"] for h in hits}:
            hits = hits + [near]
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
    if len(clean(text).split()) <= 3 and not exercises:
        # (3.54: not when an exercise is named: "open and close" is the exercise, not goodbye)
        small = [h for h in hits if h[2].get("small_talk")]
        small = [h for h in small if h[2]["key"] != "pardon"] or small   # "sorry ok", "sorry hi" (3.86)
        # (3.55: not when a longer topic phrase matched too: "not helpful" is a complaint, not thanks)
        if small and not any(h[1] >= max(s[1] for s in small) for h in hits if not h[2].get("small_talk")):                                    # "good morning", "help", "ok thanks"
            return max(small, key=lambda h: (h[0], h[1]))[2], "keyword"
    hits = _inside_exercise_names(text, hits)
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
    for better, general, only_if in PREFER_IF:
        if better in keys and general in keys and any(find_phrase(u, words) for u in only_if):
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


# 3.53 (Elwin, 14 Oct): a message made only of follow-up words ("how to", "why", "more", "how many",
# "is it safe", "kenapa", "macam mana") continues the previous answer's topic. A message with any other
# word has a topic of its own and is matched as usual; safety answers are checked before this.
FOLLOW_TRIGGERS = {
    "how", "why", "more", "explain", "elaborate", "details", "detail", "mean", "meaning", "again", "many",
    "long", "often", "safe", "next", "then", "where", "example", "steps", "step", "show", "tell", "info",
    "understand", "come", "really", "so", "huh", "clarify", "further", "repeat", "after", "about",
    "cara", "caranya", "macam", "camne", "kenapa", "apasal", "berapa", "lagi", "maksud", "faham", "ulang",
    "selamat", "lepas", "kat", "betul",
    # 3.94: "what else?", "is it serious?", "should i worry?" after an answer
    "else", "serious", "worry", "worried", "concern", "concerned", "normal", "bad", "teruk", "bahaya",
}
FOLLOW_FILLERS = {
    "to", "do", "i", "it", "this", "that", "one", "what", "about", "me", "you", "is", "does", "the", "a",
    "can", "please", "pls", "plz", "for", "and", "after", "like", "ah", "lah", "leh", "eh", "ya", "sure",
    "times", "time", "sorry", "dont", "don't", "do not", "say", "that's", "thats", "much", "should", "we",
    "nak", "buat", "mana", "apa", "tu", "ni", "ke", "kali", "lama", "tak", "ya", "boleh", "itu", "ini",
    "anything",
}
NO_CONTEXT = {"greeting", "thanks", "acknowledge", "goodbye", "language", "pardon", "how_are_you"}
# What a follow-up with nothing before it may still answer ("how often" -> how often; "steps" -> how to).
NO_CONTEXT_ANSWERS = {"how_to", "safety", "how_often", "plan_progress", "treatment_nav", "plan_exercises",
                      "pardon"}                          # "come again?" with nothing before it (3.66)
SAFETY_ANSWERS = {"red_flag", "crisis", "overdose", "poisoning"}


FOLLOW_FILLERS |= {"hmm", "hm", "ok", "okay", "oh", "erm", "um", "uh", "oo", "ooh", "hah", "pls", "now"}
# Short forms users type for follow-up words.
FOLLOW_SHORT = {"y": "why", "hw": "how", "howto": "how", "howtodo": "how", "u": "you", "wat": "what", "wht": "what", "abt": "about",
                "eg": "example", "mcm": "macam", "cmne": "camne", "camana": "macam", "knp": "kenapa",
                "npe": "kenapa", "brp": "berapa"}
_FOLLOW_VOCAB = sorted(FOLLOW_TRIGGERS | FOLLOW_FILLERS)


@lru_cache(maxsize=4096)
def _follow_word(w: str) -> str | None:
    """The follow-up word [w] stands for, allowing a short form, a doubled or dropped last letter and a
    close misspelling ("explane", "againn", "berap"); None when it is not one."""
    if w in FOLLOW_TRIGGERS or w in FOLLOW_FILLERS:
        return w
    if w in FOLLOW_SHORT:
        return FOLLOW_SHORT[w]
    single = re.sub(r"(.)\1+$", r"\1", w)                    # "againn" -> "again", "whyy" -> "why"
    if single in FOLLOW_TRIGGERS or single in FOLLOW_FILLERS:
        return single
    once = re.sub(r"(.)\1+", r"\1", w)                       # "whaat", "whhat" -> what (3.89)
    if once in FOLLOW_TRIGGERS or once in FOLLOW_FILLERS or once == "what":
        return once
    if len(w) >= 3:
        for v in _FOLLOW_VOCAB:                                 # "berap" -> "berapa", "explai" -> "explain"
            if len(v) == len(w) + 1 and v.startswith(w) and len(v) >= 4:
                return v
    if 3 <= len(single) <= 4:                               # "whst", "wgat", "wahttt" -> what (3.66)
        near = sorted((typo_cost(single, v), v) for v in FOLLOW_TRIGGERS | {"what"} if len(v) >= 3 and v[0] == w[0]
                      and abs(len(v) - len(single)) <= 1)
        if near and near[0][0] <= 0.5 and (len(near) == 1 or near[1][0] > near[0][0]):
            return near[0][1]
    if len(w) >= 5:
        best = process.extractOne(w, list(FOLLOW_TRIGGERS), scorer=fuzz.ratio)
        if best and best[1] >= 80 and best[0][0] == w[0]:
            return best[0]                                      # "explane" -> "explain"
    return None


def pure_follow_up(text: str | None) -> bool:
    """Only follow-up words, at least one of them a trigger, at most six words."""
    if not text:
        return False
    # Digits stay as words, so "what does 65% mean" is a question of its own.
    words = re.sub(r"[^a-z0-9' ]", " ", text.lower().replace("’", "'")).split()
    if not words or len(words) > 6:
        return False
    core = [w for w in words if w not in ("lah", "ah", "leh", "huh", "pls", "ya", "lor", "meh", "hor", "ke")]
    if core and core[-1] != "sure" and typo_cost(core[-1], "sure") <= 1.0 and core[-1][0] == "s":
        core[-1] = "sure"                                # "are you syre"
    if " ".join(core) in ("are you sure", "you sure", "r u sure", "are u sure", "sure or not", "sure ah"):
        return True                                      # "are you sure?" about the last answer (3.66)
    known = [_follow_word(w) for w in words]
    if known and all(k in FOLLOW_FILLERS for k in known) and [k for k in known if k not in _PARTICLE_FILLERS] == ["what"]:
        return True                                      # "what?", "um what": not "what can you do" (3.66)
    return all(k is not None for k in known) and any(k in FOLLOW_TRIGGERS for k in known)


_PARTICLE_FILLERS = {"hmm", "hm", "ok", "okay", "oh", "erm", "um", "uh", "ah", "lah", "leh", "eh", "ya", "pls",
                     "plz", "please", "huh"}


# Laptop pass 12: Chinese and Tamil messages were all unrecognised, emergencies included. The rules
# read English and Malay; a few emergency words in other scripts are still caught, and anything else
# mostly in another script gets this answer instead of "not recognised".
OTHER_SCRIPT_CRISIS = ["想死", "自杀", "自殺", "不想活", "轻生", "輕生", "தற்கொலை"]
OTHER_SCRIPT_RED_FLAGS = ["胸口痛", "胸痛", "心口痛", "呼吸困难", "呼吸困難", "喘不过气", "喘不過氣", "头晕", "頭暈",
                          "晕倒", "暈倒", "昏倒", "中风", "中風", "நெஞ்சு வலி", "மூச்சு திணறல்", "மயக்கம்"]
OTHER_SCRIPT_ANSWER = ("I can only understand English and Bahasa Melayu. Saya hanya faham Bahasa Inggeris dan "
                       "Bahasa Melayu. In an emergency call 999 (kecemasan: hubungi 999). If you are thinking of "
                       "harming yourself, call Befrienders KL 03-7627 2929 (24 hours).")


def _other_script(text: str) -> bool:
    letters = [ch for ch in text if ch.isalpha()]
    return bool(letters) and sum(not ch.isascii() for ch in letters) / len(letters) > 0.5


def _safety_again(base: dict, kind: str, r: dict) -> dict:
    """The safety answer given just before, again, for "why?" or "what do I do?" after it."""
    answer, title = {"red_flag": (r["red_flag_answer"], "Urgent safety advice"),
                     "crisis": (r["crisis_answer"], "You are not alone"),
                     "overdose": (OVERDOSE_ANSWER, "Too many pills"),
                     "poisoning": (POISON_ANSWER, "Swallowed a chemical")}[kind]
    return {**base, "answer": answer, "category": kind, "title": title, "is_matched": True,
            "matched_by": "follow_up", "follow_ups": [], "notes": [], "action": None}


INVISIBLE_RE = re.compile("[\u200b\u200c\u200d\u200e\u200f\u2060\ufeff\u00ad]")
# Accents and marks stacked on letters ("café", "Zalgo" text), not the vowel signs of other scripts (3.60).
COMBINING_RE = re.compile("[\u0300-\u036f\u1ab0-\u1aff\u1dc0-\u1dff\u20d0-\u20ff\ufe20-\ufe2f]")
MAX_TOPIC_CHARS = 1500


# Code and markup (Big List of Naughty Strings, 20 Oct): SQL, shell, HTML/script tags, templates, paths.
# 3.58: taken out of the message, and what is left is read when it still has three words ("/$( my knee is
# not painful anymore, can I stop the plan?"); "select an exercise from my plan" is not SQL.
CODE_RE = re.compile(r"(?i)(?:\bdrop\s+table\s*\w*|\bselect\s+\*\s+from\s+\w+|\binsert\s+into\s+\w+|"
                     r"\bunion\s+(?:all\s+)?select\b|\bexec\s|\$\(|\$\{[^}]*\}?|`[^`]*`|</?[a-z][^>]*>|"
                     r"<(?:script|iframe|img|svg|object|embed|style|body|input|form|meta|link)\b[^>]*|"
                     r"\{\{|\}\}|\{%|%\}|/etc/\w*|/dev/\w*|/tmp/\w*|\brm\s+-rf\b|\w+\.\w+\([^)]*\)|"
                     r"\b\w+\(\s*(?:'[^']*'|\"[^\"]*\")\s*\)|%[0-9a-f]{2}|;\s*--|\bjndi:\S*|"
                     r"\(\)\s*\{[^}]*\}?|@\{\[[^\]]*\]\}|[;{]\s*(?:touch|echo|cat|rm|wget|curl|ls|sudo|sh|bash)\s+[/$~.-][^;}]*)")
WIDE_GAP_RE = re.compile(r"\s{2,}")
DOTS_RE = re.compile(r"(?<=[^\W_])(?:\.{2,}|\u2026+)(?=[^\W_])")       # also beside digits: "bathroom...2...years"


# 3.66 (the Manglish test, chat_manglish_set.py): whole-message Malaysian English shapes in English order,
# before anything reads the message. Only with something before the shape word: "can or not?" and "how
# ah?" alone continue the previous answer.
_PARTICLES = r"(?:\s+(?:lah|leh|lor|meh|hor|ah|one|ya|huh))*[\s?!.]*"
MANGLISH = [(re.compile(r"^(?P<x>.+?)\s+cannot" + _PARTICLES + "$"), "i cannot {x}"),
            (re.compile(r"^can\s+(?P<x>.+?)\s+(?:or\s+not|anot)" + _PARTICLES + "$"), "can i {x}"),
            (re.compile(r"^(?P<x>.+?)\s+(?:can\s+)?(?:or\s+not|anot)" + _PARTICLES + "$"), "can i {x}"),
            (re.compile(r"^(?P<x>.+?)\s+can\s+ah" + _PARTICLES + "$"), "can i {x}"),
            (re.compile(r"^(?P<x>.+?)\s+(?:ok|okay|safe)\s+(?:or\s+not|anot)" + _PARTICLES + "$"), "is it ok to {x}"),
            (re.compile(r"^(?:then\s+how|how\s+ah)\s+(?P<x>.+?)" + _PARTICLES + "$"), "what should i do {x}"),
            (re.compile(r"^how\s+come\s+(?P<x>.+?)" + _PARTICLES + "$"), "why {x}")]


def _manglish(text: str) -> str:
    """"get up from the floor cannot" -> "i cannot get up from the floor", "exercise can or not" -> "can i
    exercise", "how come ..." -> "why ...": for messages of up to 15 words."""
    low = text.lower().strip()
    if len(low.split()) > 15:
        return text
    for pattern, english in MANGLISH:
        m = pattern.match(low)
        words = [w for w in re.findall(r"[a-z']+", m.group("x"))] if m else []
        if not [w for w in words if w not in _PARTICLE_FILLERS and w not in ("lor", "meh", "hor", "one")]:
            continue                                     # "how ah lah", "how ah ?": nothing but particles
        if m and m.group("x").strip(" ,") and m.group("x").split()[-1] not in (
                "cannot", "can", "not", "i", "really", "just", "still", "also", "already", "me", "you"):
            if english == "can i {x}" and m.group("x").split()[-1] in ("ok", "okay", "safe"):
                continue                                 # "walk ok or not": the next shape
            return english.format(x=m.group("x").strip(" ,"))
    return text


# 3.69 (the voice typing test, chat_voice_set.py: 79.3%): speech-to-text writes words that sound alike -
# "i dont want two live anymore", "chess pain", "my need hurts", "heal rays", "set two stand", "my store so
# low", "my plant". Each is put back only where the words around it make the meaning plain ("I need help"
# and "a store" stay), before the safety checks read the message.
_VERBS = (r"(?:live|die|end|kill|hurt|do|use|stand|walk|exercise|sit|start|stop|eat|sleep|breathe|record|log|"
          r"change|get|go|be|see|know|make|take|keep|move|lift|raise|bend|finish|continue|rest|find|update|"
          r"upload|open|reset|delete|add|ask|call|talk|come|wake|the|my|this|side|front)")
_BODY = (r"(?:pain|pian|pane|hurts?|hertz|tight|tightness|pressure|ache|aches|aching|sakit|sore|swollen|feels?|"
         r"is|was|very|so|really|kind|bit|quite|heavy)")
VOICE_FIXES = [(re.compile(p), r) for p, r in [
    (r"\b(want|wants|how|need|needs|going|have|has|got|able|try|trying|like|start|ready|wish|used|time|easy|hard|"
     r"unable|way|reason|nothing|place) (?:two|too) (" + _VERBS + r")\b", r"\1 to \2"),
    (r"\b(?:two|too) (" + _VERBS + r")\b", r"to \1"),
    (r"\btied of\b", "tired of"), (r"\bdead tied\b", "dead tired"),
    (r"\bchess(?= " + _BODY + r"\b)", "chest"), (r"\b(my|the|in my) chess\b", r"\1 chest"),
    (r"\bhertz\b", "hurts"), (r"\bdizzie\b", "dizzy"), (r"\bdizy\b", "dizzy"),
    (r"\b(my|posture|pasture|poster|your|low|high|good|bad) store\b", r"\1 score"),
    (r"\bstore (?=\d|so\b|is\b|mean|low|high|only)", "score "),
    (r"\b(shoulder|knee|hip|heel|soldier|exercise|exercises|elbow|wrist|squat|my last|average) store\b", r"\1 score"),
    (r"\b(?:pasture|poster)(?= (?:score|store|result|results|check|analysis|accuracy|is|was|feedback)\b)", "posture"),
    (r"\b(my|the|this|a|new|tukar|your|current|which|what|that|one|both|another|each|core|knee|shoulder|hip|different|"
     r"hand|balance|strength|rehab|treatment|exercise) (?:plane|plant)(s?)\b",
     r"\1 plan\2"),
    (r"\b(?:plane|plant)(?= (?:for|am i|is|was|says)\b)", "plan"),
    (r"\bremainders?\b", lambda m: "reminders" if m.group(0).endswith("s") else "reminder"),
    (r"\bpass word\b", "password"),
    (r"\b(a|the|my|without|on|from|which|what|sturdy|kitchen|of|to|use|using) cheer\b", r"\1 chair"),
    (r"\bcheer stand\b", "chair stand"), (r"\btan them\b", "tandem"),
    (r"\bheals? (?:rays|raise|raises|race|races)\b", "heel raise"), (r"\bheel (?:rays|race|races)\b", "heel raise"),
    (r"\b(arm|arms|front|side|lateral|shoulder|soldier|leg|calf) (?:rays|race|races)\b", r"\1 raises"),
    (r"\b(?:set|sit) (?:two|too|to) stand\b", "sit to stand"), (r"\bset ups\b", "sit ups"),
    (r"\b(my|left|right|both|frozen|the|your) soldiers?\b", r"\1 shoulder"),
    (r"\bsoldiers?(?= (?:pain|pane|hurt|hurts|raise|raises|abduction|flexion|exercise|is|ache|press)\b)", "shoulder"),
    (r"\bshould a(?= (?:pain|pane|raise|raises|hurts|exercise|shrug|store|score|abduction|flexion)\b)", "shoulder"),
    (r"\b(my|left|right|both|the|your) needs?(?= (?:hurts?|hertz|is|feels?|pain|pane|swollen|swells|gives|clicks|"
     r"cracks|bends|aches|sore|still|keeps|very|so|goes|go|better|in|cannot|can't|went)\b)", r"\1 knee"),
    (r"\bhe'?ll (?:rays|raise|raises|race|races)\b", "heel raise"),
    (r"\b(my|the|chest|knee|back|neck|shoulder|hip|no|in|more|sharp|bad|any|much) pane\b", r"\1 pain"),
    (r"\b(what|lose|losing|my|body|lift|heavier|light|lighter|which|gained|gain|put on|lost|gaining) wait\b",
     r"\1 weight"),
    (r"\bwait loss\b", "weight loss"),
    (r"\b(feel|feels|feeling|so|very|is|are|legs|arms|too|getting|felt) week\b", r"\1 weak"),
    (r"\bblood pleasure\b", "blood pressure"), (r"\bextra sizes\b", "exercises"), (r"\bextra size\b", "exercise"),
    (r"\b(?:war|wall) bush up\b", "wall push up"), (r"\bwar push up\b", "wall push up"), (r"\bbush ups?\b", "push up"),
    (r"\bglue bridge\b", "glute bridge"), (r"\bflection\b", "flexion"),
    (r"\b(my|your|the|on) tows\b", r"\1 toes"), (r"\b(heel to) tow\b", r"\1 toe"),
    (r"\b(so|very|just|feel|feels|feeling|i'm|im|am|too|always|really) tied\b", r"\1 tired"),
    (r"\bhep\b", "hip"), (r"\bsquads\b", "squats"), (r"\bsquad\b", "squat"),
    (r"\b(can't|cant|cannot|hard to|unable to|to|short of|hardly|barely|not|i|should i|while i|can) breed\b",
     r"\1 breathe"),
    (r"\brist\b", "wrist"), (r"\bfizzy oh\b", "physio"), (r"\broute in\b", "routine"), (r"\blefting\b", "lifting"),
    (r"\bcalve\b", "calf"), (r"\bpain full\b", "painful"), (r"\bswallen\b", "swollen"),
    (r"\b(the|a|to the|against the|on the|near the|from the) war\b", r"\1 wall"),
    (r"\bhe'?ll(?= (?:raise|raises|rays|race|races|to|too|two|lift)\b)", "heel"),
    (r"\bheal (?:to|too|two) (?:toe|tow)\b", "heel to toe"), (r"\bheel (?:too|two) (toe|tow)\b", "heel to toe"),
    (r"\b(my|your|the|both) heals\b", r"\1 heels"), (r"\bheals(?= (?:go|lift|up|down|off)\b)", "heels"),
    (r"\brays(?= (?:my|your|both|the|arms?|legs?|heels?)\b)", "raise"),
    (r"\b(how many|many|more|less|fewer|of|the|my|extra) wraps\b", r"\1 reps"),
    (r"\bnee\b", "knee"), (r"\bnees\b", "knees"),
    (r"\b(feel|feels|feeling|is|be|so|very|bit|quite|still|are|was|just|really|abit|getting) (?:soar|saw)\b",
     r"\1 sore"),
    (r"\b(?:soar|saw)(?= (?:muscles?|knee|knees|back|legs?|arms?|shoulders?|neck|feet|ankles?)\b)", "sore"),
    (r"\b(cannot|can't|cant|to|can|hard to|unable to|try to) left\b", r"\1 lift"),
    (r"\b(the|my) risk (?=exercise|extension|pain|hurts|lift|curl)", r"\1 wrist "),
]]


def _voice(text: str) -> str:
    """Sound-alike words from voice typing put back (VOICE_FIXES); the text unchanged when none is there."""
    low = text.lower()
    fixed = low
    for pattern, english in VOICE_FIXES:
        fixed = pattern.sub(english, fixed)
    return text if fixed == low else fixed


def _tidy(text: str) -> str:
    """Spacing typed by accident or for effect, made plain before anything reads the message (3.58):
    "sesak  nafas" is "sesak nafas", "terima...kasih" is "terima kasih", "h e l p" is "help" and
    "i   f e e l   d i z z y" is "i feel dizzy" (wider gaps between the words)."""
    toks = text.split()
    if len(toks) >= 3 and sum(len(w) == 1 and w.isalpha() for w in toks) >= 0.8 * len(toks):
        parts = WIDE_GAP_RE.split(text.strip())
        text = " ".join("".join(p.split()) for p in parts) if len(parts) > 1 else "".join(toks)
    return " ".join(DOTS_RE.sub(" ", text).split())


# Links, e-mail addresses and @handles carry no question of their own.
LINK_RE = re.compile(r"(?i)(https?://\S+|www\.\S+|\S+@\S+\.\S+|(?<!\w)@\w+|\b[\w-]+\.(com|org|net|my|io)\b\S*)")


# 3.66 (Elwin's reports): "999" on its own is a call for help, as are "call 999", "911", "112", "ambulance".
EMERGENCY_CALL_RE = re.compile(r"^\W*(?:(?:call|dial|phone|telefon|panggil)\s+)?(?:999|991|911|112|ambulance|"
                               r"an ambulance|ambulans|emergency|kecemasan)(?:\W*(?:now|please|pls|tolong|cepat|"
                               r"lah|ah|leh|huh|ya|lor|meh|hor|for me|me))*\W*$")


WEIGHT_READING = re.compile(r"\b(?:my\s+)?(?:body\s+)?(?:weight|berat)\s*(?:is\s*|now\s*|badan\s*)?\d{2,3}"
                            r"(?:\.\d+)?\s*(?:kg|kgs|kilo|kilos|kilogram)?\b")
YES_NO = {"yes", "yeah", "yup", "yep", "ya", "yes la", "no", "nope", "nah", "tak", "tidak", "takde", "sure", "betul",
          "boleh", "ok", "okay"}
# A body part on its own (3.67): asked what about it, never guessed ("shoulder" was the shoulder flexion,
# "knee" a diagnosis, "my hip" a greeting).
BODY_PART_ALONE = {"knee": "knee", "knees": "knees", "lutut": "knee", "back": "back", "lower back": "lower back",
                   "belakang": "back", "pinggang": "lower back", "waist": "lower back", "shoulder": "shoulder",
                   "shoulders": "shoulders", "bahu": "shoulder", "hip": "hip", "hips": "hips", "pinggul": "hip",
                   "wrist": "wrist", "ankle": "ankle", "elbow": "elbow", "siku": "elbow", "neck": "neck",
                   "leher": "neck", "leg": "leg", "legs": "legs", "kaki": "leg", "arm": "arm", "arms": "arms",
                   "hand": "hand", "hands": "hands", "tangan": "arm", "foot": "foot", "feet": "feet",
                   "thigh": "thigh", "calf": "calf", "fingers": "fingers", "finger": "finger"}


def _plain_words(text: str | None) -> list[str]:
    """The message's words, stretched letters shortened ("kneeee", "yesss", "takkkk")."""
    low = re.sub(r"([a-z])\1{2,}", r"\1", (text or "").lower())
    return re.sub(r"[^a-z ]", " ", low).split()


def _yes_no(text: str | None) -> bool:
    """Only yes or no ("ya", "nope", "tak", "sure lah", "Npoe pls!"): answered as okay (3.67)."""
    words = [w for w in _plain_words(text) if w not in _PARTICLE_FILLERS or w == "ya"]
    if not words or len(words) > 2:
        return False
    def yes_no(w):
        return w in YES_NO or re.sub(r"(.)\1+", r"\1", w) in YES_NO or (
            len(w) >= 4 and any(typo_cost(w, v) <= 0.5 for v in YES_NO if len(v) >= 4 and v[0] == w[0]))
    return all(yes_no(w) for w in words)


def _body_part_alone(text: str | None) -> str | None:
    for source in (text, respell(text) if text else None):
        words = [w for w in _plain_words(source) if w not in _PARTICLE_FILLERS and w not in ("my", "the", "saya", "i")]
        if 1 <= len(words) <= 2 and " ".join(words) in BODY_PART_ALONE:
            return BODY_PART_ALONE[" ".join(words)]
    return None


def _emergency_call(text: str) -> bool:
    """Only an emergency number or a call for an ambulance, as typed, stretched or misspelt."""
    low = re.sub(r"([a-z])\1{2,}", r"\1", text.lower())          # "ambulanceeee"
    if EMERGENCY_CALL_RE.match(low) or EMERGENCY_CALL_RE.match(respell(low)):
        return True
    first, _, rest = low.strip().partition(" ")                  # "disl 999", "cal 999" (3.89)
    word = re.sub(r"[^a-z]", "", first)
    return bool(rest) and any(typo_cost(word, v) <= 1.0 for v in ("call", "dial", "phone")) \
        and bool(EMERGENCY_CALL_RE.match("call " + rest))


def _shown(typed: str | None) -> str | None:
    """A short message (1-3 words, 40 characters) as it can be echoed back, else None."""
    shown = " ".join((typed or "").split()).strip(" ?!.,").replace('"', "'")
    if not shown or len(shown) > 40 or len(shown.split()) > 3 or not any(ch.isalpha() for ch in shown):
        return None
    return shown


def _typed_by_accident(shown: str) -> bool:
    """Random letters ("kdjsb", "ij"): no word in it is a word or a short form the rules know."""
    words = re.findall(r"[a-z']+", shown.lower())
    known = vocabulary()
    return bool(words) and not any(
        w in known or w in dictionary() or w in rare_words() or w in SHORT_WORDS_TYPED or w in FOLLOW_SHORT
        or respell(w) != w for w in words)


def _not_recognised(typed: str | None, r: dict) -> str:
    """FR500_22 "Question not recognised", with a short message echoed back (Elwin's reports, 11 Oct:
    "what do you mean by "going"?"), and random letters said to look typed by accident."""
    shown = _shown(typed)
    if shown is None:
        return r["not_recognised"]
    if _typed_by_accident(shown):
        return (f'Question not recognised: "{shown}" looks like it may have been typed by accident. Please '
                f"choose a topic below, or type your question.")
    return f'Question not recognised: what do you mean by "{shown}"? Please choose a topic below, or ask it another way.'


def _nothing_to_read(text: str) -> bool:
    """No letters in any script and no emoji the rules read ("!@#$%", "12345", "???")."""
    if any(ch.isalpha() for ch in text):
        return False
    return not any(e in text for e in EMOJI)


MALAY_GRAMMAR = set("""saya aku awak kita kami dia nak hendak boleh tak tidak ke ini itu dan yang untuk dengan apa
macam mana bila kenapa ada sudah dah di dari pun lah""".split())


def _word_list(text: str) -> bool:
    """20 words or more and hardly a word of grammar ("i", "my", "the", "is", "how", "saya", "nak"): words
    pasted or typed at random, not a question (3.58). The safety checks have read it already."""
    words = re.findall(r"[^\W\d_]+", text.lower())
    grammar = sum(w in STOP or w in MALAY_GRAMMAR for w in words)
    return len(words) >= 20 and grammar * 20 < len(words)      # under 1 in 20 (a stray "a", 3.60)


def reply(plan_id: str | None, category: str | None, text: str | None,
          conditions: list[str] | None = None, limitations: list[str] | None = None,
          risk_level: str | None = None, local_time: tuple[int, int] | None = None,
          previous_category: str | None = None, restriction: str | None = None) -> dict:
    r = rules()
    typed = text                                         # as typed, to echo back (3.66)
    if text:
        text = unicodedata.normalize("NFC", COMBINING_RE.sub("", unicodedata.normalize("NFD", text)))
        text = _tidy(INVISIBLE_RE.sub("", text))           # zero-width characters (3.57), spacing (3.58)
        text = _manglish(_voice(text))                     # "get up from the floor cannot" (3.66), "chess pain" (3.69)
    by_key = {i["key"]: i for i in intents_for(plan_id)}
    base = {"categories": _listing(categories_for(plan_id, restriction)), "rules_version": r["version"]}
    rest = r.get("restrictions", {}).get(restriction or "")

    if text and any(w in text for w in OTHER_SCRIPT_CRISIS):
        return {**base, "answer": r["crisis_answer"], "category": "crisis", "title": "You are not alone",
                "is_matched": True, "matched_by": "crisis", "follow_ups": [], "notes": [], "action": None}
    if text and any(w in text for w in OTHER_SCRIPT_RED_FLAGS):
        return {**base, "answer": r["red_flag_answer"], "category": "red_flag", "title": "Urgent safety advice",
                "is_matched": True, "matched_by": "red_flag", "follow_ups": [], "notes": [], "action": None}
    if text and _other_script(text):
        return {**base, "answer": OTHER_SCRIPT_ANSWER, "category": "language", "title": "Languages",
                "is_matched": True, "matched_by": "other_script", "follow_ups": [], "notes": [], "action": None}
    if crisis(text):
        told = r.get("crisis_answer_other") if _crisis_about_other(text) else None
        return {**base, "answer": told or r["crisis_answer"], "category": "crisis", "title": "You are not alone",
                "is_matched": True, "matched_by": "crisis", "follow_ups": [], "notes": [], "action": None}
    if overdose(text):
        return {**base, "answer": OVERDOSE_ANSWER, "category": "overdose", "title": "Too many pills",
                "is_matched": True, "matched_by": "overdose", "follow_ups": [], "notes": [], "action": None}
    if poisoning(text):
        return {**base, "answer": POISON_ANSWER, "category": "poisoning", "title": "Swallowed a chemical",
                "is_matched": True, "matched_by": "poisoning", "follow_ups": [], "notes": [], "action": None}
    if red_flag(text) or (text and _emergency_call(text)):
        return {**base, "answer": r["red_flag_answer"], "category": "red_flag", "title": "Urgent safety advice",
                "is_matched": True, "matched_by": "red_flag", "follow_ups": [], "notes": [], "action": None}

    chosen, how = None, None
    if text:
        text = LINK_RE.sub(" ", text)                     # links and addresses are not the question (3.57)
        if CODE_RE.search(text):                          # code out; the rest is read if it has words (3.58)
            left = CODE_RE.sub(" ", text)
            text = left if len(re.findall(r"[^\W\d_]{2,}", left)) >= 3 else ""
    if text and (_nothing_to_read(text) or _word_list(text)):
        text = ""                                         # nothing to answer: "not recognised" below (3.57)
    elif text and len(text) > MAX_TOPIC_CHARS:
        text = text[:MAX_TOPIC_CHARS]
    # A short follow-up continues the previous answer (3.53); a safety answer is given again.
    if not category and previous_category and previous_category not in NO_CONTEXT and pure_follow_up(text):
        if previous_category in SAFETY_ANSWERS:
            return _safety_again(base, previous_category, r)
        prev = by_key.get(previous_category)
        if prev is not None and not prev.get("small_talk"):
            chosen, how = prev, "follow_up"
    if chosen is None and not category and pure_follow_up(text) and "clarify" in by_key:
        # Nothing before it to continue: the general how-to and safety answers still fit ("show me how
        # to do it", "is it safe"); anything else asks for more rather than guessing.
        guess, guessed_how = match(plan_id, text)
        if guess is not None and guess["key"] in NO_CONTEXT_ANSWERS:
            chosen, how = guess, guessed_how             # "how often", "what next": questions of their own
        else:
            chosen, how = by_key["clarify"], "clarify"
    part = None if (chosen is not None or category) else _body_part_alone(text)
    if part and "clarify" in by_key:
        chosen, how = by_key["clarify"], "body_part"
    if chosen is not None:
        pass                                           # the follow-up above
    elif category and category in by_key:
        chosen, how = by_key[category], "category"
    elif text and text.strip():
        chosen, how = match(plan_id, text)
        followed = follow_up(text, chosen, previous_category, by_key)
        if followed is not None:
            chosen, how = followed, "follow_up"

    if chosen is None:
        return {**base, "answer": _not_recognised(typed, r), "category": None, "title": None, "is_matched": False,
                "matched_by": None, "follow_ups": [], "notes": [], "action": None}
    if rest and _restricted(chosen["key"], rest):
        # A plan, a recording or plan reminders: not for this user (3.49). Say why and where to go.
        return {**base, "answer": rest["answer"], "category": "age_limit", "title": rest["title"], "is_matched": True,
                "matched_by": how, "follow_ups": [], "notes": [], "action": rest["action"]}

    mentioned = conditions_in(text) if chosen["key"] in ("condition_advice", "safety") else []
    all_conditions = list(dict.fromkeys((conditions or []) + mentioned))
    # Time first: "rest now, it is late" matters more than the condition reminders that follow.
    notes = time_notes(chosen, local_time, all_conditions, limitations)
    notes += tailor_notes(chosen, all_conditions, limitations, risk_level)
    if rest and (chosen["key"] in rest["note_on"] or chosen["key"].startswith("exercise:")):
        notes.insert(0, rest["note"])
    base_answer = chosen["answer"]
    if chosen["key"] == "word_meaning" and _term_asked(text):
        base_answer = r["terms"][_term_asked(text)]
    elif chosen["key"] == "clarify" and how == "body_part":
        part = _body_part_alone(text)
        base_answer = (f"What would you like to know about your {part}? For example: \"my {part} hurts\", "
                       f"\"exercises for my {part}\" or \"is it safe to exercise my {part}?\". You can also pick "
                       f"a topic below.")
    elif chosen["key"] == "clarify" and _shown(typed):
        # "what", "how" with nothing before them: ask what they mean, with their words (Elwin's reports).
        base_answer = f'What do you mean by "{_shown(typed)}"? Could you tell me a bit more?' + \
            base_answer.split("?", 1)[1]
    # A condition named in the question is answered on its own (phone test, 8 Oct: with the profile's
    # conditions added the answer ran to 230 words); otherwise the profile's conditions are used.
    asked_first = mentioned if any(c in r.get("condition_detail", {}) for c in mentioned) else all_conditions
    details = [r["condition_detail"][c] for c in asked_first if c in r.get("condition_detail", {})]
    if chosen["key"] == "condition_advice" and details:
        # A different answer for each condition (Table 4.2.2): the patient's own conditions first.
        unlisted = set(r.get("unlisted_conditions", []))
        closing = r.get("condition_closing_other") if mentioned and \
            all(c in unlisted for c in asked_first if c in r["condition_detail"]) else None
        base_answer = "\n\n".join(details) + "\n\n" + (closing or r["condition_closing"])
    answer = base_answer + ("\n\n" + "\n".join(f"Note: {n}" for n in notes) if notes else "")
    follow = [by_key[k] for k in chosen.get("follow_ups", []) if k in by_key]
    return {**base, "answer": answer, "category": chosen["key"], "title": chosen["title"], "is_matched": True,
            "matched_by": how, "follow_ups": _listing(follow), "notes": notes, "action": chosen.get("action"),
            "more_actions": chosen.get("more_actions", [])}
