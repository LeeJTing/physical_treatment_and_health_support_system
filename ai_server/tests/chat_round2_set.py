"""Round 2 of the continuous chatbot improvement (7 Oct, rules 3.5 -> 3.6).

Focus: health conditions (the reply must suit the patient's condition), time of day, Malaysian
English and Malay words, elderly phrasing, two questions in one message, negation, and
navigation. Written before looking at the rules; the first run is the honest score.
"""
from chat_round1_set import KNEE

ROUND2 = [
    # conditions, typed by the patient
    (KNEE, "i got diabetes, sugar low when exercise, what to do", "condition_advice"),
    (KNEE, "can heart patient do this exercise", "condition_advice"),
    (KNEE, "i had a stroke last year, can i still do the plan", "condition_advice"),
    (KNEE, "osteoporosis safe to do squat or not", ("condition_advice", "safety")),
    (KNEE, "blood pressure 160 today can exercise?", ("condition_advice", "safety")),
    (KNEE, "my sugar level is 4 now", "condition_advice"),
    (KNEE, "i am asthmatic", "condition_advice"),
    # time of day, many ways
    (KNEE, "now 2am cannot sleep can i exercise", "best_time"),
    (KNEE, "is it ok to exercise after dinner at 9", "best_time"),
    (KNEE, "best time of the day for my knee exercise", "best_time"),
    (KNEE, "should i exercise before or after breakfast", "best_time"),
    (KNEE, "can do in the evening?", "best_time"),
    # Malaysian English / Malay
    (KNEE, "lutut sakit lepas exercise", "pain_or_discomfort"),
    (KNEE, "boleh buat exercise malam?", "best_time"),
    (KNEE, "how to do ah this exercise", "how_to"),
    (KNEE, "the app cannot record la", "recording_help"),
    (KNEE, "tak dapat code", "verification_code"),
    # elderly phrasing / long
    (KNEE, "dear sir i am 70 years old and my legs are weak, is the exercise suitable for me", ("weakness_balance", "condition_advice", "safety")),
    (KNEE, "my daughter installed this, how do i begin", "getting_started"),
    # two questions in one
    (KNEE, "how many times a week and how long each time", "how_often"),
    (KNEE, "i missed yesterday, should i do double today", "missed_session"),
    # negation / safety
    (KNEE, "no pain but a bit tired", ("tired", "pain_mild")),
    (KNEE, "i dont have chest pain, just sore muscles", ("pain_mild", "pain_or_discomfort")),
    (KNEE, "i feel dizzy and my chest is tight", "red_flag"),
    # navigation
    (KNEE, "where is the reminders page", "reminders_help"),
    (KNEE, "go back to home", None),
    (KNEE, "i want to see my profile", "profile_help"),
    (KNEE, "open my plan", ("treatment_nav", "plan_exercises")),
    (KNEE, "i want to change to a different plan", "plan_and_reminders"),
    (KNEE, "reset my password please", "forgot_password"),
]
