"""Messages with a number in them (21 Oct): a pain score ("pain 8/10"), an oxygen, pulse or temperature
reading, an age ("i am 75"), a weight or height, steps or distance walked, hours slept, repetitions done,
how often, and calories. Each family builds messages from templates with random numbers, and the topics a
right answer can have follow from the number (a pain of 7 or more is sharp pain; oxygen of 92% or less is
urgent). evaluate_chat_numbers.py runs it.
"""
import random

PLANS = ["88c1e725-4b64-5689-a70d-47d37b2fcd7e"]
N = None
PARTS = ["knee", "back", "shoulder", "hip", "neck", "leg", "arm", "ankle", "wrist", "lower back"]
URGENT = {"red_flag", "crisis", "overdose", "poisoning"}


def _pain(rng):
    n = rng.randint(1, 10)
    part = rng.choice(PARTS)
    template = rng.choice(["pain {n}/10", "pain is {n}/10", "my {part} pain is {n} out of 10", "pain level {n}",
                           "pain score is {n}", "{part} pain {n}/10 after the exercise",
                           "the pain is about {n} out of 10", "sakit {n}/10", "pain {n} over 10",
                           "i would rate the pain {n}/10", "{n}/10 pain in my {part}", "my {part} hurts, {n} out of 10",
                           "pain like {n}/10 during the exercise", "{part} pain level {n}",
                           "on a scale of 1 to 10 my pain is {n}"])
    text = template.format(n=n, part=part)
    want = {"pain_sharp"} if n >= 7 else {"pain_or_discomfort", "pain_sharp"} if n >= 4 else \
        {"pain_mild", "pain_or_discomfort"}
    if part == "neck" and "{part}" in template:
        want |= {"neck_not_covered"}                     # the neck answer: not covered by the app's plans
    return text, want


def _oxygen(rng):
    v = rng.randint(84, 100)
    text = rng.choice(["oxygen {v}", "my oxygen is {v}%", "spo2 {v}", "o2 {v}", "oxygen level {v} percent",
                       "the oximeter says {v}", "oksigen {v}", "my oxygen saturation is {v}", "spo2 {v}% after exercise",
                       "my sats are {v}", "oxygen {v}% is it ok"]).format(v=v)
    return text, {"red_flag"} if v <= 92 else {"health_readings"}


def _heart(rng):
    h = rng.randint(45, 190)
    text = rng.choice(["heart rate {h}", "my pulse is {h}", "pulse {h} after exercise", "heartbeat {h} bpm", "nadi {h}",
                       "my heart rate is {h} is it ok", "hr {h}", "{h} bpm after the exercise",
                       "resting heart rate {h}"]).format(h=h)
    return text, {"red_flag"} if h >= 150 else {"health_readings"}


def _temperature(rng):
    t = rng.randint(355, 400) / 10
    text = rng.choice(["temperature {t}", "my temp is {t}", "fever {t}", "suhu {t}", "body temperature {t} degrees",
                       "temp {t}c", "i have a fever of {t}", "my temperature is {t} can i exercise"]).format(t=t)
    return text, {"tired", "health_readings"} if t >= 38 or "fever" in text else {"health_readings"}


def _age(rng):
    a = rng.choice([rng.randint(10, 17), rng.randint(18, 64), rng.randint(65, 95), rng.randint(65, 95)])
    template = rng.choice(["i am {a}", "i'm {a} years old", "im {a} this year", "age {a}", "my age is {a}",
                           "i am {a} years old can i still do this", "umur saya {a}", "i am {a} yrs old",
                           "my mother is {a}", "my father is {a} years old", "i just turned {a}"])
    text = template.format(a=a)
    want = {"age_limit"} if a >= 65 else {"guardian_consent"} if a < 18 else {"profile_help", "safety"}
    if template.startswith("my "):
        want |= {"for_someone_else"}
    return text, want


def _body(rng):
    text = rng.choice(["i lost {k} kg", "i gained {k}kg", "i put on {k} kg", "i am {c}cm", "height {c}",
                       "my height is {c} cm", "i weigh {w} kg", "berat saya {w}kg", "weight {w}", "i'm {c} cm tall",
                       "lost {k} kilos this month"]).format(k=rng.randint(1, 12), c=rng.randint(140, 185),
                                                            w=rng.randint(40, 120))
    return text, {"profile_help"}


def _walking(rng):
    template = rng.choice(["i walked {s} steps today", "walked {d} km this morning", "i walk {m} minutes every morning",
                           "jalan kaki {d} km", "{s} steps today", "did {s} steps", "i walked {d} km is that enough"])
    text = template.format(s=rng.choice([800, 2000, 3500, 5000, 8000, 10000, 12000]), d=rng.randint(1, 8),
                           m=rng.choice([10, 15, 20, 30, 45, 60]))
    return text, {"other_activity", "how_often"} if "minutes" in template else {"other_activity"}


def _sleep(rng):
    text = rng.choice(["i slept only {h} hours", "only {h} hours sleep last night", "tidur {h} jam je", "slept {h} hrs",
                       "i only got {h} hours of sleep"]).format(h=rng.randint(2, 5))
    return text, {"tired"}


def _done(rng):
    text = rng.choice(["done {n} reps", "finished {n} sets", "i did {n} reps today", "completed {n} reps",
                       "did it {n} times already", "i finished my exercise", "done for today",
                       "finished today's exercise", "i have done my exercises", "dah siap senaman"]).format(
        n=rng.randint(2, 20))
    return text, {"session_done"}


def _often(rng):
    text = rng.choice(["can i exercise {n} times a day", "is {m} minutes enough", "can i do it {n} times a week",
                       "{m} minutes a day ok?", "how about {n} times a day", "should i exercise {n} days a week"]).format(
        n=rng.randint(2, 6), m=rng.choice([5, 10, 15, 20, 30, 45, 60]))
    return text, {"how_often"}


def _calories(rng):
    text = rng.choice(["how many calories did i burn", "how many calories does this burn", "does it count calories",
                       "calories burned today", "does the app count my steps", "how many steps should i walk a day",
                       "can these exercises help me burn fat", "berapa kalori"])
    return text, {"calories", "other_activity"} if "walk" in text else {"calories"}


FAMILIES = {"pain_score": _pain, "oxygen": _oxygen, "heart_rate": _heart, "temperature": _temperature, "age": _age,
            "weight_height": _body, "walking": _walking, "sleep": _sleep, "done": _done, "how_often": _often,
            "calories": _calories}


def build(seed: int, n: int = 2000) -> list[dict]:
    rng = random.Random(seed)
    names = sorted(FAMILIES)
    cases = []
    for _ in range(n):
        fam = rng.choice(names)
        text, want = FAMILIES[fam](rng)
        if rng.random() < 0.3:
            text = rng.choice(["hi ", "doc ", "ok ", "um ", ""]) + text + rng.choice(["", "?", " pls", " lah", "."])
        cases.append({"kind": fam, "plan_id": rng.choice(PLANS), "text": text, "want": sorted(map(str, want)),
                      "urgent": want <= URGENT})
    return cases
