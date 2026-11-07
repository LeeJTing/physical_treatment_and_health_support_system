"""Voice typing (21 Oct): older users often speak their message and the phone writes what it heard -
sound-alike words ("knee pain" -> "need pain", "heel raise" -> "heal rays", "sit to stand" -> "set two stand",
"shoulder" -> "soldier", "posture score" -> "pasture score", "reminder" -> "remainder"), no punctuation,
sometimes "um" or a first capital. Made from the chatbot's English questions; the answer must stay the same.
The sound-alikes are listed here by hand, not taken from the engine. evaluate_chat_voice.py runs it.
"""
import random
import re

# word -> what speech-to-text may write instead (sounds the same or nearly)
SOUND_ALIKE = {
    "knee": ["need", "nee"], "knees": ["needs", "nees"], "heel": ["heal", "he'll"], "heels": ["heals"],
    "raise": ["rays", "race"], "raises": ["races", "raises"], "sit": ["set"], "to": ["two", "too"],
    "shoulder": ["soldier", "should a"], "shoulders": ["soldiers"], "wrist": ["rist", "risk"],
    "ankle": ["ankel"], "hip": ["hep"], "pain": ["pane"], "painful": ["pain full"], "sore": ["soar", "saw"],
    "marching": ["marchin"], "squat": ["squad"], "squats": ["squads"], "chair": ["cheer"],
    "breathe": ["breed"], "posture": ["pasture", "poster"], "score": ["store"], "plan": ["plane", "plant"],
    "exercise": ["exercises", "extra size"], "exercises": ["exercise"], "reps": ["wraps"],
    "hurts": ["hertz", "hurt"], "swollen": ["swollen", "swallen"], "weight": ["wait"], "weak": ["week"],
    "stretch": ["stretched"], "reminder": ["remainder"], "reminders": ["remainders"], "password": ["pass word"],
    "wall": ["war"], "push": ["bush"], "glute": ["glue"], "flexion": ["flection"], "tandem": ["tan them"],
    "toe": ["tow"], "toes": ["tows"], "tired": ["tied"], "chest": ["chess"], "pressure": ["pleasure"],
    "dizzy": ["dizzie"], "faint": ["feint"], "video": ["video"], "record": ["records"], "physio": ["fizzy oh"],
    "elbow": ["el bow"], "calf": ["calve"], "thigh": ["tie"], "lift": ["left"], "lifting": ["lefting"],
    "swelling": ["swelling"], "bend": ["bent"], "straight": ["strait"], "routine": ["route in"],
}
FILLERS = ["um ", "uh ", "okay ", "hello ", ""]


def heard(text: str, rng: random.Random) -> str | None:
    """[text] as speech-to-text may write it: one or two sound-alikes, no punctuation. None when no word of
    it has a sound-alike."""
    words = re.sub(r"[^a-z0-9' ]", " ", text.lower()).split()
    spots = [k for k, w in enumerate(words) if w in SOUND_ALIKE and SOUND_ALIKE[w] != [w]]
    if not spots:
        return None
    for k in rng.sample(spots, min(len(spots), rng.choice([1, 1, 2]))):
        words[k] = rng.choice(SOUND_ALIKE[words[k]])
    s = rng.choice(FILLERS) + " ".join(words)
    r = rng.random()
    return s[:1].upper() + s[1:] + "." if r < 0.3 else s


def seeds():
    import test_chat
    probe = random.Random(0)
    out = []
    for p, q, w in test_chat.ALL_QUESTIONS:
        if w is None or (isinstance(w, str) and "/" in w) or heard(q, probe) is None:
            continue
        out.append((p, q, set(w) if isinstance(w, tuple) else {w}))
    return out


def build(seed: int, n: int = 2000) -> list[dict]:
    rng = random.Random(seed)
    base = seeds()
    cases = []
    for _ in range(n):
        p, q, want = rng.choice(base)
        cases.append({"plan_id": p, "seed_question": q, "text": heard(q, rng), "want": sorted(map(str, want))})
    return cases
