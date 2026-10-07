"""Round 11 of the continuous chatbot improvement (8 Oct, rules 3.14): what the posture check's
mistake names mean, filming problems, falls and dizziness on standing, pain scores, breathing,
rest between sets. Written before looking at the rules; the first run is the honest score: 22/30.
Rules 3.15 added a glossary of the posture check's mistake names (mistake:<label>); the four
questions about a name accept it, marked "(3.15)". Pain *during* an exercise goes to the sharp-pain
answer (stop and check) on purpose, so it is accepted for the bridge question.
"""
from chat_round1_set import KNEE
from chat_round4_set import CORE, LEGS, SHOULDER

ROUND11 = [
    (SHOULDER, "what is shoulder shrug", ("mistake:shoulder_shrug", "posture_result")),  # (3.15)
    (SHOULDER, "it say uneven arms what is that", ("mistake:uneven_arms", "posture_result")),  # (3.15)
    (LEGS, "what does incomplete stand mean", ("mistake:incomplete_stand", "posture_result")),  # (3.15)
    (KNEE, "the result said trunk lean", ("mistake:trunk_lean", "posture_result")),  # (3.15)
    (KNEE, "my room is quite dark can still record", ("recording_help", "video_quality")),  # lighting answer since 3.16
    (KNEE, "should i hold the phone landscape or portrait", "recording_help"),
    (KNEE, "the phone keep falling down while recording", "recording_help"),
    (KNEE, "i fell yesterday while doing step up", ("red_flag", "safety")),
    (KNEE, "i feel dizzy when i stand up from the chair", "red_flag"),
    (KNEE, "my pain is 3 out of 10 is that ok", ("pain_mild", "pain_or_discomfort")),
    (KNEE, "pain 8/10 after exercise", ("pain_sharp", "pain_or_discomfort", "red_flag")),
    (KNEE, "can i take panadol before exercise", "medication"),
    (KNEE, "how long should i rest between sets", ("how_often", "how_to")),
    (KNEE, "should i breathe in or out when lifting", ("safety", "how_to")),
    (KNEE, "i have a cast on my arm", ("condition_advice", "safety", "doctor_said")),
    (CORE, "my lower back pain during bridge", ("pain_sharp", "pain_or_discomfort", "pain_mild", "exercise:glute_bridge")),
    (CORE, "cannot balance on bird dog", ("weakness_balance", "difficulty", "exercise:bird_dog")),
    (KNEE, "my legs very weak since i stayed in bed for months", ("weakness_balance", "getting_started", "muscle_loss")),
    (KNEE, "i'm scared of falling", ("weakness_balance", "safety", "fear_of_falling")),
    (KNEE, "should i use a walking stick while exercising", ("equipment", "weakness_balance", "safety")),
    (KNEE, "can i exercise sitting down only", "difficulty"),
    (KNEE, "my score is 79 so close", "posture_result"),
    (KNEE, "why my progress didn't update", ("posture_result", "plan_progress", "history_help")),
    (KNEE, "what time is it", None),
    (KNEE, "tell me a joke", None),
    (KNEE, "good night", ("goodbye", "greeting")),
    (KNEE, "selamat pagi", "greeting"),
    (KNEE, "terima kasih", "thanks"),
    (KNEE, "sakit pinggang lepas senaman", ("pain_or_discomfort", "pain_mild")),
    (KNEE, "saya jatuh semalam", ("red_flag", "safety")),
]
