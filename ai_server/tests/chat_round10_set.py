"""Round 10 of the continuous chatbot improvement (8 Oct, rules 3.13): carers asking for a parent,
fasting, hot weather, low mood, swapping or skipping an exercise, what an exercise is, vague
messages. Written before looking at the rules; the first run is the honest score: 20/30.
Rules 3.14 added three topics for these (for_someone_else, motivation, other_activity); the
expectations they now answer were widened after the first run, marked "(3.14)". Now 30/30.
"""
from chat_round1_set import KNEE
from chat_round4_set import CORE, LEGS, SHOULDER

ROUND10 = [
    (KNEE, "my mother is 75, can she do these exercises", ("for_someone_else", "safety", "getting_started", "plan_exercises")),  # (3.14)
    (KNEE, "i am helping my father record his exercise", "recording_help"),
    (KNEE, "can i exercise while fasting", ("diet", "best_time")),
    (KNEE, "puasa boleh senaman tak", ("diet", "best_time")),
    (KNEE, "today very hot can exercise?", ("hot_weather", "safety", "best_time")),  # heat topic since 3.17
    (KNEE, "i feel so lazy to exercise", ("motivation", "tired", "difficulty")),  # (3.14)
    (KNEE, "i'm feeling sad and don't want to do anything", ("low_mood", "motivation", "tired", None)),  # (3.14), low_mood since 3.17
    (CORE, "what is a bird dog", "exercise:bird_dog"),
    (CORE, "can i skip the glute bridge", ("missed_session", "difficulty", "exercise:glute_bridge")),
    (LEGS, "can i do squats instead of step ups", ("difficulty", "plan_exercises", "exercise:step_up")),
    (LEGS, "step up hurts my knee", ("pain_or_discomfort", "pain_mild", "exercise:step_up")),
    (SHOULDER, "my arm cannot go up to shoulder height", ("difficulty", "weakness_balance", "pain_or_discomfort")),
    (KNEE, "help", ("bot_identity", "app_help", "getting_started", "greeting")),  # lists what it can help with
    (KNEE, "?", None),
    (KNEE, "hi doc", "greeting"),
    (KNEE, "how many exercises in my plan", "plan_exercises"),
    (KNEE, "which exercise first", "plan_exercises"),
    (KNEE, "i finished all exercises today, what next", ("plan_progress", "how_often")),
    (KNEE, "when can i stop this plan", "plan_progress"),
    (KNEE, "my knee better already, still need to continue?", "plan_progress"),
    (KNEE, "can i go jogging", ("other_activity", "safety", "difficulty")),  # (3.14)
    (KNEE, "i have a fever today", ("tired", "safety")),
    (KNEE, "i forgot my email", ("account_help", "forgot_password")),
    (KNEE, "the code expired", "verification_code"),
    (KNEE, "my score dropped from 90 to 60", "posture_result"),
    (KNEE, "it says no repetition found", ("posture_result", "recording_help")),
    (KNEE, "where to see what i did yesterday", "history_help"),
    (KNEE, "can i do the exercises on carpet", ("equipment", "safety")),
    (KNEE, "should i wear shoes", "equipment"),
    (KNEE, "thank you doctor, very helpful", "thanks"),
]
