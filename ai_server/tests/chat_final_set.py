"""Fourth chatbot question set: written after rules v3 were finished and run once with no
changes beforehand. Its first-run score is the honest accuracy figure to report:
28/35 (80%) with rules v3; 3 misses were "not recognised" (safe), 4 went to the wrong topic.
Rules v3.1 then fixed the causes (exact words before spell-correction, two exercises named ->
plan order, difficulty statements, wording), so this set now also guards against regressions."""
from chat_holdout_set import CORE, KNEE, SHOULDER

BALANCE = "c84e6e5e-b43a-59fe-96ab-65e4b585e4f1"    # Balance and Fall Prevention
UPPER = "45245b62-5696-56fe-9713-9af0b74f8768"      # Upper Limb Strength

FINAL = [
    (BALANCE, "Hello doctor, I am 72 years old and my son set up this app for me. I want to know if I can do "
              "the exercises in the morning before breakfast?", ("how_often", "diet")),
    (BALANCE, "how long do i stand heel to toe", "exercise:tandem_stance"),
    (BALANCE, "i'm scared of falling during the balance exercise", ("safety", "weakness_balance")),
    (BALANCE, "Which one comes first, heel raise or sit to stand?", "plan_exercises"),
    (BALANCE, "my ankles feel sore 😣", "pain_or_discomfort"),
    (BALANCE, "CAN I DO IT WITHOUT A CHAIR", "equipment"),
    (BALANCE, "I missed 2 weeks because I was in hospital", "missed_session"),
    (BALANCE, "my blood pressure is high today, should i still exercise?", "condition_advice"),
    (BALANCE, "I felt my heart pounding after the exercise", "red_flag"),
    (BALANCE, "can i stop taking my calcium tablets", "medication"),
    (UPPER, "wall push up how far from the wall", "exercise:wall_push_up"),
    (UPPER, "my wrist hurts during push ups", "pain_or_discomfort"),
    (UPPER, "can I use a heavier water bottle", ("equipment", "difficulty")),
    (UPPER, "I can only do 5 curls", "difficulty"),
    (UPPER, "when will my arms be stronger", "plan_progress"),
    (UPPER, "the score said 55%, what did I do wrong?", "posture_result"),
    (UPPER, "how do i turn off the reminders", "plan_and_reminders"),
    (UPPER, "what do you do", "bot_identity"),
    (KNEE, "boleh exercise kalau knee sakit?", "pain_or_discomfort"),
    (KNEE, "after the session my knee feels warm and looks bigger", "pain_swelling"),
    (KNEE, "my knee is not painful anymore, can I stop the plan?", "plan_and_reminders"),
    (KNEE, "is it normal that my leg shakes when I hold it straight", "weakness_balance"),
    (KNEE, "where do I put the phone for knee extension", ("exercise:knee_extension", "recording_help")),
    (KNEE, "I forgot my password", "forgot_password"),   # own rule since 3.2, with a Reset password button
    (KNEE, "ok", "acknowledge"),   # 3.2: a bare "ok" gets a short reply instead of "not recognised"
    (KNEE, "what time is it", None),
    (KNEE, "lol", None),
    (SHOULDER, "my shoulder clicks when i raise my arm, is it bad?", ("pain_or_discomfort", "exercise:shoulder_abduction", "exercise:shoulder_flexion", None)),
    (SHOULDER, "can I swim instead of these exercises", "difficulty"),
    (SHOULDER, "my arm went numb after the arm raises", "red_flag"),
    (CORE, "how do I keep my back flat in bird dog", "exercise:bird_dog"),
    (CORE, "I have osteoporosis, is the bridge safe?", ("condition_advice", "exercise:glute_bridge")),
    (CORE, "my back is better now, what next?", "plan_progress"),
    (CORE, "the camera can't see me when I lie on the floor", "recording_help"),
    (CORE, "thank you doctor", "thanks"),
]
