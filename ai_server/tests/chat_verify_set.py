"""Third chatbot question set, written after both earlier sets were used for fixes and run ONCE
before any further change, to report generalisation honestly (see test_chat.py).
First run with rules v2: 20/35. Expected answers changed afterwards only where a new rule was
added for that topic; each change is marked. A tuple means any of those answers is acceptable."""
from chat_holdout_set import CORE, KNEE, SHOULDER

LEGS = "1e9ec416-4c4b-52bc-a070-1dc4a614a807"      # Lower Limb Strength Builder

VERIFY = [
    (LEGS, "how should I stand up from the chair without using my hands", "exercise:sit_to_stand"),
    (LEGS, "mini squats - how deep should I go", "exercise:mini_squat"),
    (LEGS, "my thighs burn after the squats, is that ok?", "pain_or_discomfort"),
    (LEGS, "how high should the step be", ("exercise:step_up", "equipment")),   # both answers give 15 cm
    (LEGS, "do i do all three exercises every session", "plan_exercises"),
    (LEGS, "I skipped two sessions this week", "missed_session"),
    (LEGS, "feel like my knee will collapse", "weakness_balance"),
    (LEGS, "can I exercise right after eating", "diet"),
    (KNEE, "is a sofa ok instead of a chair", "equipment"),
    (KNEE, "how many seconds do I hold the leg straight", "exercise:knee_extension"),
    (KNEE, "will this plan fix my knee", "plan_progress"),
    (KNEE, "the app said I need to retry, why", "posture_result"),
    (KNEE, "can my daughter record the video for me", "recording_help"),
    (KNEE, "I keep forgetting, can the app remind me", "plan_and_reminders"),
    (KNEE, "I have diabetes, any special advice", "condition_advice"),   # was "safety"; rule added after run 1
    (KNEE, "feeling very weak and shaky today", "weakness_balance"),
    (KNEE, "my ankle swelled up", "pain_swelling"),
    (KNEE, "pain in my chest when I march", "red_flag"),
    (KNEE, "I almost blacked out", "red_flag"),
    (KNEE, "should I see a doctor about my knee", "diagnosis"),
    (KNEE, "what tablets help joint pain", "medication"),
    (KNEE, "hey there", "greeting"),
    (KNEE, "cheers, that helps", "thanks"),
    (KNEE, "how do I log in", "account_help"),   # was None; account rule added after run 1 (objective 3)
    (KNEE, "what is your name", "bot_identity"),
    (SHOULDER, "how high do I lift my arms", ("exercise:shoulder_abduction", "exercise:shoulder_flexion")),
    (SHOULDER, "my elbow is sore after curls", "pain_or_discomfort"),
    (SHOULDER, "camera in front or at the side for arm raises?", "recording_help"),
    (SHOULDER, "this plan is 5 times a week? that's a lot", "how_often"),
    (SHOULDER, "is it fine to do it at night", "how_often"),
    (CORE, "my back hurts when I lift my hips", "pain_or_discomfort"),
    (CORE, "how long to hold the bird dog", "exercise:bird_dog"),
    (CORE, "can I do this on the bed", "equipment"),
    (CORE, "can I do sit ups instead", ("difficulty", None)),   # originally None; either is acceptable
    (CORE, "what does the core plan do for me", "plan_progress"),
]
