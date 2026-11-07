"""Symptoms by their kind (21 Oct): a cramp or spasm, pins and needles, stiffness, a stitch in the side, a
pulled muscle, soreness the day after, and a joint that locks - told of different body parts, in English,
Malay and Manglish, half typed messily. evaluate_chat_symptoms.py runs it.
"""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_user_style_set import messy  # noqa: E402

PLAN = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"
LIMBS = ["calf", "leg", "foot", "thigh", "hamstring", "back", "arm", "hand", "toes"]
FAMILIES = {
    "cramp": ({"cramp"}, ["i got a cramp in my {p}", "{p} cramp at night", "my {p} cramped during the exercise",
                          "muscle spasm in my {p}", "kejang otot", "cramp in my {p} what to do", "my back is locked",
                          "charley horse in my {p}", "my {p} keeps cramping", "kaki kejang malam tadi"]),
    "pins_needles": ({"pins_needles"}, ["pins and needles in my {p}", "tingling in my {p}", "my {p} fell asleep",
                                        "my {p} feels tingly after sitting", "rasa semut semut kat kaki",
                                        "pins and needles after the exercise", "my {p} tingles when i sit long"]),
    # numbness ("kebas") stays a warning sign, even after sitting: the cautious answer is right too
    "numb_sitting": ({"pins_needles", "red_flag"}, ["kaki kebas lepas duduk lama", "my {p} went numb after sitting"]),
    "stiffness": ({"stiffness"}, ["my {p} feels stiff in the morning", "my joints are stiff", "morning stiffness",
                                  "stiff {p} after resting", "badan kaku pagi pagi", "sendi kaku", "my muscles are tight",
                                  "my {p} feels tight", "so stiff today can i exercise", "stiffness after sitting long"]),
    "stitch": ({"stitch"}, ["stitch in my side when walking", "i got a stitch during the exercise", "side stitch",
                            "side ache when i march", "senak bila jalan", "sharp stitch under my ribs when walking fast"]),
    "muscle_strain": ({"muscle_strain"}, ["pulled hamstring", "i pulled a muscle in my {p}", "i think i strained my {p}",
                                          "muscle strain in my {p}", "pulled my calf yesterday", "otot tertarik",
                                          "tweaked my {p} doing the exercise", "strained muscle what should i do"]),
    "doms": ({"pain_mild"}, ["doms", "my muscles are sore the day after", "sore the next day after exercise",
                             "delayed onset muscle soreness", "legs sore 2 days after the exercise"]),
    "locking": ({"joint_noise"}, ["my knee locks", "my knee gets stuck", "knee locking when i stand up",
                                  "my knee catches sometimes", "my joint locks up"]),
}


def build(seed: int, n: int = 2000) -> list[dict]:
    rng = random.Random(seed)
    names = sorted(FAMILIES)
    cases = []
    for _ in range(n):
        fam = rng.choice(names)
        want, texts = FAMILIES[fam]
        base = rng.choice(texts).format(p=rng.choice(LIMBS))
        text = messy(base, rng) if rng.random() < 0.5 else base
        cases.append({"kind": fam, "plan_id": PLAN, "base": base, "text": text, "want": sorted(want)})
    return cases
