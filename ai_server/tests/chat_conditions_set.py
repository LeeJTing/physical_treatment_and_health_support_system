"""Health conditions the health profile does not list (21 Oct): gout, dementia, epilepsy, a hernia, frozen
shoulder, carpal tunnel, migraine, anaemia, a thyroid problem, varicose veins, a disc problem, and others, in
English and Malay, said by the user or of a family member. The answer should be the condition advice with
that condition's own words (its "marker" appears in the answer), or the answer the condition already has
elsewhere (depression -> low mood, whiplash -> neck problems). evaluate_chat_conditions.py runs it.
"""
import random

PLAN = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"
ADVICE = {"condition_advice"}
# name typed -> (topics a right answer can have, a word the answer must contain)
CONDITIONS = {
    "gout": (ADVICE, "gout"), "gaut": (ADVICE, "gout"), "uric acid": (ADVICE, "gout"),
    "dementia": (ADVICE, "dementia"), "alzheimer's": (ADVICE, "dementia"), "nyanyuk": (ADVICE, "dementia"),
    "epilepsy": (ADVICE, "epilepsy"), "hernia": (ADVICE, "hernia"), "burut": (ADVICE, "hernia"),
    "scoliosis": (ADVICE, "scoliosis"), "plantar fasciitis": (ADVICE, "plantar fasciitis"),
    "frozen shoulder": (ADVICE, "frozen shoulder"), "carpal tunnel": (ADVICE, "carpal tunnel"),
    "tennis elbow": (ADVICE, "tennis elbow"), "lupus": (ADVICE, "lupus"), "fibromyalgia": (ADVICE, "fibromyalgia"),
    "obesity": (ADVICE, "overweight"), "anaemia": (ADVICE, "anaemia"), "anemia": (ADVICE, "anaemia"),
    "kurang darah": (ADVICE, "anaemia"), "thyroid problem": (ADVICE, "thyroid"), "hypothyroidism": (ADVICE, "thyroid"),
    "migraine": (ADVICE, "migraine"), "glaucoma": (ADVICE, "glaucoma"), "cataract": (ADVICE, "eye"),
    "varicose veins": (ADVICE, "varicose veins"), "dvt": (ADVICE, "clot"), "spinal stenosis": (ADVICE, "spine"),
    "herniated disc": (ADVICE, "disc"), "slipped disc": (ADVICE | {"diagnosis"}, "disc"),
    "spondylosis": (ADVICE, "spine"), "bunions": (ADVICE, "bunion"), "flat feet": (ADVICE, "flat feet"),
    "menopause": (ADVICE, "menopause"), "high cholesterol": (ADVICE, "cholesterol"), "kolesterol": (ADVICE, "cholesterol"),
    "fatty liver": (ADVICE, "fatty liver"), "sleep apnea": (ADVICE, "sleep apnoea"),
    "heart failure": (ADVICE, "heart"), "angina": (ADVICE | {"red_flag"}, "heart"),
    "atrial fibrillation": (ADVICE, "heart"), "lemah jantung": (ADVICE, "heart"),
    "neuropathy": (ADVICE, "neuropathy"), "ankylosing spondylitis": (ADVICE, "ankylosing spondylitis"),
    "bursitis": (ADVICE, "tendon"), "tendinitis": (ADVICE | {"diagnosis"}, "tendon"),
    "trigger finger": (ADVICE, "tendon"), "cerebral palsy": (ADVICE, "physiotherapist"),
    "polio": (ADVICE, "physiotherapist"), "asma": (ADVICE, "asthma"),
    # answered elsewhere already
    "depression": ({"low_mood"}, ""), "anxiety": ({"low_mood"}, ""), "long covid": ({"muscle_loss"}, ""),
    "whiplash": ({"neck_not_covered"}, ""), "vertigo": ({"red_flag"}, ""),
}
MINE = ["i have {c}", "i have {c} can i exercise", "is it safe to exercise with {c}", "can i do the exercises with {c}",
        "what exercises are good for {c}", "{c}", "i got {c}, is this plan ok for me", "saya ada {c}",
        "my doctor said i have {c}", "exercise with {c} ok?", "{c} can exercise or not", "i was diagnosed with {c}"]
THEIRS = ["my mother has {c}", "my father has {c}, can he do this", "my husband has {c} is it safe for him"]


def build(seed: int, n: int = 2000) -> list[dict]:
    rng = random.Random(seed)
    names = sorted(CONDITIONS)
    cases = []
    for _ in range(n):
        c = rng.choice(names)
        want, marker = CONDITIONS[c]
        theirs = rng.random() < 0.2
        text = rng.choice(THEIRS if theirs else MINE).format(c=c)
        if theirs:
            want = want | {"for_someone_else"}
        if "doctor said" in text and want == {"low_mood"}:
            want = want | {"doctor_said"}                # "doctor_said" is kept over low mood (PREFER)
        cases.append({"plan_id": PLAN, "condition": c, "text": text, "want": sorted(want), "marker": marker,
                      "theirs": theirs})
    return cases
