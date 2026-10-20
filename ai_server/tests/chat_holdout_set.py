"""Held-out chatbot questions, written after the rules were tuned on chat_eval_set.py and not
used for tuning, to give an honest accuracy figure. Mix of plans: the plan id is given per question.
"""
KNEE = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"        # Early Knee Recovery
SHOULDER = "1d7600d4-5fa4-538d-9f92-df663915233e"    # Shoulder Mobility Starter
CORE = "1aba07fd-cf5b-5d4c-a948-24e4c0d9fd90"        # Core and Back Care

HOLDOUT = [
    (KNEE, "could you walk me through the heel raise step by step", "exercise:heel_raise"),
    (KNEE, "my calves are aching since yesterday", "pain_or_discomfort"),
    (KNEE, "Is soreness the day after normal?", ("pain_or_discomfort", "pain_mild")),   # mild-soreness answer fits
    (KNEE, "it really hurts and it's getting worse every time", "pain_sharp"),
    (KNEE, "what days should I train", "how_often"),
    (KNEE, "Can I do the plan more than 3 times a week?", "how_often"),
    (KNEE, "I was busy and didn't exercise for 3 days", "missed_session"),
    (KNEE, "what kind of shoes", "equipment"),
    (KNEE, "my legs shake when I stand up from the chair", "weakness_balance"),
    (KNEE, "is my plan helping at all?", "plan_progress"),
    (KNEE, "what's the first exercise in my plan", "plan_exercises"),
    (KNEE, "my phone can't see my feet in the video", "recording_help"),
    (KNEE, "why did I only get 40 percent", "posture_result"),
    (KNEE, "Can I switch to another plan?", "plan_and_reminders"),
    (KNEE, "the reminder comes at the wrong time", "reminders_help"),
    (KNEE, "is it ok to exercise with a cold", "tired"),
    (KNEE, "I feel faint", "red_flag"),
    (KNEE, "I fell and hit my head", "red_flag"),
    (KNEE, "my whole arm feels numb", "red_flag"),
    (KNEE, "should I take ibuprofen for the pain", "medication"),
    (KNEE, "I think I tore something in my knee", "diagnosis"),
    (KNEE, "good evening", "greeting"),
    (KNEE, "ok thanks", "thanks"),
    (KNEE, "what's 2 plus 2", None),
    (KNEE, "recommend me a movie", None),
    (KNEE, "seated marching is it in my plan", "exercise:seated_marching"),
    (KNEE, "exercises too easy, can I add more", "difficulty"),
    (KNEE, "is warming up necessary", "safety"),
    (SHOULDER, "how do I raise my arms to the side properly", "exercise:shoulder_abduction"),
    (SHOULDER, "which exercises do I have", "plan_exercises"),
    (SHOULDER, "my shoulder is painful when I lift", "pain_or_discomfort"),
    (SHOULDER, "bicep curl how many reps", "exercise:elbow_flexion"),
    (SHOULDER, "can i use dumbbells", "equipment"),
    (SHOULDER, "shoulder clicking noise is that normal", ("joint_noise", None)),   # 3.12: own rule
    (SHOULDER, "where do I put the camera for the front arm raise", "exercise:shoulder_flexion"),
    (CORE, "how to do the bridge", "exercise:glute_bridge"),
    (CORE, "my lower back aches during bird dog", "pain_or_discomfort"),
    (CORE, "do I need a yoga mat for this plan", "equipment"),
    (CORE, "how long will it take to recover my back", "plan_progress"),
    (CORE, "can I do pelvic tilts", None),
    (CORE, "my back is stiff in the morning", "pain_or_discomfort"),
    (CORE, "what is in my core plan", "plan_exercises"),
    (CORE, "is it dangerous to exercise with back pain", "pain_or_discomfort"),
    (CORE, "I'm 70, is this safe for me?", ("safety", "age_limit")),   # 3.74: plans stop at 65
    (CORE, "byee", "goodbye"),
]
