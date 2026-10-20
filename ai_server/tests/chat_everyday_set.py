"""Everyday things people type to a rehabilitation chatbot that no earlier test covered (21 Oct, Elwin: "keep
expanding the knowledge base for random inputs"). Each family lists messages and the topics a right answer
can have (None = "Question not recognised", the message echoed back). Messages are typed messily at random
(chat_user_style_set.messy). evaluate_chat_everyday.py runs it.

Families: chit-chat, feelings, a body part alone, a symptom alone, app features, health readings, emoji,
requests the chatbot cannot do, other sports and activities, Malaysian food and drink, a time alone, and
yes / no after an answer.
"""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_user_style_set import messy  # noqa: E402

N = None
ANY_PAIN = {"pain_or_discomfort", "pain_mild", "pain_sharp"}
FAMILIES = {
    "chit_chat": [("how are you", {"how_are_you"}), ("how are you doing", {"how_are_you"}),
                  ("what's up", {"how_are_you", "greeting"}), ("sup", {"how_are_you", "greeting"}), ("good night", {"goodbye"}),
                  ("dah makan?", {"how_are_you", "greeting"}), ("have you eaten", {"how_are_you", "greeting"}), ("i'm bored", {"motivation", "low_mood"}),
                  ("tell me a joke", {"bot_identity", N}), ("are you there", {"greeting"}), ("good morning doc", {"greeting"}),
                  ("nice to meet you", {"greeting"}), ("see you tomorrow", {"goodbye"}), ("apa khabar", {"how_are_you", "greeting"})],
    "feelings": [("i'm sad", {"low_mood"}), ("feeling lonely", {"low_mood"}), ("i give up", {"motivation", "low_mood"}),
                 ("nobody cares about me", {"low_mood", "crisis"}), ("i'm stressed", {"low_mood"}),
                 ("i feel hopeless", {"low_mood", "crisis"}), ("sedih", {"low_mood"}), ("i feel useless", {"low_mood"}),
                 ("i'm frustrated with my progress", {"low_mood", "motivation", "plan_progress"}),
                 ("i cry every day", {"low_mood", "crisis"}), ("i feel down", {"low_mood"}),
                 ("i'm angry", {"low_mood"}), ("rasa murung", {"low_mood"})],
    "body_part": [("knee", {N, "clarify", "body_map"} | ANY_PAIN), ("my back", {N, "clarify", "body_map"} | ANY_PAIN),
                  ("shoulder", {N, "clarify", "body_map"} | ANY_PAIN), ("lutut", {N, "clarify", "body_map"} | ANY_PAIN),
                  ("pinggang", {N, "clarify", "body_map"} | ANY_PAIN), ("my hip", {N, "clarify", "body_map"} | ANY_PAIN),
                  ("wrist", {N, "clarify", "body_map"} | ANY_PAIN), ("ankle", {N, "clarify", "body_map"} | ANY_PAIN)],
    "symptom": [("dizzy", {"red_flag"}), ("pening", {"red_flag"}), ("numb", {"red_flag"}), ("cramp", ANY_PAIN),
                ("tired", {"tired"}), ("swollen", {"pain_swelling"}), ("sore", {"pain_mild", "pain_or_discomfort"}),
                ("fever", {"tired"}), ("cough", {"tired"}), ("short of breath", {"red_flag"}), ("penat", {"tired"}),
                ("muscle ache", ANY_PAIN), ("stiff", ANY_PAIN | {"how_to", "safety"}), ("kebas", {"red_flag"}),
                ("nausea", {"tired", "red_flag"}), ("headache", {"tired", "red_flag", "pain_or_discomfort"})],
    "app_feature": [("dark mode", {"text_size", "app_help"}), ("font", {"text_size"}), ("bigger text", {"text_size"}),
                    ("logout", {"account_help", "session_expired"}), ("change language", {"language"}),
                    ("notification sound", {"reminders_help", "reminder_late_or_off"}), ("history", {"history_help"}),
                    ("where my results", {"history_help", "posture_result"}),
                    ("delete my data", {"delete_account", "privacy_data"}), ("offline", {"app_facts", "app_help"}),
                    ("update app", {"app_problem", "app_facts", "app_help"}), ("app crash", {"app_problem"}),
                    ("video upload failed", {"recording_help", "video_quality"})],
    "reading": [("bp 180/110", {"red_flag"}), ("blood pressure 190/100", {"red_flag"}), ("sugar 3.2", {"red_flag", "condition_advice"}),
                ("bp 120/80", {"condition_advice", "acknowledge", N}), ("sugar 6", {"condition_advice", "diet", N}),
                ("heart rate 150 after exercise", {"red_flag", "safety"}), ("weight 70kg", {"profile_help", N}),
                ("my bp is high today", {"condition_advice", "safety"}),
                ("glucose 2.8", {"red_flag"}), ("bp 200/120 headache", {"red_flag"})],
    "emoji": [("👍", {"acknowledge", "thanks"}), ("🙏", {"thanks"}), ("😢", {"low_mood", N, "clarify"}),
              ("❤️ thanks", {"thanks"}), ("👌", {"acknowledge", "thanks"}), ("😭😭", {"low_mood", N, "clarify"})],
    "cannot_do": [("call my doctor", {"cannot_do"}), ("book an appointment", {"cannot_do"}),
                  ("send message to my son", {"cannot_do"}), ("play music", {"cannot_do"}),
                  ("order food for me", {"cannot_do"}), ("whatsapp my daughter", {"cannot_do"}),
                  ("make an appointment with physio", {"cannot_do"}), ("call ambulance for me", {"red_flag"})],
    "activity": [("can i do yoga", {"other_activity"}), ("jogging ok?", {"other_activity"}),
                 ("swimming", {"other_activity"}), ("badminton", {"other_activity"}), ("taichi", {"other_activity"}),
                 ("can i go gym", {"other_activity"}), ("cycling", {"other_activity"}), ("can i dance", {"other_activity"}),
                 ("hiking this weekend ok", {"other_activity"}), ("can i play football", {"other_activity"})],
    "food": [("can eat durian?", {"diet"}), ("nasi lemak ok?", {"diet"}), ("teh tarik before exercise", {"diet"}),
             ("coffee before exercise", {"diet"}), ("banana after exercise", {"diet"}), ("what to eat", {"diet"}),
             ("can i drink milo", {"diet"}), ("roti canai for breakfast ok", {"diet"}), ("protein shake", {"diet"}),
             ("how much water", {"diet"})],
    "time_alone": [("tomorrow", {N, "clarify", "best_time"}), ("tonight", {N, "clarify", "best_time"}),
                   ("later", {N, "clarify", "acknowledge"}), ("esok", {N, "clarify", "best_time"}),
                   ("now", {N, "clarify", "acknowledge"}), ("this evening", {N, "clarify", "best_time"})],
    "yes_no": [("yes", "previous+ack"), ("no", "previous+ack"), ("ya", "previous+ack"), ("tak", "previous+ack"),
               ("nope", "previous+ack"), ("ok lah", "previous+ack"), ("sure", "previous+ack")],
}
PREVIOUS = ["how_often", "pain_or_discomfort", "exercise:heel_raise", "safety", "plan_progress"]


def build(seed: int, n: int = 2000) -> list[dict]:
    rng = random.Random(seed)
    names = list(FAMILIES)
    cases = []
    for _ in range(n):
        fam = rng.choice(names)
        base, want = rng.choice(FAMILIES[fam])
        previous = None
        if want == "previous+ack":
            previous = rng.choice(PREVIOUS)
            want = {previous, "acknowledge", "clarify"}
        text = base if fam in ("emoji", "reading") else messy(base, rng)
        cases.append({"kind": fam, "text": text, "base": base, "previous_category": previous,
                      "want": sorted(map(str, want))})
    return cases
