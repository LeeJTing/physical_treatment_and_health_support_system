"""Medicines by name (21 Oct): the brand and generic names people in Malaysia take (pain, diabetes, blood
pressure, cholesterol, blood thinners, heart, steroids, asthma, thyroid, gout, bones, sleep and mood,
Parkinson's, traditional remedies). Three families: a plain mention ("i'm on amlodipine, can i exercise" -> the
medicines answer), too many taken ("i took 30 amlodipine" -> overdose, urgent), and a normal dose ("i took my
metformin this morning" -> the medicines answer, not an emergency). evaluate_chat_medicines.py runs it.
"""
import random

PLAN = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"
DRUGS = """panadol paracetamol ibuprofen aspirin naproxen diclofenac voltaren arcoxia etoricoxib celebrex celecoxib
ponstan tramadol codeine gabapentin pregabalin lyrica metformin glucophage gliclazide diamicron sitagliptin januvia
empagliflozin jardiance dapagliflozin forxiga insulin lantus mixtard novorapid amlodipine norvasc losartan cozaar
perindopril coversyl lisinopril enalapril hydrochlorothiazide bisoprolol atenolol metoprolol propranolol nifedipine
frusemide furosemide lasix spironolactone atorvastatin lipitor simvastatin rosuvastatin crestor warfarin clopidogrel
plavix rivaroxaban xarelto apixaban eliquis isosorbide digoxin prednisolone prednisone dexamethasone ventolin
salbutamol seretide symbicort thyroxine levothyroxine carbimazole allopurinol colchicine alendronate fosamax zolpidem
stilnox diazepam valium sertraline fluoxetine escitalopram amitriptyline levodopa madopar""".split()
MENTION = ["i take {d}", "i'm on {d}", "i am on {d} can i exercise", "can i exercise after taking {d}",
           "{d} before exercise ok?", "does {d} affect my exercise", "saya makan {d}", "my doctor gave me {d}",
           "i forgot to take my {d}", "{d} makes me tired", "should i take {d} before or after exercise"]
TOO_MANY = ["i took {n} {d}", "i swallowed {n} {d} just now", "my mother took {n} {d} by mistake",
            "accidentally took {n} {d}", "my father swallowed {n} {d} tablets", "dah telan {n} biji {d}"]
NORMAL = ["i took my {d} this morning", "took 1 {d} after breakfast", "i take 1 {d} every day",
          "already took my {d} today"]


def build(seed: int, n: int = 2000) -> list[dict]:
    rng = random.Random(seed)
    cases = []
    for _ in range(n):
        d = rng.choice(DRUGS)
        kind = rng.choice(["mention", "mention", "too_many", "normal"])
        if kind == "mention":
            text, want = rng.choice(MENTION).format(d=d), {"medication"}
        elif kind == "too_many":
            text, want = rng.choice(TOO_MANY).format(d=d, n=rng.randint(10, 40)), {"overdose"}
        else:
            text, want = rng.choice(NORMAL).format(d=d), {"medication", "acknowledge"}
        cases.append({"kind": kind, "plan_id": PLAN, "drug": d, "text": text, "want": sorted(want),
                      "urgent": kind == "too_many"})
    return cases
