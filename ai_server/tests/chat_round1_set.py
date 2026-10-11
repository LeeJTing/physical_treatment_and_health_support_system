"""Round 1 of the continuous chatbot improvement (7 Oct, rules 3.4 -> 3.5).

Written BEFORE looking at the rules, the way patients type: navigation to screens, timing,
health conditions, Malaysian English, typos, very short and odd inputs. The first run is the
honest score for unseen questions; failures were then fixed with general rule changes and the
set kept as regression tests. Expected = rule key, a tuple of acceptable keys, or None for
"not recognised" (FR500_22).
"""
import json
from pathlib import Path

_CAT = json.loads((Path(__file__).resolve().parents[2] / "assets" / "seed" / "catalogue.json").read_text(encoding="utf-8"))
KNEE = _CAT["plans"][0]["plan_id"]

ROUND1 = [
    # navigation: profile
    (KNEE, "where to edit my weight", "profile_help"),
    (KNEE, "i gained weight, where to update", "profile_help"),
    (KNEE, "how to add diabetes to my profile", ("profile_help", "condition_advice")),
    (KNEE, "my risk say high why", "profile_help"),
    (KNEE, "take me to profile", "profile_help"),
    # navigation: treatment / recording / history / reminders
    (KNEE, "open my exercise", ("how_to", "plan_exercises", "treatment_nav")),
    (KNEE, "where do i record the video", "recording_help"),
    (KNEE, "how to upload my exercise video", "recording_help"),
    (KNEE, "where can i see my score last week", "history_help"),
    (KNEE, "show me my progress chart", ("history_help", "plan_progress")),
    (KNEE, "set reminder 8am", "reminders_help"),
    (KNEE, "the app never notify me", "reminders_help"),
    (KNEE, "i dont want reminder anymore", "reminders_help"),
    # account
    (KNEE, "cannot login le", "forgot_password"),
    (KNEE, "forgot pasword", "forgot_password"),
    (KNEE, "how to change password", ("forgot_password", "change_password")),
    (KNEE, "my code expired", "verification_code"),
    (KNEE, "never receive email from you", "verification_code"),
    (KNEE, "how to logout", "account_help"),
    # timing
    (KNEE, "can i do exercise at 11pm", "best_time"),
    (KNEE, "is morning better or night better", "best_time"),
    (KNEE, "can exercise before sleep or not", "best_time"),
    (KNEE, "what time should i do my exercises", "best_time"),
    (KNEE, "exercise after lunch ok?", ("best_time", "diet")),
    # conditions
    (KNEE, "i have diabetes can i exercise", "condition_advice"),
    (KNEE, "got high blood pressure, safe or not", ("condition_advice", "safety")),
    (KNEE, "my asthma is acting up today", ("condition_advice", "tired")),
    (KNEE, "i have arthritis in my knee", ("condition_advice", "pain_or_discomfort")),
    # getting started / help
    (KNEE, "first time using, what to do", "getting_started"),
    (KNEE, "how this app works", ("bot_identity", "getting_started", "app_help")),
    (KNEE, "what should i do today", ("getting_started", "plan_exercises", "treatment_nav")),
    # short / odd input
    (KNEE, "?", None),
    (KNEE, "123456", None),
    (KNEE, "okok", "acknowledge"),
    (KNEE, "thank you very much doctor", "thanks"),
    (KNEE, "lol", None),
    (KNEE, "what is the weather today", None),
    (KNEE, "tell me a joke", None),
    (KNEE, "hi, my knee hurts", "pain_or_discomfort"),
    (KNEE, "hello how to start", "getting_started"),
]
