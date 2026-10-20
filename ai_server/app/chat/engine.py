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
    return one if one in SHORT_WORDS else re.sub(r"(.)\1{2,}", r"\1\1", w)
NEGATORS = {"no", "not", "without", "never", "don't", "dont", "didn't", "didnt", "haven't", "havent", "isn't",
            "isnt", "wasn't", "wasnt", "nor"}
# Everyday words mapped onto the words the rules use.
SYNONYMS = {"pane": "pain", "panes": "pains", "workout": "exercise", "workouts": "exercises", "train": "exercise", "training": "exercising",
            "lift": "raise", "lifts": "raises", "lifting": "raising", "lifted": "raised", "high": "height",
            "physio": "physiotherapist", "doc": "doctor", "vid": "video", "pic": "photo"}
# Common Malay words patients mix into English (Malaysian users). Single words; phrases are in
# MALAY_PHRASES. Body-part and symptom words map to the English the rules (and red flags) know.
MALAY = {"apa": "what", "saya": "i", "aku": "i", "lemah": "weak", "mula": "start", "nak": "want", "tukar": "change", "sesuai": "best", "untuk": "for", "malam": "night", "pagi": "morning", "petang": "evening", "tengahari": "afternoon", "boleh": "can",
         "buat": "do", "senaman": "exercise", "bersenam": "exercise", "lutut": "knee", "bahu": "shoulder",
         "kaki": "leg", "tangan": "arm", "pinggang": "back", "belakang": "back", "letih": "tired",
         "penat": "tired", "pening": "dizzy", "dada": "chest", "tak": "not", "tidak": "not", "dapat": "get",
         "kod": "code", "lupa": "forgot", "bila": "when", "masa": "time", "tolong": "please", "bengkak": "swollen",
         "pitam": "fainted", "senget": "crooked", "herot": "crooked", "pelat": "slurred", "kebas": "numb",
         "lumpuh": "paralysed",
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
                 "terhantuk kepala": "hit my head", "kepala terhentak": "hit my head"}
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
                     "ystd": "yesterday", "ytd": "yesterday", "msg": "message", "pic": "picture", "vid": "video"}
# Malay as it is texted (3.59, the random typing test: "sya jatuh semalam", "xleh bangun", "jatuh td").
SHORT_WORDS_TYPED.update({
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
                      "my exercises", "my exercise list", "exercises today", "today's exercises",
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
                      "when can stop", "when to stop", "when stop", "point of this exercise", "point of this plan",
                      "point of doing", "what is the point of", "what's the point of this",
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
                 "pening", "sleepy", "cold", "hot", "lonely", "stressed", "great", "nothing", "like"}


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
        sign = _sign_reading(was)
        if not sign or near[k] & SIGN_WORDS:
            continue
        if mended[k] in known and typo_cost(was, mended[k]) < typo_cost(was, sign):
            continue                                     # a closer word of the rules: "frint arm raise" is front
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
               ("kt", "laluan"): ("kata", "laluan")}


def _malay_two(typed: list[str], mended: list[str]) -> list[str]:
    malay = set(COMMON_MALAY) | set(MALAY) | MALAY_SIGN_WORDS | {w for p in MALAY_PHRASES for w in p.split()}
    if not any(x in malay for m in mended for x in m.split()):
        return mended
    out = list(mended)
    bare = [w[:-3] if w.endswith("lah") and len(w) > 3 else w for w in typed]     # "mtlah", "drlah", "pglah"
    for k, w in enumerate(bare):
        as_typed = typed[k]
        nxt = bare[k + 1] if k + 1 < len(bare) else ""
        if (w, nxt) in MALAY_PAIRS:
            out[k], out[k + 1] = MALAY_PAIRS[(w, nxt)]
            continue
        if k and (bare[k - 1], w) in MALAY_PAIRS:
            continue
        if w == "x" and nxt.isalpha() and not (k and bare[k - 1].isdigit()):
            out[k] = "tak"                               # "x boleh", "x nak": tak (3.64)
            continue
        if w != as_typed and w in SHORT_WORDS_TYPED:
            out[k] = SHORT_WORDS_TYPED[w]                # "pglah", "lglah"
            continue
        if w.startswith("x") and len(w) >= 3 and mended[k] == as_typed:
            rest = SHORT_WORDS_TYPED.get(w[1:]) or MALAY_TWO.get(w[1:]) or _malay_texted(w[1:]) or (
                w[1:] if w[1:] in COMMON_MALAY or w[1:] in MALAY_SIGN_WORDS else None)
            if rest:
                out[k] = "tak " + rest                   # "xnk", "xbole", "xbngn"
                continue
        if w == "dr" and k and typed[k - 1] in ("bunuh", "bnh"):
            out[k] = "diri"                              # "bunuh dr": suicide
        elif w in MALAY_TWO and mended[k] == as_typed:
            nxt = typed[k + 1] if k + 1 < len(typed) else ""
            if (w == "ms" and nxt in ("", "pain", "sakit")) or (w == "ml" and k and bare[k - 1].isdigit()):
                out[k] = w                               # "i have ms": MS; "500 ml"
            else:
                out[k] = MALAY_TWO[w]
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
PREFER_UNLESS = [# 3.50: "I have cancer, can I exercise?" is condition advice; "do I have cancer?" stays diagnosis
                 ("condition_advice", "diagnosis", ["do i have", "could it be", "could this be", "is it cancer",
                                                    "is this cancer", "might be", "do you think", "am i getting",
                                                    "be cancer", "lump", "signs of", "symptoms of"]),
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
    """The words just before position i make it a question about what to do ("what if i can't get up")."""
    before = f" {' '.join(words[max(0, i - 3):i])} "
    return any(before.endswith(f" {h} ") for h in HYPOTHETICAL)


# Laptop pass 9: a time word counts only in the fall's own sentence ("my mum fell years ago; today she
# started the plan" is an old fall), and "earlier in my life" is not "earlier today".
# 3.62: also a comma before a new person ("she has fallen, she fell last year too": two falls, one now).
CLAUSE_BREAK = re.compile(r"[.;!?]+|\bbut\b|\btapi\b|,\s*(?=(?:i|she|he|my|mum|mom|mother|dad|father|"
                          r"saya|dia|mak|emak|ayah|abah|nenek|atuk)\b)")
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
                "dia", "saya", "did", "so", "then", "now", "sekali"}
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
HISTORY_EVENTS = {"heart attack"}
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
    while k >= 0 and (c[k] in ("just", "baru", "has", "had", "have", "suddenly") or c[k] in times):
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


def high_bp(text: str) -> bool:
    for sys_, dia in BP_READING.findall(text):
        s_, d_ = int(sys_), int(dia)
        if 70 <= s_ <= 280 and 40 <= d_ <= 180 and s_ > d_ and (s_ >= 180 or d_ >= 110):
            return True
    return False


def crisis(text: str | None) -> bool:
    """Thoughts of suicide or self-harm: checked before everything else, also with slips mended
    ("suicdie", "i wsnt to die", "tired of livign", 3.55), and with an unknown word read as the word of
    a crisis phrase it is one slip from ("better if i was goe", "i wsant to die", 3.62)."""
    if _also_respelled(_crisis, text):
        return True
    mended = _phrase_mend(text, "crisis")
    return mended is not None and _crisis(mended)


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
             "double warfarin", "extra warfarin", "warfarin twice", "double my blood thinner",
             # PC safety pass 16: three or more times a dose, and extra sleeping pills. A regular medicine
             # taken twice by mistake stays a pharmacist question (decided in laptop pass 6).
             "three times my dose", "3 times my dose", "four times my dose", "4 times my dose",
             "five times my dose", "5 times my dose", "three times the dose", "3 times the dose", "triple dose",
             "triple my dose", "extra sleeping pills", "extra sleeping tablets",
             # Malay puts the amount after the medicine ("makan ubat terlalu banyak")
             "ubat terlalu banyak", "terlebih makan ubat", "terlebih ubat", "ubat berlebihan", "telan ubat banyak"]
OD_BOXES = ["medicine box", "pill box", "pillbox", "medicine cabinet", "kotak ubat"]
OVERDOSE_ANSWER = ("Taking too many pills can be dangerous even if you feel fine now. Call 999 or go to the nearest "
                   "emergency department now, and take the medicine packets with you; do not wait for symptoms. "
                   "If this was on purpose, or you are thinking of harming yourself, you are not alone: "
                   "Befrienders KL 03-7627 2929 (24 hours) or Talian HEAL 15555 (8 am to midnight).")
# Household chemicals swallowed (laptop pass 7): Dettol, bleach, floor cleaner, pesticide...
POISONS = ["dettol", "clorox", "bleach", "floor cleaner", "cleaner", "pesticide", "insecticide", "racun",
           "kerosene", "minyak tanah", "antifreeze", "weed killer", "detergent", "toilet cleaner", "lysol",
           # PC safety pass 16
           "cleaning liquid", "cleaning fluid", "cleaning product", "dishwashing liquid", "pencuci", "sabun cecair"]
POISON_VERBS = {"drank", "drink", "drinks", "swallowed", "swallow", "ate", "eaten", "minum", "telan", "took", "had",
                "terminum", "tertelan"}
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
        ws = tuple(p.split())
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
    None when there is no such phrase (3.62: "better if i was goe", "blajed out", "peeat hidup")."""
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
                    or typo_cost(w, p) > (1.0 if len(p) < 6 else 1.5)):
                continue
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
    if _red_flag_typed(text):
        return True
    mended = _phrase_mend(text, "red_flags")             # one unknown word of a warning-sign phrase (3.62)
    return mended is not None and _red_flag_typed(mended)


def _red_flag_typed(text: str) -> bool:
    again = respell(text)
    base = again if _plain(again) != _plain(text) else text
    # "ok fell over this morning", "sorry jatuh tahun lepas, tapi tadi lagi": a filler in front is not
    # who fell (3.56).
    bare = _LEADING_FILLER_RE.sub("", base)
    return _red_flag(base) or (bare != base and bool(bare.strip()) and _red_flag(bare))


def _red_flag(text: str) -> bool:
    if high_bp(text) or low_sugar(text) or high_sugar(text):
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


def conditions_in(text: str | None) -> list[str]:
    if not text:
        return []
    words = clean(text).split()
    found = list(dict.fromkeys(code for phrase, code in CONDITION_WORDS.items() if find_phrase(phrase, words)))
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


def match(plan_id: str | None, text: str) -> tuple[dict | None, str | None]:
    """The rule a typed question resolves to, and how it was matched (_match_any); none when the message,
    its words weighed together, is about another domain (3.61)."""
    chosen, how = _match_any(plan_id, text)
    if chosen is not None and not chosen.get("small_talk") and _weighted_off_domain(text):
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
        # Only greetings and fillers ("hi doc", "sorry hi"): the small talk in it.
        for w in plain.split():
            c, h = _match(plan_id, w)
            if c is not None and c.get("small_talk"):
                return c, h
    chosen, how = _match(plan_id, text)
    if chosen is not None and not chosen.get("small_talk") and _off_domain(text):
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
}
FOLLOW_FILLERS = {
    "to", "do", "i", "it", "this", "that", "one", "what", "about", "me", "you", "is", "does", "the", "a",
    "can", "please", "pls", "plz", "for", "and", "after", "like", "ah", "lah", "leh", "eh", "ya", "sure",
    "times", "time", "sorry", "dont", "don't", "do not", "say", "that's", "thats", "much", "should", "we",
    "nak", "buat", "mana", "apa", "tu", "ni", "ke", "kali", "lama", "tak", "ya", "boleh", "itu", "ini",
}
NO_CONTEXT = {"greeting", "thanks", "acknowledge", "goodbye", "language"}
# What a follow-up with nothing before it may still answer ("how often" -> how often; "steps" -> how to).
NO_CONTEXT_ANSWERS = {"how_to", "safety", "how_often", "plan_progress", "treatment_nav", "plan_exercises"}
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
    if len(w) >= 3:
        for v in _FOLLOW_VOCAB:                                 # "berap" -> "berapa", "explai" -> "explain"
            if len(v) == len(w) + 1 and v.startswith(w) and len(v) >= 4:
                return v
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
    known = [_follow_word(w) for w in words]
    return all(k is not None for k in known) and any(k in FOLLOW_TRIGGERS for k in known)


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
DOTS_RE = re.compile(r"(?<=[^\W\d_])(?:\.{2,}|\u2026+)(?=[^\W\d_])")


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
    if text:
        text = unicodedata.normalize("NFC", COMBINING_RE.sub("", unicodedata.normalize("NFD", text)))
        text = _tidy(INVISIBLE_RE.sub("", text))           # zero-width characters (3.57), spacing (3.58)
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
        return {**base, "answer": r["not_recognised"], "category": None, "title": None, "is_matched": False,
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
            "matched_by": how, "follow_ups": _listing(follow), "notes": notes, "action": chosen.get("action"),
            "more_actions": chosen.get("more_actions", [])}
