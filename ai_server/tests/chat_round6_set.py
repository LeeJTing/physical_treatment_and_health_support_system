"""Round 6 of the continuous chatbot improvement (7 Oct, rules 3.10 -> 3.11): limitations, risk
level and the patient's own schedule. Written before looking at the rules; the first run is the
honest score.
"""
from chat_round1_set import KNEE
from chat_round4_set import LEGS, SHOULDER

ROUND6 = [
    # physical limitations
    (LEGS, "my left leg is weak can i do step up", ("weakness_balance", "exercise:step_up", "condition_advice")),
    (KNEE, "i have balance problem", "weakness_balance"),
    (KNEE, "i always lose my balance", "weakness_balance"),
    (SHOULDER, "my right arm cannot lift high", ("weakness_balance", "difficulty", "exercise:shoulder_flexion")),
    (SHOULDER, "my shoulder is stiff in the morning", ("pain_or_discomfort", "condition_advice", "best_time",
                                                        "stiffness")),
    (KNEE, "i use a walking stick", ("weakness_balance", "equipment", "safety")),
    (KNEE, "can i do it sitting down", ("difficulty", "how_to", "equipment")),
    (KNEE, "i am in a wheelchair", ("weakness_balance", "difficulty", "condition_advice")),
    # risk level
    (KNEE, "i am high risk can i do more exercise", ("profile_help", "difficulty", "safety", "risk_level", "safety_limits")),
    (KNEE, "what does medium risk mean", "risk_level"),  # 3.52: its own topic (profile_help did not explain the levels)
    (KNEE, "how is my risk calculated", "risk_level"),  # 3.52: its own topic (profile_help did not explain the levels)
    # schedule
    (KNEE, "which days should i exercise", "how_often"),
    (KNEE, "can i exercise every day", "how_often"),
    (KNEE, "i only have 10 minutes", ("how_often", "difficulty")),
    (KNEE, "can i split the exercises morning and evening", ("how_often", "best_time")),
    (KNEE, "i exercised already today, can i do again", ("how_often", "difficulty")),
    # combined
    (KNEE, "i have diabetes, what time is best to exercise", "best_time"),
    (KNEE, "with high blood pressure can i exercise in the morning", ("best_time", "condition_advice")),
    (KNEE, "is it safe for old people", ("safety", "condition_advice")),
    (KNEE, "my doctor said rest for a week", ("diagnosis", "missed_session", "tired", "doctor_said")),
    # emotional
    (KNEE, "i feel lazy to exercise", ("motivation", "tired", "missed_session")),  # motivation topic since 3.14
    (KNEE, "i am scared to fall", ("weakness_balance", "safety", "fear_of_falling")),
    (KNEE, "i feel like giving up", ("plan_progress", "tired", "missed_session", "motivation")),   # 3.67
    (KNEE, "i am so frustrated my score is always low", "posture_result"),
    # plan management
    (KNEE, "can i do two plans at the same time", ("plan_and_reminders", "multiple_plans")),  # several plans since 9 Oct (3.35)
    (KNEE, "i finished all exercises what now", ("plan_progress", "plan_and_reminders")),
    (KNEE, "how do i get a new plan", "plan_and_reminders"),
    (KNEE, "delete my account", "delete_account"),  # 3.51: its own topic (account_help did not say how)
    (KNEE, "is my data safe", "privacy_data"),  # 3.51: its own topic (account_help did not say how)
    (KNEE, "who can see my information", "privacy_data"),  # 3.51: its own topic (account_help did not say how)
]
