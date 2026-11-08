"""Round 18 (14 Oct, PC): what users ask about the features added since round 17 (Terms of Use and
privacy, delete my account, a parent's or guardian's agreement under 18, a doctor's OK before plans,
"Report this answer"), plus everyday topics asked the messy way real users type (no punctuation,
typos, short fragments, Malaysian English, Malay). Written before changing the rules.
"""
from chat_round1_set import KNEE

ROUND18 = [
    # Privacy and personal data (Terms of Use section 5)
    (KNEE, "is my data safe", "privacy_data"),
    (KNEE, "who can see my health info", "privacy_data"),
    (KNEE, "do u sell my data", "privacy_data"),
    (KNEE, "where is my data stored", "privacy_data"),
    (KNEE, "do you keep my exercise videos", "privacy_data"),
    (KNEE, "how long do you keep my data", "privacy_data"),
    (KNEE, "can i get a copy of my data", "privacy_data"),
    (KNEE, "data saya selamat ke", "privacy_data"),
    # Delete my account
    (KNEE, "how to delete my account", "delete_account"),
    (KNEE, "i want to remove my account and all my data", "delete_account"),
    (KNEE, "delete acc", "delete_account"),
    (KNEE, "can i undo deleting my account", "delete_account"),
    (KNEE, "macam mana nak padam akaun", "delete_account"),
    # Terms of Use
    (KNEE, "where can i read the terms and conditions", "terms_help"),
    (KNEE, "what did i agree to", "terms_help"),
    (KNEE, "why must i accept the terms again", "terms_help"),
    (KNEE, "what happens if i decline the terms", "terms_help"),
    # Under 18
    (KNEE, "im 15 can i use this app", "guardian_consent"),
    (KNEE, "why does my parent need to agree", "guardian_consent"),
    (KNEE, "i turned 18 how do i change my age group", "guardian_consent"),
    (KNEE, "it says my age does not match the terms", "guardian_consent"),
    # A doctor's OK before plans (a condition answered "No")
    (KNEE, "why cant i get a plan it says check with my doctor first", "doctor_clearance"),
    (KNEE, "my asthma is not under control can i still get exercises", "doctor_clearance"),
    (KNEE, "what does under control mean", "doctor_clearance"),
    (KNEE, "my doctor said ok now how do i get a plan", "doctor_clearance"),
    # Report this answer
    (KNEE, "your answer was wrong", "report_answer"),
    (KNEE, "how do i report a wrong answer", "report_answer"),
    (KNEE, "that didnt answer my question", "report_answer"),
    # Everyday topics, typed the messy way
    (KNEE, "knee pain after exercise normal or not", "pain_or_discomfort"),
    (KNEE, "my legs very tired after the plan", "tired"),
    (KNEE, "cant finish all reps", "difficulty"),
    (KNEE, "too hard for me lah", "difficulty"),
    (KNEE, "i skip 3 days already", "missed_session"),
    (KNEE, "vid too dark", "video_quality"),
    (KNEE, "where to put my phone when recording", "recording_help"),
    (KNEE, "why my score so low", "posture_result"),
    (KNEE, "the app says not the right exercise but i did it", "wrong_exercise"),
    (KNEE, "can i exercise after eating", "best_time"),  # timing after a meal (my expectation was wrong)
    (KNEE, "can i go jogging also", "other_activity"),
    (KNEE, "what time best to exercise", "best_time"),
    (KNEE, "how many times a week", "how_often"),
    (KNEE, "do i need dumbbells", "equipment"),
    (KNEE, "i forgot my pasword", "forgot_password"),
    (KNEE, "didnt get the verification code", "verification_code"),
    (KNEE, "change my weight in profile", "profile_help"),
    (KNEE, "the words too small cannot see", "text_size"),
    (KNEE, "my mother want to use this for her", "for_someone_else"),
    (KNEE, "rasa pening masa senaman", "red_flag"),  # dizzy while exercising: stop (my expectation was wrong)
    (KNEE, "no mood to exercise today", "motivation"),
    (KNEE, "can i do 2 plans at once", "multiple_plans"),
]
