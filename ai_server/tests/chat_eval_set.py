"""Evaluation questions for the chatbot: (question, expected rule key).

Written as patients and testers actually type: paraphrases, typos, short and long
questions, Malaysian English, mixed topics, and questions the bot must NOT answer
from its rules. Expected keys:
  an intent key, "exercise:<pose_key>", "red_flag", or None (= "Question not recognised").
The plan used for every question is Early Knee Recovery
(Seated Knee Extension, Seated Marching, Heel Raise; 3 times a week).
Also used to produce the chatbot test-case table for Chapter 5.
"""

EVAL = [
    # ---- how to do the exercises (general) ----
    ("How do I do the exercises properly?", "how_to"),
    ("can you explain the correct technique", "how_to"),
    ("am i doing it right", "how_to"),
    ("what's the proper form", "how_to"),
    ("Show me how to do it", "how_to"),
    ("I'm not sure if my form is good", "how_to"),
    ("instructions pls", "how_to"),
    ("how shuld i do the excercises", "how_to"),

    # ---- specific exercises ----
    ("How do I do the seated knee extension?", "exercise:knee_extension"),
    ("knee extension how?", "exercise:knee_extension"),
    ("how to straighten my knee in the exercise", "exercise:knee_extension"),
    ("explain heel raises", "exercise:heel_raise"),
    ("how do i do calf raises", "exercise:heel_raise"),
    ("what is seated marching", "exercise:seated_marching"),
    ("seated march instructions", "exercise:seated_marching"),
    ("how do I do sit to stand?", "exercise:sit_to_stand"),
    ("how to do the bird dog", "exercise:bird_dog"),
    ("Is the glute bridge in my plan?", "exercise:glute_bridge"),
    ("how many reps of heel raise", "exercise:heel_raise"),
    ("how to do bicep curls", "exercise:elbow_flexion"),
    ("wall pushups how", "exercise:wall_push_up"),
    ("how do i do a mini squat", "exercise:mini_squat"),
    ("what is tandem stance", "exercise:tandem_stance"),
    ("step ups instructions", "exercise:step_up"),
    ("how to do side leg raise", "exercise:hip_abduction"),
    ("explain the front arm raise", "exercise:shoulder_flexion"),
    ("how do I do lateral raises", "exercise:shoulder_abduction"),
    ("marching on the spot how to", "exercise:march_in_place"),

    # ---- what is in my plan ----
    ("What exercises are in my plan?", "plan_exercises"),
    ("which exercise should I do first", "plan_exercises"),
    ("list of exercises", "plan_exercises"),
    ("how many reps do I need to do", "plan_exercises"),
    ("how many sets", "plan_exercises"),
    ("what's in this plan", "plan_exercises"),
    ("tell me about my plan", "plan_exercises"),

    # ---- progress ----
    ("When will I see results?", "plan_progress"),
    ("how long until i get better", "plan_progress"),
    ("is this plan even working", "plan_progress"),
    ("how do i know if im improving", "plan_progress"),
    ("what happens after I finish the plan", "plan_progress"),
    ("how long is the recovery", "plan_progress"),

    # ---- pain (decision tree) ----
    ("My knee hurts", "pain_or_discomfort"),
    ("I feel pain after exercising", "pain_or_discomfort"),
    ("is it normal to be sore", "pain_or_discomfort"),
    ("my muscles ache", "pain_or_discomfort"),
    ("pain?", "pain_or_discomfort"),
    ("my joints are very stiff in the morning", "pain_or_discomfort"),
    ("it's painful when I bend my knee", "pain_or_discomfort"),
    ("got cramp in my leg", "pain_or_discomfort"),
    ("my knee pain lah, can exercise or not", "pain_or_discomfort"),
    ("the pain is sharp and getting worse", "pain_sharp"),
    ("I get a shooting pain when I lift my leg", "pain_sharp"),
    ("just a bit of muscle soreness", "pain_mild"),
    ("my knee is swollen after the exercise", "pain_swelling"),
    ("there's swelling around my ankle", "pain_swelling"),
    ("the joint looks red and puffy", "pain_swelling"),

    # ---- how often / how long ----
    ("How often should I exercise?", "how_often"),
    ("can i do it everyday", "how_often"),
    ("how many times a week", "how_often"),
    ("how long should a session take", "how_often"),
    ("do I need rest days", "how_often"),
    ("can I exercise twice a day", "how_often"),
    ("hw ofen shuld i exersise", "how_often"),

    # ---- missed sessions ----
    ("I missed yesterday's session", "missed_session"),
    ("I forgot to do my exercises", "missed_session"),
    ("what if I skip a day", "missed_session"),
    ("how do i catch up", "missed_session"),
    ("I haven't exercised for a week", "missed_session"),

    # ---- safety ----
    ("Is it safe for me to exercise?", "safety"),
    ("should i hold my breath while lifting", "safety"),
    ("do i need to warm up first", "safety"),
    ("how do I avoid falling", "safety"),
    ("any precautions I should take", "safety"),
    ("is this exercise dangerous", "safety"),

    # ---- equipment ----
    ("what equipment do I need", "equipment"),
    ("do I need to buy weights", "equipment"),
    ("what chair should I use", "equipment"),
    ("what should I wear", "equipment"),
    ("can I use a water bottle", "equipment"),
    ("do i need a mat", "equipment"),

    # ---- difficulty ----
    ("this is too hard for me", "difficulty"),
    ("the exercises are too easy", "difficulty"),
    ("I can't finish all the repetitions", "difficulty"),
    ("can I make it more challenging", "difficulty"),
    ("struggling to complete the exercise", "difficulty"),

    # ---- tired / unwell ----
    ("I'm too tired to exercise today", "tired"),
    ("feeling exhausted", "tired"),
    ("should I exercise if I have a fever", "tired"),
    ("I'm not feeling well", "tired"),

    # ---- weakness / balance (report section 2.6 example) ----
    ("my leg feels wobbly when standing", "weakness_balance"),
    ("my legs feel weak", "weakness_balance"),
    ("I feel unsteady", "weakness_balance"),
    ("my knee keeps giving way", "weakness_balance"),
    ("I keep losing my balance", "weakness_balance"),
    ("legs feel like jelly", "weakness_balance"),

    # ---- recording the video (system troubleshooting, objective 3) ----
    ("how do I record my exercise", "recording_help"),
    ("where should I put my phone", "recording_help"),
    ("the app can't detect my body", "recording_help"),
    ("it says full body not visible", "recording_help"),
    ("how long should the video be", "recording_help"),
    ("my video won't upload", "recording_help"),
    ("what camera angle should I use", "recording_help"),

    # ---- posture score ----
    ("what does my posture score mean", "posture_result"),
    ("why is my accuracy so low", "posture_result"),
    ("I failed the posture check", "posture_result"),
    ("should I retry", "posture_result"),
    ("what does 65% mean", "posture_result"),

    # ---- plan and reminders ----
    ("how do i change my plan", "plan_and_reminders"),
    ("can I get a different plan", "plan_and_reminders"),
    ("I want to stop this plan", "plan_and_reminders"),
    ("how do I change the reminder time", "plan_and_reminders"),
    ("i am not getting any notifications", "plan_and_reminders"),

    # ---- medicines and diagnosis: must NOT give advice ----
    ("can I take panadol before exercising", "medication"),
    ("should I stop my blood pressure medicine", "medication"),
    ("what painkiller is best", "medication"),
    ("can I take my insulin after exercise", "medication"),
    ("what is wrong with my knee", "diagnosis"),
    ("do I have arthritis", "diagnosis"),
    ("is my ankle broken", "diagnosis"),
    ("do i need surgery", "diagnosis"),

    # ---- diet (other module) ----
    ("what should I eat before exercise", "diet"),
    ("should i drink water", "diet"),
    ("how do I lose weight", "diet"),

    # ---- conversation ----
    ("hi", "greeting"),
    ("Hello!", "greeting"),
    ("good morning", "greeting"),
    ("thanks", "thanks"),
    ("thank you so much", "thanks"),
    ("bye", "goodbye"),
    ("that's all", "goodbye"),
    ("what can you do", "bot_identity"),
    ("are you a real person", "bot_identity"),
    ("help", "bot_identity"),

    # ---- red flags: urgent advice, always first ----
    ("I have chest pain", "red_flag"),
    ("CHEST PAIN while exercising", "red_flag"),
    ("i cant breath properly", "red_flag"),
    ("I feel dizzy", "red_flag"),
    ("I fainted after the session", "red_flag"),
    ("my left arm is numb", "red_flag"),
    ("my heart is racing", "red_flag"),
    ("I fell down during the exercise", "red_flag"),
    ("my knee is badly swollen and hot", "red_flag"),
    ("feeling light headed", "red_flag"),
    ("my speech is slurred", "red_flag"),
    ("hi, I have chest pain, how often should I exercise", "red_flag"),
    ("short of breath", "red_flag"),
    ("my chest pian is bad", "red_flag"),

    # ---- negated red flags: NOT urgent ----
    ("I have no chest pain, how often should I exercise", "how_often"),
    ("I'm not dizzy, just tired", "tired"),

    # ---- mixed topics: the more specific / safety-related rule wins ----
    ("my knee hurts when I do the seated knee extension", "pain_or_discomfort"),
    ("is it safe to do heel raises", "exercise:heel_raise"),
    ("hello, how often should I exercise", "how_often"),
    ("thanks, but my knee still hurts", "pain_or_discomfort"),

    # ---- unrelated: must be "not recognised" ----
    ("what is the capital of France", None),
    ("tell me a joke", None),
    ("what's the weather today", None),
    ("who won the football match", None),
    ("asdfghjkl", None),
    ("123456", None),
    ("can you book a taxi for me", None),
    ("what is the meaning of life", None),
    ("translate hello to Malay", None),
    ("write me a poem", None),
]
