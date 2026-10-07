"""Round 8 of the continuous chatbot improvement (7 Oct, rules 3.12 -> 3.13): Malaysian-style
messages (particles lah/leh/meh, Malay-English mixing) and long messages from elderly patients.
Written before looking at the rules; the first run is the honest score.
"""
from chat_round1_set import KNEE

ROUND8 = [
    (KNEE, "boss how to start this one ah", "getting_started"),
    (KNEE, "my knee very pain lah", "pain_or_discomfort"),
    (KNEE, "cannot do meh too hard", "difficulty"),
    (KNEE, "can skip today or not", "missed_session"),
    (KNEE, "the video cannot upload leh", "recording_help"),
    (KNEE, "why my score so low one", "posture_result"),
    (KNEE, "reminder can change time anot", "reminders_help"),
    (KNEE, "i want ask about my plan", "plan_exercises"),
    (KNEE, "kaki saya lemah", "weakness_balance"),
    (KNEE, "bahu sakit bila angkat tangan", "pain_or_discomfort"),
    (KNEE, "macam mana nak mula", "getting_started"),
    (KNEE, "saya ada darah tinggi boleh senaman tak", "condition_advice"),
    (KNEE, "saya lupa kata laluan", "forgot_password"),
    (KNEE, "nak tukar plan", "plan_and_reminders"),
    (KNEE, "bila masa sesuai untuk senaman", "best_time"),
    (KNEE, "hello, good afternoon. I am 68 years old, I just had knee surgery three months ago and my "
           "physiotherapist recommended this app. I want to know how often I should exercise.", "how_often"),
    (KNEE, "Dear doctor, I tried the exercise yesterday but my knee became swollen and warm at night, "
           "what should I do?", ("pain_swelling", "red_flag")),
    (KNEE, "Good evening. My husband has diabetes and high blood pressure, is it safe for him to do "
           "these exercises in the evening?", ("best_time", "condition_advice", "safety")),
    (KNEE, "sorry to bother you, my eyes are not good, the words too small, how to make bigger", None),
    (KNEE, "my grandson set this up, i dont know how to use", ("app_help", "getting_started")),
]
