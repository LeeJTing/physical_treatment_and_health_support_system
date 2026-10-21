"""Round 9 of the continuous chatbot improvement (8 Oct, rules 3.12): the exercises recorded on
7 Oct (bird dog, glute bridge, mini squat, step-up, heel raise), what the posture check says,
pregnancy / osteoporosis / joint replacement, account questions, Malay, very short replies.
Written before looking at the rules; the first run is the honest score: 23/30 (one expectation was
wrong, see glute bridge), 30/30 after the rule changes in chat-rules-3.13.
"""
from chat_round1_set import KNEE
from chat_round4_set import CORE, LEGS

ROUND9 = [
    (CORE, "my wrists hurt when i do bird dog", ("pain_or_discomfort", "pain_mild", "exercise:bird_dog")),
    # The exercise answer ends with where the phone goes for that exercise, so it is the better answer
    # (first run gave it; the expectation was corrected, not the rules).
    (CORE, "where should i put the phone for glute bridge", ("exercise:glute_bridge", "recording_help")),
    (LEGS, "how low should i go in mini squat", "exercise:mini_squat"),
    (LEGS, "what height step should i use", ("exercise:step_up", "equipment")),
    (KNEE, "the app says hips sag what does that mean", ("mistake:hips_sag", "posture_result")),  # glossary since 3.15
    (KNEE, "why it count only 3 reps when i did 5", ("posture_result", "recording_help")),
    (KNEE, "my video always say full body not visible", "recording_help"),
    (KNEE, "i have osteoporosis can i do these", ("condition_advice", "safety")),
    (KNEE, "i'm 5 months pregnant is it ok to exercise", ("condition_advice", "safety")),
    (KNEE, "just had hip replacement last month", ("condition_advice", "doctor_said", "safety")),
    (KNEE, "my doctor said no squats", "doctor_said"),
    (KNEE, "can do exercise after eat or not", ("diet", "best_time")),
    (KNEE, "i feel giddy after exercise", ("red_flag", "safety", "tired")),
    (KNEE, "my calf cramp during heel raise", ("pain_or_discomfort", "pain_mild", "exercise:heel_raise", "cramp")),
    (KNEE, "how many sets per day", "how_often"),
    (KNEE, "the exercise too easy already", "difficulty"),
    (KNEE, "can i add weights", ("difficulty", "equipment")),
    (KNEE, "change my password", ("account_help", "forgot_password", "change_password")),
    (KNEE, "how to delete my account", "delete_account"),  # 3.51: its own topic (account_help did not say how)
    (KNEE, "i got no internet can still use", "app_help"),
    (KNEE, "what does my score mean", "posture_result"),
    (KNEE, "the reminder sound too loud", "reminders_help"),
    (KNEE, "ok noted", "acknowledge"),
    (KNEE, "tq so much", "thanks"),
    (KNEE, "can my wife use my account", ("account_help", "app_help")),
    (KNEE, "my knee give way when i stand", ("weakness_balance", "safety", "red_flag")),
    (KNEE, "lutut saya bengkak", ("pain_swelling", "red_flag")),
    (KNEE, "boleh buat senaman waktu malam?", "best_time"),
    (KNEE, "I am diabetic, should i eat before exercise", ("diet", "condition_advice")),
    (KNEE, "how long until i see results", "plan_progress"),
]
