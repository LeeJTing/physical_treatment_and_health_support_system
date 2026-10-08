"""Round 7 (7 Oct, rules 3.11): a fresh mixed set across every area, to measure how well the
earlier rounds generalised. Written before looking at the rules or earlier sets.
"""
from chat_round1_set import KNEE
from chat_round4_set import CORE, LEGS, SHOULDER

ROUND7 = [
    (KNEE, "how many times should i do heel raises", "exercise:heel_raise"),
    (KNEE, "knee hurts when i bend", "pain_or_discomfort"),
    (KNEE, "where to see my old results", "history_help"),
    (KNEE, "the reminder rings at wrong time", "reminders_help"),
    (KNEE, "i want to change my height", "profile_help"),
    (KNEE, "i cant remember my password", "forgot_password"),
    (KNEE, "where is the code ah", "verification_code"),
    (KNEE, "do i need special shoes", "equipment"),
    (KNEE, "should i exercise if i have a cold", "tired"),
    (KNEE, "what if i skip one day", "missed_session"),
    (KNEE, "is 10pm too late for exercise", "best_time"),
    (KNEE, "good morning doctor", "greeting"),
    (KNEE, "i have hypertension and diabetes", "condition_advice"),
    (KNEE, "my legs shaking during exercise", ("weakness_balance", "safety", "tired")),
    (KNEE, "how to put my phone for recording", "recording_help"),
    (KNEE, "my score 75 can continue?", "posture_result"),
    (KNEE, "what plan am i on", "plan_exercises"),
    (KNEE, "how long until i recover", "plan_progress"),
    (KNEE, "can i drink coffee before exercise", "diet"),
    (KNEE, "can i take my painkiller", "medication"),
    (SHOULDER, "my shoulder clicks when i raise my arm", ("pain_or_discomfort", "safety", "joint_noise")),
    (SHOULDER, "how high should i lift my arms", ("exercise:shoulder_flexion", "exercise:shoulder_abduction", "how_to")),
    (LEGS, "my knee goes inwards when i stand up", ("posture_result", "exercise:sit_to_stand", "how_to")),
    (LEGS, "is step up safe for my knees", ("exercise:step_up", "safety")),
    (CORE, "my lower back hurts during bridge", ("pain_or_discomfort", "exercise:glute_bridge")),
    (CORE, "can i do this on my bed", ("equipment", "how_to", "difficulty")),
    (KNEE, "bye bye", "goodbye"),
    (KNEE, "who made this app", ("bot_identity", "app_help")),
    (KNEE, "what's your name", "bot_identity"),
    (KNEE, "what is the capital of malaysia", None),
]
