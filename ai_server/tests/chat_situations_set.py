"""Everyday situations around exercising (21 Oct): haze, fasting in Ramadan, rain and cold rooms, travelling,
an operation coming or just done, periods, alcohol and smoking, and a massage, blood donation or vaccine
just before - in English, Malay and Manglish, typed messily now and then. The topics a right answer can have
are listed per family. evaluate_chat_situations.py runs it.
"""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_user_style_set import messy  # noqa: E402

PLAN = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"
FAMILIES = {
    "haze": ({"haze"}, ["can i exercise during haze", "the haze is bad today", "jerebu teruk boleh senam luar?",
                        "air quality is bad, can i still exercise", "api reading 150 today", "is it ok to exercise when hazy",
                        "haze season exercise indoors ok?", "air pollution very bad today", "jerebu boleh exercise?",
                        "the air is smoky outside"]),
    "fasting": ({"fasting"}, ["can i exercise while fasting", "puasa boleh senam?", "ramadan exercise",
                              "when to exercise during ramadan", "exercise before buka puasa ok?",
                              "can i do my exercises after iftar", "fasting month can i continue my plan",
                              "i am fasting today, should i skip", "exercise before sahur", "bulan puasa boleh buat senaman?"]),
    "weather": ({"weather"}, ["raining today can i exercise", "it is raining", "hujan hari ni boleh senam?",
                              "too cold to exercise", "my room is very cold", "aircond room ok?",
                              "can i exercise in an air conditioned room", "rainy day exercise",
                              "cold weather exercise ok", "sejuk sangat boleh senam?"]),
    "travel": ({"travel"}, ["i'm travelling this week", "i'm on holiday", "going on vacation, what about my plan",
                            "balik kampung next week can i continue", "can i exercise in a hotel room",
                            "i will be overseas for two weeks", "long flight tomorrow, what about my exercises",
                            "outstation for work this week",
                            "cuti sekolah balik kampung", "travelling can i still do the exercises"]),
    "surgery": ({"surgery"}, ["i am going for surgery next week", "after my operation can i continue",
                              "can i exercise before my operation", "had surgery last month when can i start",
                              "post op can i do the exercises", "i will have an operation soon",
                              "lepas pembedahan boleh senam?", "after the surgery when can i exercise again",
                              "having surgery on friday", "just had an operation"]),
    "period": ({"period"}, ["i'm menstruating can i exercise", "period pain can exercise?", "can i exercise on my period",
                            "having my period today", "datang bulan boleh senam?", "menstrual cramps should i exercise",
                            "haid boleh buat senaman?", "senggugut teruk", "is it ok to exercise during menstruation",
                            "on my period and very tired"]),
    "alcohol_smoking": ({"alcohol_smoking"}, ["can i exercise after drinking alcohol", "i smoke", "i drank beer last night",
                                              "can i smoke after exercise", "i am a smoker can i do this",
                                              "merokok boleh senam?", "hangover today should i exercise",
                                              "i want to quit smoking", "i vape is that ok", "had some wine at dinner"]),
    "after_treatment": ({"after_treatment"}, ["can i exercise after massage", "can i exercise after urut",
                                              "after acupuncture can i exercise", "can i exercise after blood donation",
                                              "can i exercise after vaccine", "after covid vaccine exercise ok?",
                                              "i just donated blood", "got my flu shot today", "lepas urut boleh senam?",
                                              "had cupping today can i exercise"]),
}


def build(seed: int, n: int = 2000) -> list[dict]:
    rng = random.Random(seed)
    names = sorted(FAMILIES)
    cases = []
    for _ in range(n):
        fam = rng.choice(names)
        want, texts = FAMILIES[fam]
        base = rng.choice(texts)
        text = messy(base, rng) if rng.random() < 0.5 else base
        cases.append({"kind": fam, "plan_id": PLAN, "base": base, "text": text, "want": sorted(want)})
    return cases
