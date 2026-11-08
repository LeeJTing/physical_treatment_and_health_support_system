"""Round 13 of the continuous chatbot improvement (8 Oct, rules 3.21): everyday use of the app -
signing in, editing the profile, reminders on certain days, switching plans, reading results -
and messages typed by voice (no punctuation, run-on). Written before looking at the rules; the
first run is the honest score: 25/30. Rules 3.22 added a "language" topic; the three
language questions accept it, marked "(3.22)".
"""
from chat_round1_set import KNEE

ROUND13 = [
    (KNEE, "i cant log in", ("account_help", "forgot_password")),
    (KNEE, "it says wrong password but i typed correctly", "forgot_password"),
    (KNEE, "how do i log out", "account_help"),
    (KNEE, "can i change my email", ("account_help", "profile_help")),
    (KNEE, "i want to update my age", "profile_help"),
    (KNEE, "where do i add my medical conditions", ("profile_help", "condition_advice")),
    (KNEE, "remind me only on monday wednesday friday", "reminders_help"),
    (KNEE, "can i get reminder at 7pm instead", "reminders_help"),
    (KNEE, "i want a different plan this one too easy", ("plan_and_reminders", "difficulty")),
    (KNEE, "how do i pick a new plan", "plan_and_reminders"),
    (KNEE, "what does the green tick mean in my history", ("history_help", "posture_result")),
    (KNEE, "how is my accuracy calculated", "posture_result"),
    (KNEE, "my results page empty", ("history_help", "app_help")),
    (KNEE, "the app keep crashing when i record", ("recording_help", "app_help", "app_problem")),   # 3.67
    (KNEE, "video upload very slow", "recording_help"),
    (KNEE, "can i use the app without a phone stand", ("recording_help", "equipment")),
    (KNEE, "hi can you tell me how to do the knee one", ("exercise:knee_extension", "how_to")),
    (KNEE, "ok so i finished the first exercise what do i do next", ("plan_exercises", "plan_progress", "how_to")),
    (KNEE, "my knee hurts a bit after the seated marching is that normal", ("pain_mild", "pain_or_discomfort")),
    (KNEE, "um how many times a day should i do it", "how_often"),
    (KNEE, "i did all 3 exercises today feeling good", ("plan_progress", "acknowledge", "how_often")),
    (KNEE, "the reminder came but i was busy", ("missed_session", "reminders_help")),
    (KNEE, "does this app share my data", ("app_help", "account_help", "privacy_data")),
    (KNEE, "is my video saved somewhere", ("recording_help", "app_help", "account_help", "privacy_data")),
    (KNEE, "can the doctor see my results", ("history_help", "app_help")),
    (KNEE, "what language can i use", ("language", "bot_identity", "app_help")),  # (3.22)
    (KNEE, "boleh guna bahasa melayu", ("language", "bot_identity", "app_help")),  # (3.22)
    (KNEE, "speak chinese?", ("language", "bot_identity", "app_help", None)),  # (3.22)
    (KNEE, "thanks bye", ("goodbye", "thanks")),
    (KNEE, "ok", "acknowledge"),
]
