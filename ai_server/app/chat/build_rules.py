"""Builds rules.json for the rehabilitation chatbot (M500.2, FR500_17 to FR500_23).

Rule types (report section 2.6, Rule-Based NLP):
  * red flags         urgent safety phrases; always answered first (chest pain, severe swelling, ...)
  * intents           keyword rules with a predefined answer. `show` intents are the question
                      categories the app lists (FR500_18); hidden intents (greetings, medicine,
                      diagnosis, pain follow-ups) are still matched from typed text
  * follow-ups        decision-tree branches offered after an answer, e.g. pain -> mild / sharp / swelling
  * exercise intents  one per catalogue exercise, generated from its instruction text; worded for
                      the patient's plan when the exercise is in it
  * plan intents      what is in my plan / progress, generated from the plan itself
  * condition notes   extra safety lines added for the patient's declared conditions, risk level
                      and limitations (Table 4.2.2: the reply is filtered by health condition)

Priority decides between rules that both match (higher wins).
Re-run after editing this file or the catalogue:   python ai_server/app/chat/build_rules.py
"""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from app.chat.layout import layout  # noqa: E402  (3.68: every answer set out in lines)

ROOT = Path(__file__).resolve().parents[3]
CATALOGUE = ROOT / "assets" / "seed" / "catalogue.json"
OUT = Path(__file__).with_name("rules.json")
VERSION = "chat-rules-4.07"

# FR500_22's "Question not recognised" (3.66; was "The question is not recognised, please try asking other
# question."). A short message is echoed back in it (engine._not_recognised).
NOT_RECOGNISED = "Question not recognised. Please choose a topic below, or ask it another way."   # UC400 M7


def intent(key, title, priority, keywords, examples, answer, show=True, follow_ups=(), tailor=False,
           negatable=False, anchor_start=False, small_talk=False, action=None, more_actions=()):
    """negatable: a keyword right after "no"/"not" does not count ("I have no pain").
    anchor_start: keywords count only at the start of the message (greetings).
    small_talk: wins outright when the whole message is three words or fewer ("good morning", "help").
    action: a button the app shows under the answer, {"key": ..., "label": ...}; the app maps the key
    to a screen (open_reset_password, open_planning, open_profile, open_treatment, open_reminders,
    open_history). more_actions: a second button when the answer names a second screen (3.48)."""
    return {"key": key, "title": title, "show": show, "priority": priority, "keywords": list(keywords),
            "examples": list(examples), "answer": answer, "follow_ups": list(follow_ups), "tailor": tailor,
            "negatable": negatable, "anchor_start": anchor_start, "small_talk": small_talk, "action": action,
            "more_actions": list(more_actions)}


INTENTS = [
    # ---- shown categories ---------------------------------------------------------------------
    intent("getting_started", "Getting started", 5,
           ["start", "starting", "get started", "getting started", "begin", "beginning", "first step", "first steps",
            "first time", "new here", "new user", "where do i start", "where should i start", "how should we start",
            "how should i start", "how do i start", "how do we start", "how to start", "where to begin",
            "how to begin", "what should i do first", "what do i do first", "what to do first", "what now",
            "what next", "what should i do now", "how to use", "how to use this app", "how does the app work",
            "how do i use", "guide me", "walk me through"],
           ["how should we start", "where do I begin", "what should I do first", "I am new, how do I use this app",
            "how do I get started with my exercises"],
           "Here is how to start: 1) Make sure your health profile is complete (Profile tab), so your safety "
           "limits are set. 2) Open AI-assisted treatment planning and tap Retrieve physical treatment to get "
           "plans that suit you, then select one. 3) Open My treatment plan from the Treatment tab and start the "
           "first exercise: read its steps, then record yourself doing it. 4) The app checks your posture; reach "
           "80% to move on to the next exercise. Your reminders follow the plan's weekly schedule.",
           action={"key": "open_planning", "label": "Open treatment planning"},
           more_actions=[{"key": "open_profile", "label": "Open Profile"}]),
    intent("how_to", "How to do the exercises", 4,
           ["knee goes in", "knees go in", "knee goes inward", "knees go inward", "knee inwards", "knees inwards", "caving in", "knees together",
            "rest between", "between reps", "between sets", "between exercises", "break between", "how to do", "how do i do", "how should i do", "how to perform", "correct way", "right way", "proper way",
            "proper form", "good form", "technique", "instruction", "instructions", "step by step",
            "demonstrate", "demonstration", "show me how", "doing it right", "doing it wrong", "do it right",
            "do it correctly", "correctly", "properly", "form", "posture", "position", "guide", "tutorial", "explain",
            "teach me"],
           ["how do I do the exercises", "what is the correct way to do this exercise", "how do I know my form is right",
            "can you explain the steps", "am I doing the exercise properly"],
           "Each exercise in your plan has its own steps and safety points: open it from your treatment pathway. "
           "Move slowly and smoothly, keep breathing, and stay within a comfortable range. Record yourself doing it "
           "and the app will check your posture and tell you what to correct. You can also ask me how to do a "
           "specific exercise, for example \"how do I do the heel raise?\"", tailor=True),
    intent("pain_or_discomfort", "Pain or discomfort", 8,
           ["pain", "pains", "painful", "hurt", "hurts", "hurting", "sore", "soreness", "ache", "aching", "achy",
            "discomfort", "uncomfortable", "stiff", "stiffness", "tender", "cramp", "cramping", "strain", "burn",
            "burning", "throb", "throbbing", "twinge", "pinch", "pinching", "tight", "tightness", "sakit"],
           ["my knee hurts when I exercise", "is it normal to feel sore after exercising",
            "what should I do if I feel pain", "my muscles ache the next day", "my joints feel stiff"],
           "Some muscle tiredness or mild soreness for a day or two is normal when you start, and it should ease "
           "as you get used to the exercises. Pain that is sharp, gets worse while you exercise, or comes with "
           "swelling is not normal. Which describes your pain best? Choose an option below.",
           follow_ups=["pain_mild", "pain_sharp", "pain_swelling"], tailor=True, negatable=True),
    intent("how_often", "How often and how long", 4,
           ["do again", "again today", "twice a day", "two times a day", "more than once", "exercise again", "extra session", "already today",
            "how often", "how many times", "how many days", "every day", "everyday", "daily", "per week", "a week",
            "times a week", "frequency", "schedule", "how long", "how much time", "what days", "which days",
            "which day", "what time of day", "what time should", "time of day", "best time", "morning", "every evening", "each evening", "night", "at night",
            "before bed", "rest day", "rest days", "twice a day", "more than", "more often", "less often",
            "how many sessions", "session length", "duration", "minutes", "weekend", "weekends", "consecutive",
            "sets per day", "sets a day", "rounds per day", "per day"],
           ["how often should I exercise", "can I do this every day", "how many times a week", "how long should each session be",
            "should I take rest days", "what time of day is best"],
           "Follow the number of sessions per week shown in your plan, with a rest day in between when you can. "
           "Each session only takes a few minutes, and any time of day that suits you is fine, as long as it is "
           "not straight after a big meal. Your reminders already follow this schedule. Doing the exercises well "
           "matters more than doing extra sessions.", tailor=True),
    intent("missed_session", "Missed a session", 5,
           ["missed", "miss", "skip", "skipped", "skipping", "forgot", "forgotten", "didn't exercise", "did not exercise",
            "haven't exercised", "have not exercised", "fell behind", "fallen behind", "falling behind", "behind schedule", "catch up", "make up",
            "no time", "too busy", "busy", "stopped exercising", "break from"],
           ["I missed my session yesterday", "what if I skip a day", "I forgot to exercise", "how do I catch up"],
           "That is fine. Do your next session as usual; do not do two sessions in one day to catch up. If you "
           "have missed several days, start again gently with fewer repetitions and build back up."),
    intent("safety", "Exercising safely", 4,
           ["when to stop", "when should i stop", "stop exercising", "should i stop", "sweat", "sweating",
            "sweaty", "warm up", "warming up", "cool down", "cooling down", "safe", "safely", "safety", "unsafe", "danger", "dangerous", "careful", "precaution", "precautions",
            "risk", "risky", "breath", "breathe", "breathing", "warm up", "warmup", "warm-up", "warming up",
            "cool down", "cooling down", "stretch", "stretching", "my age", "old age", "elderly", "too old",
            "fall", "falling", "slip", "slipping", "support", "hold on", "harm", "injure myself", "hurt myself",
            "avoid injury", "okay for me", "ok for me", "suitable for me", "allowed"],
           ["is it safe for me to exercise", "how do I avoid falling", "should I hold my breath", "do I need to warm up",
            "what precautions should I take"],
           "Exercise next to a sturdy chair or counter, on a dry non-slip floor, and breathe normally; never hold "
           "your breath. Warm up with a few minutes of gentle movement first. Stop if you feel dizzy, short of "
           "breath, or unwell. Your plan already stays within the safety limits from your health profile.",
           tailor=True),
    intent("condition_advice", "Exercising with a health condition", 7,
           ["high blood pressure", "blood pressure", "hypertension", "diabetes", "diabetic", "blood sugar",
            "heart disease", "heart condition", "heart problem", "had a stroke", "stroke", "asthma", "asthmatic",
            "arthritis", "osteoporosis", "my condition", "my conditions", "health condition", "medical condition",
            "chronic", "heart patient", "sugar level", "my sugar", "sugar low", "low sugar", "glucose",
            "sugar reading", "pregnant", "pregnancy", "expecting a baby", "mengandung", "hamil",
            "hip replacement", "knee replacement", "joint replacement", "replacement surgery", "new hip",
            "new knee", "replaced hip", "replaced knee", "wound", "stitches", "incision", "cast", "plaster",
            "fracture", "fractured",
            "broken bone", "broke my", "sprain", "sprained", "heart attack", "pacemaker", "stent",
            "bypass surgery", "angioplasty",
            # 3.50 (11 Oct): the conditions added to the health profile
            "rheumatoid", "copd", "lung disease", "chronic lung", "emphysema", "cancer", "chemo",
            "chemotherapy", "radiotherapy", "kanser", "barah", "kidney disease", "kidney problem", "dialysis",
            "buah pinggang", "parkinson", "parkinsons", "multiple sclerosis", "foot ulcer", "diabetic foot",
            "wound on my foot",
            # 3.54 (15 Oct): everyday names (Malay ones arrive translated)
            "osteoarthritis", "weak bones", "brittle bones", "thin bones", "gave birth", "just had a baby",
            "after delivery", "parkinson's", "have ms", "with ms", "for ms", "got ms", "ms exercise", "ms can", "ada ms"],
           ["I have diabetes, is there anything special I should do", "can I exercise with high blood pressure",
            "I have asthma, any advice"],
           "Your plan was chosen within the safety limits for the conditions in your health profile, so you can "
           "follow it as set. Stop and rest if anything feels wrong, and check with your doctor before doing more "
           "than the plan.", tailor=True),
    intent("equipment", "What you need", 5,
           ["equipment", "chair", "chairs", "stool", "sofa", "couch", "bed", "floor", "carpet", "mat", "yoga mat",
            "weights", "water bottle", "dumbbell", "dumbbells", "step", "stairs", "shoes", "shoe", "barefoot",
            "socks", "clothes", "clothing", "wear", "band", "resistance band", "gym", "buy", "tools", "need anything",
            "space", "room", "outdoors", "outside", "wall", "counter", "table", "rail", "handrail",
            "instead of a chair", "instead of the chair", "instead of chair", "instead of a mat"],
           ["what equipment do I need", "do I need weights", "what kind of chair should I use", "what should I wear",
            "do I need to buy anything", "can I do it on the bed"],
           "You do not need to buy anything. Most exercises use a firm chair without wheels or armrests, pushed "
           "against a wall; a sofa or bed is too soft. Floor exercises need a mat or a carpet, and step-ups need "
           "a low step (no higher than 15 cm) with a rail. Wear comfortable clothes and non-slip shoes. A small "
           "water bottle can be used as a light weight if you are comfortable."),
    intent("difficulty", "Too easy or too hard", 7,
           ["cannot go up", "can't go up", "cannot go higher", "can't go higher", "not able to lift",
            "not able to raise", "cannot bend", "can't bend", "cannot straighten", "can't straighten",
            "sitting down", "seated version", "while sitting", "do it sitting", "cannot lift", "can't lift", "cannot raise", "can't raise", "not high enough", "cannot reach", "can't reach",
            "too easy", "too hard", "too difficult", "difficult", "struggle", "struggling", "can't finish",
            "cannot finish", "can't complete", "can't do", "cannot do", "unable to", "harder", "easier",
            "challenging", "not challenging", "progress to", "increase", "decrease", "fewer reps", "more reps",
            "add more", "level up", "too much", "too little", "boring", "modify", "instead of these exercises", "instead of the exercises",
            "instead of this exercise", "something else", "other exercise", "another exercise", "different exercise",
            "replace", "can only",
            "only do", "only manage", "only managed", "only able",
            # round 14 (elderly users)
            "won't go up", "wont go up", "won't go higher", "won't lift", "won't bend", "won't straighten",
            "as high as the picture", "as high as the video", "as far as the picture", "not as high as",
            "sit down halfway", "need to sit down", "rest halfway", "stop halfway", "halfway through",
            "gave up after", "give up after", "stopped after",
            "could only do", "half way", "only goes up", "only go up", "only goes down", "only go down"],
           ["the exercises are too easy", "this is too hard for me", "I can't finish all the repetitions",
            "can I make it harder", "can I do more repetitions"],
           "If an exercise is too hard, do fewer repetitions with good form and rest between them; it should feel "
           "like effort, not pain. If you cannot move as far as the picture, go only as far as is comfortable "
           "and a little further each week. If it feels too easy, keep the same plan until you finish it, then request a "
           "new recommendation from the planning page: it will suggest a plan for your new level. Do not add "
           "weight, extra sets or other exercises on your own.", tailor=True),
    intent("tired", "Feeling tired or unwell", 6,
           ["didn't sleep well", "did not sleep well", "not sleep well", "slept badly", "slept poorly", "poor sleep",
            "bad sleep", "no sleep", "sleepy", "not enough sleep", "tired", "tiring", "exhausted", "exhausting", "fatigue", "fatigued", "no energy", "low energy",
            "worn out", "sleepy", "drained", "fell asleep", "out of breath", "breathing hard", "panting", "not feeling well",
            # PC pass 14: panting after an exercise is effort, not the exercise's how-to
            "breathing hard after the", "out of breath after the", "panting after the", "breathing hard after doing",
            "gasping a bit", "gasping a little", "puffing", "huffing and puffing", "feel unwell", "unwell", "sick", "ill", "fever",
            "cold", "flu", "cough", "headache", "period", "bad day"],
           ["I feel too tired to exercise", "I am exhausted after the session", "I'm not feeling well today",
            "should I exercise when I am sick"],
           "Feeling a little tired after exercising is normal. If you are unusually exhausted, unwell, or have a "
           "fever, skip today's session and rest; continue when you feel better. If tiredness lasts for days or "
           "comes with breathlessness, contact your doctor.", negatable=True),
    intent("weakness_balance", "Weak or unsteady legs", 7,
           ["swayed", "sway", "swaying", "lost balance", "lost my balance", "walking stick", "use a stick", "walking cane", "walker", "walking frame", "zimmer", "crutch", "crutches", "wheelchair", "lose my balance", "lose balance",
            "wobbly", "wobble", "unsteady", "unstable", "shaky", "shaking", "shake", "shakes", "trembling", "tremble",
            "weak", "weakness", "give way", "gives way", "giving way", "give out", "gives out", "collapse",
            "collapsing", "buckle", "buckles", "buckling", "balance", "off balance", "lose balance", "losing balance",
            "lost my balance", "feel like falling", "jelly", "no strength", "not strong", "heavy legs",
            # 3.59: "i can't get up" was the age-limit answer, "can't stand up" heel raises. With a fall,
            # the floor, "since" or "lying" it is a warning sign instead (red_flag_combos).
            # Only the difficulty: "how should I stand up from the chair" is the sit-to-stand exercise.
            "can't get up", "cannot get up", "cant get up", "unable to get up", "hard to get up",
            "trouble getting up", "can't stand up", "cannot stand up", "cant stand up", "hard to stand up",
            "trouble standing up"],
           ["my leg feels wobbly when standing", "my legs feel weak", "I feel unsteady on my feet",
            "my knee gives way", "I lose my balance", "I can't get up from the chair", "I can't get up"],
           "Legs, arms or hands that feel weak, wobbly or shaky are common after a long period of less activity, "
           "and this is what your exercises are building up. For standing exercises always keep one hand on a "
           "sturdy chair or counter; for any exercise do fewer repetitions and rest when the shaking starts. If "
           "weakness comes on suddenly, or affects one side of your body, stop and get medical help straight away; "
           "if your hand shakes even when it is resting, tell your doctor.", tailor=True, negatable=True),
    intent("recording_help", "Recording your exercise video", 5,
           ["record", "recording", "recorded", "video", "videos", "camera", "film", "filming", "phone position",
            "put my phone", "put the phone", "where to put", "tripod", "stand for my phone", "full body",
            "not detected", "can't detect", "cannot detect", "can't see me", "cannot see me", "can't see my",
            "upload", "uploading", "angle", "frame", "720p", "resolution", "too long", "too short", "front or side",
            "in front or", "at the side", "lighting", "dark", "someone record", "record for me",
            "no repetition", "no repetitions", "no reps found", "repetition found", "no complete repetition",
            "landscape", "portrait", "horizontal or vertical", "sideways or upright", "phone stand",
            "place the phone", "place my phone", "phone at my side", "at my side", "phone in front",
            "hand not visible", "hand is not visible",
            "without a stand", "no stand", "no tripod"],
           ["how do I record my exercise", "where should I put my phone", "the app cannot detect my body",
            "why does it say my full body is not visible", "how long should the video be"],
           "Put your phone on a stand, upright, at about waist height and 2.5 to 3 metres away, so your whole "
           "body from head to feet stays in the picture during the movement. Use good light in front of you "
           "and record 10 to 30 seconds. Each exercise says whether the camera should face you or be at your "
           "side. Someone else may hold the phone for you if it stays still. If the app cannot see your whole "
           "body, step back a little and record again. If it found no repetition, make each movement a little "
           "bigger and slower, with a short pause back at the start."),
    intent("posture_result", "Understanding your posture score", 6,
           ["frustrated", "always low", "keep failing", "never pass",
            "score", "scores", "accuracy", "percent", "percentage", "my result", "the result", "result mean",
            "results page", "feedback", "posture check", "posture analysis", "retry", "try again", "low score",
            "app said", "the app says", "app told me", "it said my", "said my", "says my", "too far forward",
            "failed", "fail", "pass", "passed", "80", "correction", "corrections", "tips", "what did i do wrong",
            "wrong posture", "bad posture", "only counted", "it count", "count only", "counted only",
            "didn't count", "did not count", "not counted", "wrong count", "count wrong", "counted wrong",
            "rep count", "reps counted", "miscount", "missed my reps", "counted less", "count less"],
           ["what does my posture score mean", "why is my accuracy low", "what do I do if I fail the posture check",
            "should I retry the exercise"],
           "The posture score shows how closely your movement matched the correct form, as a percentage, with "
           "tips on what to change. At 80% or more your progress is updated automatically. Below that you can "
           "read the tips and retry, or continue; every attempt is saved so you can see your improvement. "
           "If it counted fewer repetitions than you did, make each one a full, clear movement with a short "
           "pause back at the start, and keep your whole body in the picture."),
    intent("best_time", "When to exercise", 5,
           ["what time should", "what time is best", "what time of day", "what time to", "which time", "best time", "good time", "right time", "when should i exercise",
            "when should i do", "when to exercise", "when can i exercise", "exercise now", "exercise tonight",
            "exercise at night", "night", "tonight", "late", "too late", "midnight", "before bed", "before sleep",
            "bedtime", "after dinner", "after eating", "after a meal", "morning or evening", "in the morning",
            "in the evening", "early morning", "can i do it now", "do it now", "right now", "clocktime",
            "morning better", "night better", "evening better", "before sleep", "before sleeping", "after lunch",
            "after breakfast", "before breakfast"],
           ["when is the best time to exercise", "can I exercise now", "is it ok to exercise at night",
            "should I exercise in the morning or evening"],
           "The best time is when you feel alert and have had a light meal about an hour before. Many people find "
           "late morning or late afternoon easiest. Keep to a regular time so it becomes a habit, and avoid the "
           "last hour or two before bed.", tailor=True),
    # Priority 7: "how does this app work" must beat the plan's progress rule ("is it working").
    intent("app_help", "How the app works", 7,
           ["how this app works", "how this app work", "how the app works", "how the app work",
            "how does the app work", "how does this app work", "how do i use this app", "how to use this app",
            "how to use the app", "how to use app", "app works", "using this app", "use this app",
            "internet", "no internet", "offline", "no wifi", "without wifi", "wifi", "mobile data", "no data",
            "no connection", "no signal"],
           ["how does this app work", "how do I use this app"],
           "HealthGuide has five tabs. Home shows today's session and your daily limits. Treatment holds your "
           "plan: get one in AI-assisted treatment planning, then do each exercise and record it so the app can "
           "check your posture. Profile holds your health details, which keep your advice safe. You can ask me "
           "about any of these at any time. You need an internet connection to sign in, check your posture "
           "and chat with me; your reminders still arrive without one.", show=False,
           action={"key": "open_planning", "label": "Open treatment planning"},
           more_actions=[{"key": "open_profile", "label": "Open Profile"}]),
    # Priority 8: the patient's own doctor outranks everything except red flags and medicines.
    intent("doctor_said", "Your doctor's advice", 8,
           ["doctor said", "doctor told me", "doctor advised", "doctor asked me", "physiotherapist said",
            "physio said", "physiotherapist told me", "told me to rest", "advised me to rest", "bed rest",
            "rest for a week", "rest for a few days", "doctor say", "doctor says"],
           ["my doctor said I should rest for a week", "the physiotherapist told me not to do squats"],
           "Always follow your doctor's or physiotherapist's advice first: it is based on examining you. If "
           "they told you to rest, pause your exercises (you can switch reminders off) and continue when they "
           "say it is safe; your progress is kept. If their advice differs from your plan, ask them which "
           "exercises are suitable, and update your health profile if anything has changed.", show=False,
           action={"key": "open_reminders", "label": "Pause my reminders"}),
    intent("joint_noise", "Clicking or cracking joints", 7,
           ["click", "clicks", "clicking", "clicky", "crack", "cracks", "cracking", "popping", "pops",
            "grinding", "creaking", "crunching", "noise", "noises", "sound", "sounds"],
           ["my shoulder clicks when I raise my arm", "my knee makes a cracking sound", "is the clicking normal"],
           "Clicking or cracking without pain is common and usually harmless; it is often gas or a tendon moving "
           "over the joint. Carry on if it does not hurt. If it comes with pain, swelling, or the joint catching "
           "or locking, stop that movement and ask your doctor or physiotherapist.", show=False, tailor=True),
    intent("treatment_nav", "My treatment plan", 6,
           ["open my exercise", "open my exercises", "start exercise", "start my exercise",
            "start exercising", "start my exercises", "go to exercise", "go to my exercise", "open exercise",
            "exercise page", "treatment page", "my treatment plan page", "open treatment", "open my treatment",
            "today's exercise", "todays exercise", "what should i do today", "what to do today",
            "where are my exercises", "take me to my exercises", "my pathway", "next stage"],
           ["open my exercises", "where are my exercises", "take me to my treatment plan"],
           "Your treatment plan shows your exercises in order. Open the next one, read its steps, then record "
           "yourself doing it; the app checks your posture and moves you on when you reach 80%.",
           show=False, action={"key": "open_treatment", "label": "Open my treatment plan"}),
    intent("profile_help", "Your health profile", 6,
           ["medium risk", "low risk", "high risk", "risk mean", "risk calculated", "my risk level", "risk level mean",
            "my profile", "health profile", "update profile", "update my profile", "edit profile", "edit my profile",
            "profile", "go to profile", "open profile", "take me to profile", "to my profile", "gained weight",
            "lost weight", "put on weight", "weight changed", "new weight", "where to update", "update my age",
            "change my profile", "profile page", "my details", "change my details", "update my details",
            "my weight", "my height", "my age", "change my weight", "update my weight", "change my age",
            "risk level", "my risk", "why am i high risk", "why high risk", "my conditions", "add a condition",
            "remove a condition", "add condition", "health conditions", "my limitations", "bmi", "body mass index"],
           ["how do I update my health profile", "why is my risk level high", "how do I change my weight",
            "where can I add my health conditions"],
           "Your health profile holds your age, gender, weight, height, health conditions and physical "
           "limitations. Your risk level and safety limits are worked out from it, and your treatment plans are "
           "chosen to fit them. Tap the button below, then Edit, to change anything; keep it up to date so your "
           "advice stays safe.", show=False, action={"key": "open_profile", "label": "Open my profile"}),
    # Priority 7: "reminder not working" is about reminders, not the plan's progress ("is it working").
    intent("reminders_help", "Exercise reminders", 7,
           ["reminder", "reminders", "remind", "remind me", "notification", "notifications", "notify", "alarm",
            "remindr", "reminer", "remider", "remainder", "remainders", "reminde", "notifcation", "notication",
            "notifications not", "reminder time", "change time", "wrong time", "not getting reminders", "no reminder",
            "turn off reminders", "stop reminders", "turn on reminders", "missed reminder", "too loud",
            "volume", "ringtone", "change the days", "days of my reminder", "weekdays",
            "weekends", "last day", "turn off the last day", "delete a reminder", "delete reminder",
            "delete my reminder", "remove a reminder", "remove reminder", "delete button", "bin icon"],
           ["how do I change my reminder time", "I am not getting reminders", "how do I turn off reminders",
            "how do I change the days of my reminder", "how do I delete a reminder"],
           "An exercise reminder says which exercise is next, and tapping it opens that plan. Open Reminders "
           "to change things: tap the time to change it, and tap a day to turn it on or off; one day must stay on, "
           "so to stop a reminder, switch it off instead. \u201cRemind me to log my health readings\u201d adds a "
           "daily reminder to record your blood pressure, sugar or weight. Reminders you added yourself can be "
           "deleted with the bin button; a plan's reminders stay with the plan and stop when the plan stops. If "
           "none arrive, check that notifications are allowed for HealthGuide in your phone settings. If you "
           "have already exercised that day, that day's exercise reminder is skipped. The sound follows your "
           "phone's notification settings.",
           show=False, action={"key": "open_reminders", "label": "Open reminders"}),
    # 8 Oct: the posture check's new messages (fall alert, adjusted targets, partial reps, video tips).
    intent("fall_alert", "The possible-fall message", 8,
           ["may have fallen", "might have fallen", "fall alert",
            "fall warning", "thinks i fell", "think i fell", "possible fall", "would the app know",
            "app know if i", "know if i fell", "know if i fall", "detect a fall", "detect falls", "detect if i fall",
            "fall detection", "detects falls"],
           ["the app said I may have fallen", "why did I get a fall warning"],
           "The posture check saw a movement that looked like losing your balance or a fall. If you did "
           "fall, or feel hurt or dizzy, stop and get help; call 999 in an emergency. If it was a false "
           "alarm (for example you bent down to pick something up), you can record the exercise again. "
           "Keep a sturdy chair or counter within reach while you exercise.", show=False),
    intent("adjusted_targets", "Adjusted targets", 7,
           ["targets adjusted", "adjusted targets", "target adjusted", "adjusted to my health profile",
            "lower target", "lower targets", "easier target", "easier targets"],
           ["why are my targets adjusted", "what does targets adjusted to my health profile mean"],
           "Because of your age or health profile, the posture check asks for a little less range of movement, "
           "so the exercises stay safe and achievable while your strength comes back. Checks on how you move, "
           "such as keeping your elbows straight or your back upright, are the same for everyone. If your "
           "health has changed, update your profile.", show=False,
           action={"key": "open_profile", "label": "Open health profile"}),
    intent("partial_reps", "Partial repetitions", 7,
           ["partial repetitions", "partial repetition", "partial reps", "partial rep", "small movements",
            "small movement", "half of each", "half of the movement", "half movements", "half the movement"],
           ["it says partial repetitions", "what does small movements mean"],
           "The posture check saw you moving but not as far as a full repetition, so it counted partial "
           "repetitions. That is a fine start, especially after a long rest: move a little further each "
           "session, only as far as is comfortable, and pause briefly back at the start of each one.",
           show=False, action={"key": "open_treatment", "label": "Open my treatment plan"}),
    intent("video_quality", "Video too dark or too far", 7,
           ["too dark", "quite dark", "video is dark", "video dark", "move the phone closer", "phone closer",
            "look small", "i look small", "too far away", "far from the camera", "less accurate"],
           ["it says my video is quite dark", "why does it say move the phone closer"],
           "A dark video, or you looking small in the picture, makes the posture check less accurate. Record "
           "with a light on in front of you (not behind you), and place the phone about 2 to 3 metres away "
           "so your whole body fills most of the picture, from head to feet. "
           # 4.00: what to wear, and no one else in the picture
           "Wear fitted clothes rather than loose ones, and keep other people and pets out of the picture.",
           show=False, action={"key": "open_treatment", "label": "Record an exercise"}),
    # 8 Oct (round 13): which languages the assistant understands.
    intent("language", "Languages", 5,
           ["what language", "which language", "languages", "bahasa melayu", "guna bahasa", "speak malay",
            "in malay", "speak chinese", "in chinese", "mandarin", "speak tamil", "in tamil", "english only"],
           ["what language can I use", "can I ask in Malay"],
           "I answer in English and understand many everyday Malay words mixed in, such as sakit, lutut, "
           "boleh or penat. Short, simple sentences work best. In an emergency, call 999.", show=False),
    # 8 Oct (round 10): elderly and family users.
    intent("for_someone_else", "Exercising for a family member", 3,
           ["my mother", "my father", "my mum", "my mom", "my dad", "my parents", "my parent",
            "my grandmother", "my grandfather", "my grandma", "my grandpa", "my wife", "my husband",
            "my son", "my daughter", "my friend", "can she", "can he", "for her", "for him", "she do", "he do",
            "father", "mother", "grandmother", "grandfather", "grandma", "grandpa", "year old father",
            "year old mother", "elderly parent"],
           ["can my mother do these exercises", "is this plan suitable for my father"],
           "Each person should use their own account and health profile: the plan and its safety limits are "
           "chosen from the profile of the person exercising, including their age, conditions and fall risk. "
           "Help them create an account and fill in their profile, then get a plan for them. For an older "
           "family member, stay close during the first sessions, keep a sturdy chair or counter within reach, "
           "and set up the phone for them so the app can check their posture. If they have fallen in the past "
           "year, feel unsteady or have a heart condition, ask their doctor before they start.", show=False,
           action={"key": "open_profile", "label": "Open health profile"}),
    # 8 Oct (round 14): elderly users after a long rest (disuse atrophy), fear of falling, small text,
    # family helpers.
    intent("muscle_loss", "Weak muscles after bed rest", 7,
           ["muscle loss", "lost muscle", "lost a lot of muscle", "losing muscle", "lose muscle", "muscles shrank",
            "muscle shrank", "muscles shrink", "muscle shrink", "muscles shrunk", "muscle shrunk", "shrank", "shrunk",
            "muscles got smaller", "thigh got smaller", "legs got smaller", "got smaller", "getting smaller",
            "thin legs", "legs are thin", "legs are so thin", "legs so thin", "skinny legs", "legs became thin",
            "muscle wasting", "wasting", "sarcopenia", "atrophy", "atrophied", "disuse", "bedridden",
            "bed bound", "bedbound", "lying in bed", "in bed for", "stayed in bed", "in hospital for",
            "in the hospital for", "in hospital", "after hospital", "out of hospital", "discharged from hospital",
            "from hospital", "from the hospital", "hospital stay", "warded", "build muscle",
            "build up muscle", "rebuild", "get stronger", "getting stronger", "become stronger", "regain",
            "get it back", "strength back", "my strength back", "too late to build", "too late to get stronger",
            "too late for me", "too old to get stronger", "too old to build", "after covid", "long covid"],
           ["I was in hospital for weeks and my legs are weak", "my muscles shrank after bed rest",
            "is it too late to build muscle at my age"],
           "Muscles shrink quickly after weeks in bed or in hospital, but they grow stronger again with exercise "
           "at any age. Start with the easiest exercises in your plan, a few repetitions with a sturdy chair "
           "within reach, and add a little each week; most people notice a difference within 4 to 8 weeks. Eat "
           "some protein at each meal (fish, eggs, tofu, beans or milk) unless your doctor has limited it. If "
           "one calf is swollen, warm or painful after bed rest, see a doctor before exercising.",
           show=False, tailor=True),
    intent("fear_of_falling", "Afraid of falling", 7,
           ["afraid of falling", "scared of falling", "fear of falling", "worried about falling",
            "worry about falling", "scared i will fall", "scared i'll fall", "afraid i will fall", "afraid i'll fall",
            "worried i will fall", "worried i'll fall", "scared to fall", "afraid to fall", "if i fall",
            "what if i fall", "in case i fall", "if she falls", "if he falls", "if she fall", "if he fall",
            # 3.73: told by the person helping ("my father is scared he will fall")
            "scared he will fall", "scared she will fall", "scared he'll fall", "scared she'll fall",
            "afraid he will fall", "afraid she will fall", "afraid he'll fall", "afraid she'll fall",
            "worried he will fall", "worried she will fall", "worried he'll fall", "worried she'll fall",
            "if he can't get up", "if she can't get up", "if he cannot get up", "if she cannot get up",
            "after a fall", "get up after a fall", "get up from the floor", "get up if i fall", "nobody is home",
            # 3.62: before weak legs' "cannot get up" (3.59) took "what if i cannot get up after falling".
            "get up after falling", "get up after fall", "get up after i fall", "can't get up after",
            "cannot get up after", "cant get up after", "if i can't get up", "if i cannot get up",
            "afraid of getting hurt", "scared of getting hurt", "worried about getting hurt", "afraid of a fall",
            "scared of a fall", "afraid of getting injured", "scared of getting injured",
            "no one is home", "no one at home", "nobody at home", "alone at home", "home alone", "live alone",
            "living alone", "stay alone", "staying alone", "someone with me", "someone be with me",
            "anyone with me", "scared to stand", "afraid to stand", "scared to exercise",
            "afraid to exercise", "holding the wall", "hold the wall", "hold onto the wall", "hold on to the wall",
            "holding the chair", "hold the chair", "hold onto something", "fell last year", "fell before",
            "fell down", "fell over", "fell off", "fell in the", "had a fall", "slipped in", "slipped on",
            "fallen before", "had a fall before", "takut fell", "fell last month", "fell a few months ago",
            "now i'm scared", "now i am scared", "since then i'm scared", "scared since",
            # laptop pass 10: a near-fall is a warning sign worth telling the doctor
            "nearly fell", "almost fell", "nearly fall", "almost fall", "nearly fallen", "almost fallen",
            "nearly slipped", "almost slipped", "nearly tripped", "almost tripped"],
           ["I am scared I will fall", "what if I fall when nobody is home", "should someone be with me"],
           "Being afraid of falling is common. Keep one hand on a sturdy chair or kitchen counter, wear non-slip "
           "shoes, clear the floor and keep your phone within reach. If you live alone, do the standing "
           "exercises when someone is at home, and skip them on days you feel unsteady. If you fall, do not "
           "get up quickly: rest, check for pain, roll onto your side, crawl to a sturdy chair and push up "
           "slowly. If you are hurt or cannot get up, call for help or 999 and keep warm. Tell your doctor "
           "about any fall or near-fall; they can check your balance and medicines.",
           show=False, tailor=True),
    intent("text_size", "Text too small", 6,
           ["words are too small", "words too small", "text is too small", "text too small", "font too small",
            "font size", "text size", "bigger text", "bigger font", "bigger words", "larger text", "larger font",
            "make the text bigger", "make the words bigger", "too small to read", "small words", "small text",
            "can't see the screen", "cannot see the screen", "can't see my screen", "cannot see my screen",
            "can't read the screen", "cannot read the screen", "hard to read", "difficult to read",
            "poor eyesight", "bad eyesight", "eyesight", "rabun"],
           ["the words are too small", "how do I make the text bigger"],
           "The app follows your phone's text size. To make the words bigger, open your phone's Settings, "
           "then Display, then Font size (on some phones, Font size and style), and move the slider up; the "
           "app's text grows with it. A family member can also sit with you while you use the app. The app "
           "has a light theme only; dark mode is not available yet.",
           show=False),
    intent("family_help", "Help from family", 6,
           ["help me with the app", "help me use the app", "help me use", "help me with this app",
            "help me record", "help me set up", "help me with my exercises", "can my daughter help",
            "can my son help", "daughter help", "son help", "family help", "family member help",
            "family members help", "grandchild help", "caregiver", "carer", "helper", "maid",
            "domestic helper"],
           ["can my daughter help me with the app", "can my caregiver record my video"],
           "Yes. A family member or carer can set up the phone, record your video, and read your results and "
           "my answers with you. Keep using your own account and health profile so your plan stays matched to "
           "you, and do the exercises yourself; they can stay close by in case you lose your balance.",
           show=False, action={"key": "open_treatment", "label": "Open my treatment plan"}),
    # 8 Oct (laptop pass 11): eating-disorder signs and not eating. Never calorie or weight-loss tips.
    intent("eating_concern", "Eating and exercise", 9,
           ["make myself vomit", "make myself sick", "make myself throw up", "made myself vomit", "made myself sick",
            "throw up after eating", "throwing up after eating", "vomit after eating", "vomit after meals",
            "purge", "purging", "haven't eaten", "have not eaten", "not eaten for", "didn't eat for",
            "did not eat for", "no food for", "skip meals", "skipping meals", "skip meal", "skip my meals",
            "skipped meals", "starve", "starving myself", "starve myself", "stop eating", "stopped eating",
            "not eating", "not eat", "eat nothing", "eaten nothing", "barely eat", "hardly eat", "too fat",
            "hate my body", "binge", "bingeing", "binging", "laxative", "laxatives", "burn off what i ate",
            "earn my food", "exercise to burn off"],
           ["I make myself vomit after eating", "I haven't eaten for 2 days, can I exercise",
            "I skip meals so I can exercise more"],
           "Please eat regular meals and do not exercise on an empty stomach or to make up for what you ate: "
           "your body needs food to recover and to keep you steady. If you have not been able to eat for a "
           "day or more, rest today and talk to your doctor. If you feel you have to make yourself vomit, "
           "skip meals or exercise to control your weight, you are not alone: talk to your doctor, or call "
           "Befrienders KL 03-7627 2929 (24 hours) or Talian HEAL 15555 (8 am to midnight). I cannot give "
           "calorie or weight-loss advice.", show=False),
    intent("bladder_leak", "Leaking urine", 8,
           ["wet myself", "wet my pants", "leak urine", "leaking urine", "leak a little", "leak when i",
            "pee a little", "pee myself", "bladder leak", "bladder leakage", "incontinence", "incontinent",
            "terkencing", "kencing sikit", "can't hold my urine", "cannot hold my urine"],
           ["I wet myself a little when I do the squats", "urine leaks out when I cough or squat"],
           "Leaking a little urine when you squat, cough or lift is common, especially after childbirth or as "
           "we get older, and it can be treated. Empty your bladder before you exercise and tell your doctor "
           "or a physiotherapist: pelvic floor exercises often help. If it starts suddenly together with back "
           "pain or numbness between your legs, get medical help straight away.", show=False),
    intent("low_mood", "Feeling low", 7,
           ["sad", "so sad", "depressed", "depression", "feeling down", "feel down", "low mood", "lonely",
            "grief", "grieving", "passed away", "hopeless", "feel empty", "keep crying", "sedih", "murung",
            "cry every day", "crying every day", "i cry", "nobody visits", "no one visits", "nobody cares",
            "no one cares", "alone all day", "all alone"],
           ["I feel sad", "I have been feeling down", "my husband died and I feel so sad"],
           "I am sorry you are feeling this way. Low mood is common during recovery and after a loss, and it is "
           "not a weakness. Gentle activity, daylight and talking with someone you trust can help. If you have "
           "felt low or lost interest in most things for more than two weeks, please talk to your doctor. If "
           "you ever think about harming yourself, call Befrienders KL 03-7627 2929 (24 hours) or Talian HEAL "
           "15555 (8 am to midnight), or 999 in an emergency.", show=False),
    intent("hot_weather", "Exercising in hot weather", 6,
           ["very hot", "so hot", "too hot", "hot day", "heatwave", "panas", "humid", "hot weather",
            "weather is hot"],
           # no "today" here: with "weather" it made "what is the weather today" a heat question
           ["it is very hot, can I exercise?", "is it ok to exercise in hot weather"],
           "On hot days exercise indoors in a cool, airy room, or outdoors only before 11 am or after 4 pm. "
           "Drink water before and after, wear light clothes, and stop if you feel dizzy, very thirsty, very "
           "sweaty or get a headache. Older adults and people with heart disease or diabetes are more at risk "
           "in the heat, so take extra care.", show=False),
    intent("motivation", "Keeping motivated", 4,
           ["lazy", "malas", "unmotivated", "no mood", "don't feel like",
            "dont feel like", "can't be bothered", "cannot be bothered"],
           ["I feel too lazy to exercise", "I have no motivation", "I want to give up"],
           "Many people feel this way. Start small: do just the first exercise today, at the same time each day, "
           "and let your reminder prompt you. Exercising with a family member helps, and Results shows how far "
           "you have come. Strength comes back slowly after a long rest, so every session counts, even a short "
           "one. If you have felt low or lost interest in most things for more than two weeks, please talk to "
           "your doctor.", show=False, action={"key": "open_history", "label": "See my progress"}),
    intent("other_activity", "Other sports and activities", 5,
           ["jogging", "jog", "go running", "running every", "gym", "swimming", "swim", "cycling", "bicycle",
            "play badminton", "play football", "play futsal", "play tennis", "playing badminton",
            "playing football", "go hiking", "yoga", "pilates", "zumba", "dancing",
            "other exercise", "other exercises", "other sports", "sports", "play sport", "brisk walk",
            "treadmill", "go for a walk", "walking exercise"],
           ["can I go jogging", "can I go to the gym", "can I play badminton"],
           "Gentle walking is good for you, also on rest days: on even ground, with your walking aid if you use "
           "one, and with someone if you have fallen before. For harder activity such as jogging, sports or "
           "the gym, wait until your plan has built up your strength, start gently, and ask your doctor or "
           "physiotherapist first, especially if you have a health condition or have fallen before. Stop if it "
           "causes pain that is still there the next day.", show=False),
    intent("history_help", "Your past results", 6,
           ["old results", "old scores", "see my old", "previous score", "previous scores", "earlier results", "earlier scores",
            "see my score", "see my scores", "score last week", "scores last week", "last week", "my score history", "past scores", "past results", "previous results", "my results", "session history",
            "previous sessions", "past sessions", "how did i do", "accuracy history", "what i did", "green tick",
            "tick in my history", "my history",
            "did yesterday", "yesterday's score", "see yesterday",
            "all my attempts", "track my progress", "see my progress"],
           ["where can I see my past results", "how did I do in my last session", "show my session history"],
           "Every exercise you record is saved with its posture score and tips. Session history shows them all, "
           "with your average, your best score and a chart of how your posture accuracy is changing.",
           show=False, action={"key": "open_history", "label": "See my results"}),
    # Round 15 (9 Oct): the features added on 9 Oct. Several active plans (Elwin's rules: clash = same
    # body area, same goal and mostly the same joints (3.44); at most 3 / 2 / 1 plans for Low / Medium / High risk; one exercise per plan
    # a day, a shared exercise done once and counted for both), the body map with the neck left out
    # (high risk), and the posture check's "does not look like" message. Not shown as categories (the list
    # stays as it was for older users); typed questions reach them.
    intent("multiple_plans", "Following more than one plan", 7,
           ["two plans", "2 plans", "three plans", "3 plans", "more than one plan", "several plans", "many plans",
            "how many plans", "both plans", "both my plans", "second plan", "add a plan",
            "add another plan", "add plan", "extra plan", "other plan", "plans at the same time",
            "plan at the same time", "plans at once", "clash", "clashes", "clashing", "conflict", "conflicts",
            "in both plans", "in both my plans", "both of my plans", "one of my plans", "stop one plan",
            "replace one", "replace a plan", "replace my plan", "dua pelan", "pelan serentak", "pelan lain",
            "tambah pelan", "plan together", "plans together", "not clash", "doesn't clash", "dont clash",
            "do not clash", "does not clash"],
           ["can I follow two plans at the same time", "how many plans can I have", "why does it say the plan clashes",
            "the same exercise is in both my plans"],
           "You can follow more than one plan: up to 3 at a time if your risk level is Low, 2 if it is Medium, and "
           "1 if it is High. Two plans with the same goal that train the same joints clash, so the app asks you "
           "to replace one instead of adding the second; a shoulder plan and a hand plan can be followed "
           "together. Each plan gives you one exercise a day; an exercise that is "
           "in two of your plans is done once and counts for both. To add a plan, open AI-assisted planning and "
           "choose Retrieve physical treatment. To stop one, open it on the Physical Treatment page and tap Stop "
           "this plan; your progress so far is kept.", show=False),
    intent("neck_not_covered", "Neck problems", 7,
           ["neck", "necks", "leher", "tengkuk", "cervical", "stiff neck", "neck pain", "neck exercise",
            "neck exercises"],
           ["why can I not select my neck", "is there an exercise for my neck", "I have neck pain"],
           "This app does not include neck exercises, which is why the neck is greyed out on the body map: neck "
           "problems need a doctor or physiotherapist to guide the exercises. If you have neck pain, see your "
           "doctor or physiotherapist, and get medical help straight away if it comes with numbness, tingling or "
           "weakness in your arms, or after a fall or injury. If your neck hurts during another exercise, stop "
           "that exercise and tell your doctor or physiotherapist.", show=False),
    intent("body_map", "Choosing the body area", 6,
           ["body map", "body picture", "body figure", "the figure", "the body diagram", "picture of the body",
            "choose the part", "choose a part", "choose body part", "choose the area", "choose my area",
            "select body part", "select the part", "select the area", "pick the area", "pick the part",
            "tap the body", "part of my body", "parts of my body", "which body part", "front and back",
            "choose both", "select both", "more than one area", "more than one part", "two areas", "two parts",
            "can't find my", "cannot find my", "exercise for my hand", "exercises for my hand",
            "exercise for my wrist", "exercises for my wrist", "exercise for my fingers", "any exercise for",
            "anggota badan", "bahagian badan"],
           ["how do I choose the part I want to recover", "where is the body map", "can I choose more than one part",
            "is there any exercise for my hand"],
           "Open AI-assisted planning and choose Retrieve physical treatment. The first question shows a body "
           "figure: tap each part you want to recover (you can choose more than one; its name appears on the "
           "picture), tap it again to remove it, and use Front and Back to turn the figure. If you cannot find the "
           "place, tap \u201cCan't find it? Choose from a list\u201d. The plans suggested then focus on the parts you "
           "chose; wrists and hands have their own plan, Hand and Wrist Recovery. The neck is greyed out: neck "
           "problems need a doctor or physiotherapist, so the app has no neck exercises.", show=False),
    intent("wrong_exercise", "\u201cDoes not look like\u201d the exercise", 7,
           ["wrong exercise", "does not look like", "doesn't look like", "dont look like", "don't look like",
            "not look like", "did not look like", "does not seem like", "not the right exercise",
            "chose the right exercise", "choose the right exercise", "choosing the right exercise",
            "went backwards", "arm went backwards", "your knees bent a lot", "you were sitting",
            "you were standing", "you were lying down", "legs moved one at a time"],
           ["it says this video does not look like the exercise", "why does it say wrong exercise",
            "it said my arm went backwards"],
           "The posture check first makes sure the video shows the exercise you chose. When it says the video does "
           "not look like that exercise, nothing is saved and the reason in brackets says what looked different, "
           "for example \u201cyour arm went backwards, not forwards\u201d. Check that you picked the exercise you "
           "recorded, then record it again following its steps, with the phone where the exercise says (in front "
           "of you or at your side) and your whole body in the picture. If you are sure it was the right exercise, "
           "try again with slower, clearer movements.", show=False),
    # Round 16 (9 Oct): change password from Profile, the 3-day session, Exit on the posture screens,
    # the Google account setup, the health-log reminder.
    intent("change_password", "Changing your password", 8,
           ["change my password", "change password", "change pasword", "change the password",
            "changing my password", "update my password", "update password", "still know the old",
            "know my old password", "old password", "current password", "password in profile",
            "tukar kata laluan", "ubah kata laluan", "tukar password", "tukar pasword"],
           ["how do I change my password", "I want a new password but I know the old one"],
           "To change your password while you still know it, open Profile and tap Change password: type your "
           "current password, then the new one twice (at least 8 characters, with a letter and a number). Your "
           "other phones are then signed out; this one stays signed in. If you have forgotten your current "
           "password, tap \u201cForgot your current password?\u201d there, or Forgot password? on the login "
           "screen, to get a reset code by email.",
           show=False, action={"key": "open_profile", "label": "Open Profile"},
           more_actions=[{"key": "open_reset_password", "label": "Reset by email"}]),
    intent("session_expired", "Why you were logged out", 7,
           ["logged out", "logged me out", "log me out", "signed me out", "kicked out", "kick me out",
            "log in again", "login again", "sign in again", "log in every time", "login every time",
            "have to log in", "need to log in", "session expired", "session ended", "stay logged in",
            "keep me logged in", "stay signed in"],
           ["why was I logged out", "why do I have to log in again"],
           "To keep your health details safe, you stay signed in on this phone only while you use the app: "
           "after 3 days without opening it you are signed out, and you log in again with your email and "
           "password (or Continue with Google). Opening the app at least once every 3 days keeps you signed in. "
           "Changing or resetting your password also signs you out on your other phones.", show=False),
    # Round 17: late or silent reminders (exact alarms only where allowed; "Turn on notifications").
    intent("reminder_late_or_off", "Reminders that come late or not at all", 8,
           ["came late", "come late", "comes late", "coming late", "one hour late", "an hour late", "hour late",
            "minutes late", "not on time", "reminder on time", "notification on time", "reminder late",
            "reminder is late", "notification late", "reminder delayed", "reminder is delayed",
            "notification delayed", "delayed reminder", "turn on notifications", "turn on notification",
            "notifications are turned off", "notifications turned off", "notifications are off",
            "notification is off", "cannot ring", "can't ring", "cant ring", "allow notifications",
            "dont allow", "don't allow", "do not allow", "peringatan lambat", "notifikasi lambat"],
           ["why did my reminder come late", "how do I turn on notifications"],
           "If the Reminders page says notifications are turned off, tap Turn on notifications, switch them on "
           "for HealthGuide and come back to the app: your reminders are set again (this also fixes pressing "
           "Don't allow by mistake). If reminders come late, Android may hold them back by up to an hour to save "
           "battery. To get them on time, open your phone's Settings, find HealthGuide under Apps (on some phones "
           "under Special app access) and turn on Alarms & reminders, then close and reopen HealthGuide.",
           show=False, action={"key": "open_reminders", "label": "Open reminders"}),
    intent("health_log_reminder", "A reminder to log your health readings", 8,
           ["reminder to log", "remind me to log", "reminder to record", "remind me to record",
            "reminder to check", "remind me to check", "health readings", "health log", "log my readings",
            "readings reminder", "blood pressure reminder", "sugar reminder"],
           ["can I get a reminder to log my blood pressure", "remind me to record my health readings"],
           "Yes. Open Reminders and tap \u201cRemind me to log my health readings\u201d: it reminds you every day "
           "at 8 pm to record your blood pressure, sugar or weight, and it is never skipped. Tap the time or the "
           "days to change them, switch it off for a while, or delete it with the bin button.",
           show=False, action={"key": "open_reminders", "label": "Open reminders"}),
    # Below the pain rules (8): "my knee hurts, how do I exit" gets the pain answer first.
    intent("exit_exercise", "Leaving an exercise", 7,
           ["exit the recording", "exit the exercise", "exit recording", "exit exercise", "exit button",
            "if i exit", "tap exit", "press exit", "exit halfway", "exercise halfway", "recording halfway",
            "exercise half way",
            "quit the exercise", "quit exercise", "leave the exercise", "cancel the exercise",
            "cancel recording", "cancel the recording"],
           ["how do I stop the exercise halfway", "how do I exit the recording"],
           "Tap Exit at the top of the recording, analysing or result screen to stop the exercise and go back "
           "to the home page. While you are recording or the video is being checked, the app asks first, and "
           "that attempt is not saved; a result of 80% or more that was already saved stays saved. You can do "
           "the exercise again later from Physical Treatment. If you feel pain, dizziness or unwell, stop at "
           "once, sit down and rest.", show=False,
           action={"key": "open_treatment", "label": "Open my treatment plan"}),
    intent("google_setup", "Signing in with Google", 8,
           ["signed in with google", "sign in with google", "continue with google", "using google",
            "after google", "google account", "google sign in", "google login", "log in with google",
            "login with google", "account setup", "complete account setup", "complete my account",
            "finish setup", "finish the setup", "cancel the setup", "has been linked", "been linked",
            "google linked", "username after"],
           ["I signed in with Google, why does it ask for a password", "what happens if I cancel the account setup"],
           "You can sign in with Continue with Google on the login screen. The first time, the app asks you to "
           "complete your account: choose a username and a password (at least 8 characters, with a letter and "
           "a number), so you can also log in with your email and password later. If you tap Cancel, nothing "
           "is kept and you return to the login screen; you can start again any time. If your Google email "
           "already has an account here, Google is linked to it and the app says \u201cYour Google account has "
           "been linked to your existing account.\u201d: your plans and results stay as they are.", show=False),
    intent("plan_and_reminders", "Changing your plan or reminders", 5,
           ["get a new plan", "new plan",
            "change plan", "change my plan", "new plan", "different plan", "another plan", "switch plan",
            "switch to", "stop plan", "stop the plan", "stop this plan", "change this plan", "end this plan",
            "quit this plan", "leave this plan", "stop my plan", "end my plan", "delete plan", "cancel plan", "quit"],
           ["how do I change my plan", "can I get a different plan", "how do I stop this plan"],
           "To change plan, open AI-assisted planning and choose Retrieve physical treatment to get new "
           "recommendations. You can follow up to 3 plans at once, depending on your risk level; a new plan for "
           "the same body area and goal replaces the one you have. You can stop a plan from the Physical "
           "Treatment page with Stop this plan. Reminders follow your plan's weekly schedule; check that notifications are "
           "allowed for the app in your phone settings if they do not appear."),
    intent("forgot_password", "Forgot password", 7,
           ["forgot password", "forgot my password", "forget password", "forget my password", "forgotten password",
            "forgot pasword", "forgot passwrod", "forgot pass", "pasword", "passwrod", "passward", "pass word",
            "password", "my password", "help with my password",
            "change pasword", "reset pasword",
            "reset password", "reset my password", "password reset", "lupa kata laluan", "lupa password",
            "new password", "cant remember my password", "can't remember my password", "lost my password",
            "wrong password", "password not working", "locked out", "account locked", "cannot log in",
            "can't log in", "cant log in", "unable to log in", "cannot login", "can't login", "cant login"],
           ["I forgot my password", "how do I reset my password", "I can't log in"],
           "You can set a new password with a 6-digit code sent to your email: tap the button below (or "
           "Forgot password? on the login screen), enter your email, then type the code and your new password. "
           "If the code does not arrive, check your spam folder and wait a minute before asking for a new one. "
           "After too many wrong passwords the account is locked for 15 minutes.",
           show=False, action={"key": "open_reset_password", "label": "Reset password"}),
    intent("verification_code", "Verification code", 7,
           ["where is the code", "where is my code", "the code", "no code yet", "where code",
            "verification code", "verify code", "no code", "didn't get the code", "didnt get the code",
            "did not get the code", "code not received", "never got the code", "didn't receive the code",
            "didnt receive the code", "did not receive the code", "didn't receive the email", "no email",
            "email not received", "otp", "resend code", "code expired", "code not working", "wrong code",
            "confirm my email", "verify my email", "email verification", "receive email", "receive any email",
            "not get code", "not get the code", "not get any code", "no otp", "code not come", "code never came",
            "receive the email", "never receive", "never received", "not receive", "not received", "email not coming",
            "email never came", "no email from you", "didn't get email", "didnt get email",
            "wrong code many times", "too many wrong", "code has expired"],
           ["I did not get the verification code", "the code is not working", "how do I verify my email"],
           "The 6-digit code is sent to the email you registered with. Check your spam or junk folder, and make "
           "sure the address is spelled correctly. You can tap Resend code once a minute; a code stops working "
           "after a while, and after 5 wrong tries (the app then says it has expired), so tap Resend code and "
           "always use the newest one. If you clicked a link in the email instead, return to the app and log "
           "in.", show=False),
    intent("account_help", "Account and login", 6,
           ["my information", "my info",
            "log in", "login", "log out", "logout", "sign in", "sign out", "account", "email",
            "username", "google sign in",
            "change my details"],
           ["how do I log in", "how do I update my health profile", "how do I log out"],
           "Log in with the email and password you registered with, or use Continue with Google. If you forgot "
           "your password, tap Forgot password? on the login screen to get a reset code by email. You can update "
           "your health details on the Profile page; your plan's safety limits are recalculated when you save. "
           "Your data is only visible to your own account."),

    # ---- decision-tree follow-ups (hidden; offered after the pain answer) -------------------------
    intent("pain_mild", "Mild soreness or tiredness", 9,
           ["mild", "a little", "slightly", "slight", "bit sore", "a bit", "just sore", "normal soreness",
            "muscle soreness", "aching muscles", "next day", "day after", "not too bad"],
           ["it is only mild soreness", "my muscles are a bit sore the next day"],
           "Mild soreness is a normal sign that your muscles are working. Keep exercising gently, move within a "
           "comfortable range, and it should ease within a day or two. If it lasts longer than three days, do "
           "fewer repetitions and contact your physiotherapist.", show=False, tailor=True, negatable=True),
    intent("pain_sharp", "Sharp or worsening pain", 9,
           ["sharp", "stabbing", "shooting", "getting worse", "worse", "worsening", "sudden pain",
            # Not "pain during" (3.66: "my wrist pain during push ups" is pain, not sharp pain).
            "can't move", "cannot move", "very painful", "really hurts", "unbearable", "won't go away", "not going away",
            # 3.64: not "every time" alone ("do i have to log in every time i open the app").
            "hurts every time", "hurt every time", "pain every time", "painful every time", "sakit every time",
            "every time i bend", "every time i move", "every time i stand", "every time i walk",
            "every time i lift", "every time i do it", "keeps hurting"],
           ["I get a sharp pain during the exercise", "the pain is getting worse"],
           "Stop the exercise that causes it and rest. Do not push through sharp or worsening pain. If it does "
           "not settle within a day, or it stops you moving normally, contact your doctor or physiotherapist "
           "before you continue with that exercise.", show=False, tailor=True, negatable=True),
    intent("pain_swelling", "Swelling, redness or heat", 9,
           ["swelling", "swollen", "swell", "swells", "swelled", "puffy", "redness", "red", "hot joint", "warm joint",
            "feels hot", "bruise", "bruising", "inflamed", "inflammation"],
           ["my knee is swelling after exercise", "the joint looks red and feels warm"],
           "Stop exercising that joint and rest it, raised if you can. Swelling, redness or heat in a joint "
           "should be checked: contact your doctor or physiotherapist before exercising it again. If the "
           "swelling is severe or you also have a fever, seek medical care today.", show=False, negatable=True),

    # ---- hidden intents: outside the bot's scope, answered safely -------------------------------
    intent("medication", "Medicines", 9,
           ["medicine", "medicines", "medication", "medications", "meds", "my meds", "pill", "pills", "tablet", "tablets", "painkiller",
            "painkillers", "pain killer", "panadol", "paracetamol", "ibuprofen", "aspirin", "insulin", "drug", "drugs",
            "dose", "dosage", "prescription", "supplement", "supplements", "vitamin", "vitamins", "cream", "ointment",
            "injection", "inhaler dose", "antibiotic", "antibiotics", "antibiotik", "which medicine",
            "what medicine", "glucosamine", "fish oil", "collagen", "minyak angin", "minyak urut", "liniment",
            "tiger balm", "counterpain", "balm"],
           ["can I take painkillers before exercising", "should I stop my medicine", "what medicine should I take"],
           "I cannot give advice about medicines. Please ask your doctor or pharmacist, and keep taking your "
           "medicines as prescribed unless they tell you otherwise. If a dose was taken twice by mistake, call "
           "your pharmacist or doctor now for advice; for insulin, a blood thinner or many tablets, call 999.",
           show=False),
    intent("diagnosis", "Diagnosis and seeing a doctor", 9,
           ["diagnose", "diagnosis", "what is wrong", "what's wrong", "is it broken", "broken", "fracture",
            "fractured", "torn", "tear", "tore", "sprain", "sprained", "dislocated", "pulled a muscle", "pulled muscle",
            "injured", "injury", "do i have arthritis", "do i have osteoporosis", "is it arthritis", "tendonitis",
            "sciatica", "slipped disc", "ligament", "meniscus", "x-ray", "xray", "scan", "mri", "surgery",
            "operation", "see a doctor", "see the doctor", "visit a doctor", "go to the doctor",
            "go to hospital", "see a physiotherapist", "should i see",
            # laptop pass 11: illnesses the assistant cannot diagnose
            "cancer", "tumour", "tumor", "covid", "dengue"],
           ["what is wrong with my knee", "is my bone broken", "do I have arthritis", "do I need surgery",
            "should I see a doctor"],
           "I cannot diagnose conditions or injuries. If you are worried, or a problem is not improving, please "
           "see your doctor or physiotherapist about it. If you think something is broken or seriously injured, "
           "stop exercising it and get medical care.", show=False),
    intent("diet", "Food and drink", 5,
           ["eat", "eating", "ate", "food", "diet", "meal", "meals", "after eating", "before eating", "drink",
            "drinking", "protein", "calories", "lose weight", "weight loss", "water", "hydrate", "hydration",
            "snack", "breakfast", "lunch", "dinner", "fasting"],
           ["what should I eat before exercising", "should I drink water", "can I exercise after a meal"],
           "Drink some water before and after your exercises, and wait about an hour after a large meal before "
           "exercising. For food advice that suits your health conditions, use the Diet section of the app.",
           show=False),
    intent("greeting", "Greeting", 1,
           ["hi", "hello", "hey", "hey there", "good morning", "good afternoon", "good evening", "helo", "hai", "yo",
            "anyone there", "are you there", "greetings"],
           ["hello", "hi there", "good morning"],
           "Hello! I can answer questions about your rehabilitation exercises, pain, safety, your plan, "
           "recording your videos and reminders. Tap a topic below or type your question.",
           show=False, anchor_start=True, small_talk=True),
    intent("thanks", "Thanks", 2,
           ["thanks", "thank you", "thank u", "thx", "ty", "tq", "cheers", "appreciate", "appreciated", "helpful",
            "that helps", "that helped", "great", "nice", "ok thanks", "okay thanks", "love this app",
            "love the app", "love it", "great app", "good app", "nice app", "awesome", "app is good",
            "app is great", "very helpful", "so helpful",
            # 3.66, Elwin's reports ("Yahnks", "yanks") and other ways thanks is mistyped.
            "yanks", "yahnks", "thnks", "tahnks", "thnx", "thanx", "tnx", "thks", "thank yuo", "thanku", "tqvm",
            "tq vm", "tenkyu", "thankss", "thankyou", "thnk you", "thanks you", "terima kasih"],
           ["thank you", "thanks a lot", "that was helpful"],
           "You're welcome. Keep it up! Ask me anything else about your plan, or tap Exit Chatbot when you are done.",
           show=False, small_talk=True),
    # Lowest priority and not small talk: answers a bare "ok", but "ok my knee hurts" still gets the
    # pain answer. No "yes"/"no"/"right"/"fine": they start real questions ("no pain", "right knee hurts").
    intent("acknowledge", "Okay", 0,
           ["ok", "okay", "okk", "okey", "alright", "all right", "noted", "got it", "understood", "i see", "cool",
            "hmm", "hm"],
           ["ok", "alright", "got it"],
           "Okay. If you have another question about your exercises, pain, safety or your plan, type it or tap "
           "a topic below.", show=False, anchor_start=True),
    intent("goodbye", "Goodbye", 1,
           ["bye", "byebye", "goodbye", "good bye", "see you", "see ya", "that's all", "thats all", "nothing else",
            "no more questions", "exit", "close", "good night"],
           ["bye", "that's all for now"],
           "Take care, and see you at your next session. Tap Exit Chatbot to return to the planning page.",
           show=False, small_talk=True),
    intent("bot_identity", "About this assistant", 2,
           ["who made", "who created", "who built", "who developed", "made this app", "who designed",
            "who are you", "what are you", "your name", "are you human", "are you a robot", "are you a bot",
            "chatgpt", "chat gpt", "gpt", "are you ai", "are you an ai", "artificial intelligence", "openai",
            "siri", "google assistant", "real doctor", "are you a doctor",
            "are you real", "real person", "what can you do", "what do you do", "what do you know",
            "what can you help", "what can i ask", "help", "how does this work",
            "how do you work", "chatbot", "chat bot",
            # 3.66, Elwin's reports: "what question can i ask" was the report answer; "i m ur father".
            "what question", "what questions", "which question", "which questions", "what to ask",
            "what should i ask", "what can you answer", "what question can i ask", "what questions can i ask",
            "what question can", "your father", "ur father", "your mother", "ur mother", "your dad", "ur dad",
            "your mum", "ur mum", "your mom", "ur mom", "are you my friend", "be my friend", "i love you",
            "love you", "do you love me", "are you single", "marry me", "are you married"],
           ["what can you do", "what can I ask you", "are you a real person", "what question can i ask"],
           "I am the rehabilitation assistant for your treatment plan. I answer common questions using answers "
           "prepared in advance, so I cannot diagnose or give medical advice. You can ask about how to do your "
           "exercises, pain, safety, how often to exercise, recording your video, your posture score, and "
           "your plan or reminders. Tap a topic below to see the questions you can ask.",
           show=False, small_talk=True),
    # 3.66, Elwin's reports ("Excuse me?", "exxuse me?"): what he expected - sorry, what can I help with,
    # and that a wrong answer can be reported.
    intent("pardon", "Sorry, say again?", 2,
           ["excuse me", "pardon", "pardon me", "come again", "say again", "say that again", "what did you say",
            "i beg your pardon", "sorry", "sorry what", "huh what"],
           ["excuse me?", "pardon?"],                  # not "come again?": "come" alone matched it
           "Sorry if my answer was not clear. What can I help you with? Choose a topic below, or type your "
           "question in other words. If an answer was wrong, tap Report this answer under it.",
           show=False, small_talk=True),
    # 3.66, Elwin's report ("allergy": "do you mean you have an allergy? You may add it to your profile").
    intent("allergy", "Allergies", 7,
           ["allergy", "allergies", "allergic", "alergi", "alahan", "allergic reaction"],
           ["I have an allergy", "allergy", "I am allergic to latex"],
           "If you have an allergy, tell your doctor before starting your exercises, and keep any allergy "
           "medicine you were given (such as an inhaler or an adrenaline pen) with you when you exercise. You "
           "can keep your health conditions up to date in your profile. If you have trouble breathing, or your "
           "face, lips or tongue swell, call 999 now.", show=False,
           action={"key": "open_profile", "label": "Open my profile"}),
    # 3.66, Elwin's report ("med": "do you need help calling emergencies?"): medicine or medical help.
    # 3.74 (numbers test, chat_numbers_set.py): a pulse, oxygen or temperature reading or question ("my
    # oxygen is 96", "what is a normal heart rate"). A reading that needs help now (oxygen 92% or lower, a
    # pulse of 150 or more, or 40 or less) is a warning sign before this (engine.low_oxygen, odd_pulse).
    intent("health_readings", "Your health readings", 6,
           ["heart rate", "heartrate", "pulse", "pulse rate", "heartbeat", "heart beat rate", "bpm",
            "normal heart rate", "resting heart rate", "oxygen", "oxygen level", "oxygen saturation", "spo2", "sp02",
            "o2 level", "o2 sat", "oximeter", "pulse oximeter", "body temperature", "my temperature",
            "temperature is", "temperature of", "check my temperature", "my temp", "suhu badan", "nadi", "kadar nadi",
            "oksigen", "paras oksigen", "what is a fever", "normal temperature"],
           ["what is a normal heart rate", "my oxygen is 96", "what temperature is a fever"],
           "I cannot check your readings, but these are the usual guides when you are resting. "
           "Pulse (heart rate): 60 to 100 beats a minute; it rises while you exercise and should settle within a "
           "few minutes of rest. "
           "Oxygen (SpO2): 95 to 100%; 92% or lower needs a doctor today, and with trouble breathing, call 999. "
           "Temperature: 38 \u00b0C or higher is a fever; skip exercise and rest until it is gone. "
           "Blood pressure: do not exercise when it is 180/110 or higher; follow your doctor's target. "
           "Stop exercising if your heart races, beats unevenly or stays fast after resting; with chest pain or "
           "fainting, call 999.", show=False),
    # 3.74: the app counts neither the calories burned nor steps ("how many calories did i burn" was the pain
    # answer); Home shows the daily food limits.
    intent("calories", "Calories and steps", 6,
           ["calorie", "calories", "kalori", "burn calories", "calories burn", "calories burned", "calories burnt",
            "burn fat", "burning fat", "fat burn", "count calories", "count my calories", "count steps",
            "count my steps", "step count", "step counter", "steps counter", "pedometer", "how many steps should",
            "how many steps a day", "how many steps per day", "how many steps do i", "steps a day", "steps per day",
            "langkah sehari"],
           ["how many calories did I burn", "does the app count my steps"],
           "The app does not count the calories you burn or your steps; your phone's step counter or a "
           "smartwatch can. "
           "These exercises build strength, balance and movement, and burn only a little energy. "
           "For food, Home shows your daily limits for calories, salt and sugar, worked out from your profile, "
           "and the Diet section has food advice; to lose weight, ask your doctor what suits you. "
           "Walking most days is good for you: start with what feels comfortable and add a little each week.",
           show=False),
    # 3.74: "i finished my exercise", "done 10 reps" (was the plan's exercise list). Low priority: "done my
    # exercise but my knee hurts" is about the knee.
    intent("session_done", "Well done", 3,
           ["finished my exercise", "finished my exercises", "finished the exercise", "finished the exercises",
            "finished today's exercise", "finished todays exercise", "done my exercise",
            "done my exercises", "done with my exercise", "done with my exercises", "done for today",
            "completed my exercise", "completed my exercises", "completed today's exercise", "did my exercise",
            "did my exercises", "have done my exercises", "siap senaman", "dah siap senaman", "sudah siap senaman",
            "selesai senaman", "habis senaman"],
           ["I finished my exercise", "I have done all my exercises"],
           "Well done for finishing your exercise! "
           "Your posture score and tips are saved in Session history. "
           "Rest, drink some water, and notice how you feel: mild muscle soreness the next day is normal. "
           "Each plan gives you one exercise a day: the next one comes tomorrow, and your reminder will tell you "
           "when.", show=False),
    # 3.76 (situations test, chat_situations_set.py): everyday situations around exercising. Before: "the haze
    # is bad today", "i'm on holiday", "i smoke" were not recognised, fasting got the general best time,
    # "can i exercise after blood donation" condition advice.
    intent("haze", "Haze and air quality", 7,
           ["haze", "hazy", "jerebu", "berjerebu", "air quality", "air pollution", "pollution", "polluted",
            "api reading", "api index", "api level", "air pollutant index", "ipu", "smoky outside", "air is smoky",
            "smoky air", "berasap", "asap tebal",
            "asap jerebu"],
           ["the haze is bad today", "the air quality is bad"],
           "On hazy days, exercise indoors with the windows and doors closed: all your exercises can be done at home. "
           "Check the Air Pollutant Index (API): above 100 is unhealthy, so do not exercise outdoors. "
           "With asthma, COPD or heart disease, keep your inhaler or medicines close, and stop if you cough, wheeze "
           "or feel short of breath. "
           "Drink plenty of water.", show=False),
    intent("fasting", "Exercising while fasting", 7,
           ["fasting",
            "puasa", "berpuasa", "ramadan", "ramadhan", "bulan puasa", "iftar", "berbuka",
            "buka puasa", "sahur", "sahoor", "suhoor", "intermittent fasting"],
           ["I am fasting in Ramadan", "exercise during Ramadan"],
           "You can keep doing your exercises while fasting, at a gentle pace. "
           "The easiest time is 1 to 2 hours after breaking your fast, or before sahur; avoid the late afternoon, "
           "when you are most tired and thirsty. "
           "Drink plenty of water between breaking your fast and sahur. "
           "If you have diabetes, especially with insulin or tablets that can cause low sugar, ask your doctor "
           "before exercising while fasting, and stop if you feel shaky, sweaty, dizzy or confused.", show=False),
    intent("weather", "Rain, cold and air-conditioning", 6,
           ["raining", "rainy", "in the rain", "rain today", "heavy rain", "hujan", "too cold", "very cold", "so cold", "cold room", "room is cold",
            "room is very cold", "cold weather", "weather is cold", "sejuk", "cuaca sejuk", "aircond", "air cond",
            "aircon", "air con", "air conditioner", "air conditioned", "air-conditioned", "air conditioning"],
           ["it is raining today", "my room is very cold"],
           "Rain does not stop your exercises: they can all be done indoors. "
           "In a cold or air-conditioned room, warm up for a few minutes longer and wear a layer you can take off. "
           "With asthma, cold air can bring on wheezing, so keep your inhaler close. "
           "On hot days, exercise in a cool, airy room and drink water.", show=False),
    intent("travel", "Travelling or on holiday", 6,
           ["travelling", "traveling", "going to travel", "will travel", "travel next", "travel overseas", "travel abroad", "on holiday",
            "go on holiday", "going on holiday", "school holiday", "family holiday", "vacation", "balik kampung", "outstation", "overseas", "abroad",
            "long flight", "my flight", "on a flight", "hotel room", "cuti sekolah", "bercuti"],
           ["I am travelling this week", "I will be on holiday next week"],
           "You can take your plan with you: the exercises need only a sturdy chair and a little space, so a hotel "
           "room or a relative's house is fine. "
           "Reminders follow your phone's time, also in another time zone. "
           "On long journeys, get up and walk, or move your ankles, every hour. "
           "If you miss a few days, start again gently with fewer repetitions.", show=False),
    intent("surgery", "Before or after an operation", 7,
           ["going for surgery", "having surgery", "have surgery", "surgery next", "surgery soon", "surgery on",
            "operation next", "operation soon", "an operation", "before surgery", "before my surgery",
            "before the surgery", "before my operation", "before the operation", "after surgery", "after my surgery",
            "after the surgery", "after my operation", "after the operation", "after operation", "had surgery",
            "had an operation", "post op", "post-op", "postop", "pembedahan", "lepas operation", "lepas operate",
            "kena operate", "nak operate", "bedah"],
           ["I am going for surgery next week", "when can I start again after my operation"],
           "Before and after an operation, your surgeon's and physiotherapist's advice comes first. "
           "Before it: keep doing your exercises if they feel comfortable, unless your doctor says otherwise; being "
           "stronger helps you recover. "
           "After it: ask them when you may start again and which movements to avoid; you can switch your "
           "reminders off meanwhile, and your progress is kept. "
           "Update your health profile if the operation changes anything, such as a new hip or knee.", show=False),
    intent("period", "Exercising during your period", 7,
           ["my period", "on my period", "on period", "having my period", "period pain", "period pains",
            "period cramps", "menstrual", "menstruation", "menstruating", "menses", "haid", "datang bulan",
            "senggugut", "during my period", "during period", "pms"],
           ["I am on my period", "period pain"],
           "Exercising during your period is fine, and gentle exercise can ease cramps. "
           "Go at an easier pace on heavy or painful days, and drink water. "
           "Stop and rest if you feel dizzy or faint. "
           "Very heavy bleeding, or pain that stops you doing daily things, is worth telling your doctor.",
           show=False),
    intent("alcohol_smoking", "Alcohol and smoking", 7,
           ["alcohol", "drinking alcohol", "drank alcohol", "beer", "wine", "liquor", "whisky", "arak", "tuak",
            "hangover", "i smoke", "smoking", "smoker", "cigarette", "cigarettes", "rokok", "merokok",
            "vape", "vaping", "quit smoking", "stop smoking", "berhenti merokok"],
           ["I drank alcohol last night", "I smoke cigarettes"],
           "Alcohol and smoking both make exercise harder and less safe. "
           "Do not exercise after drinking alcohol: it upsets your balance, makes falls more likely and dries you "
           "out, so wait until the next day. "
           "Smoking makes exercise harder because your muscles get less oxygen; avoid smoking just before or after "
           "exercising. "
           "Stopping smoking helps your breathing within weeks, and your clinic or doctor can help you quit.",
           show=False),
    intent("after_treatment", "After a massage, blood donation or vaccine", 6,
           ["massage", "urut", "tukang urut", "acupuncture", "akupunktur", "cupping", "bekam", "blood donation",
            "donate blood", "donated blood", "donating blood", "derma darah", "after vaccine", "after my vaccine",
            "after the vaccine", "after a vaccine", "after vaccination", "after covid vaccine", "after my covid vaccine",
            "had my vaccine", "got my vaccine", "vaccine yesterday", "vaccine today", "just vaccinated",
            "got vaccinated", "after the jab", "after my jab", "got my flu shot", "had my flu shot",
            "flu shot today", "after booster", "after my booster", "lepas vaksin", "selepas vaksin"],
           ["I just had a massage", "I just donated blood"],
           "Gentle exercise is usually fine afterwards, with a little care. "
           "After a massage, urut or cupping: if the area is sore or bruised, rest it for a day. "
           "After giving blood: avoid hard exercise and heavy lifting for the rest of the day and drink extra "
           "water; carry on with your exercises the next day. "
           "After a vaccine: light exercise is fine if you feel well; with a fever or feeling unwell, rest until it "
           "passes, and go easy on a sore arm that day.", show=False),
    # 3.78 (symptoms test, chat_symptoms_set.py): symptoms by their kind. Before: a cramp was the general pain
    # answer, "muscle spasm in my back" and "pins and needles in my feet" were not recognised, "stitch in my
    # side" was the surgical-wound advice (stitches), "pulled hamstring" was not recognised.
    intent("cramp", "Cramp or muscle spasm", 7,
           ["cramp", "cramps", "cramped", "cramping", "muscle cramp", "leg cramp", "calf cramp", "charley horse",
            "spasm", "spasms", "muscle spasm", "back spasm", "back is locked", "locked back", "back locked",
            "kejang", "kejang otot", "otot kejang", "kaki kejang"],
           ["I got a cramp in my calf", "muscle spasm in my back"],
           "A cramp is a muscle suddenly tightening: it hurts, but usually passes within a few minutes. "
           "Stop and gently stretch the muscle: for a calf cramp, straighten your leg and pull your toes towards "
           "you, or stand with that heel down and lean on a chair. "
           "Rub the muscle, walk around once it eases, and drink some water. "
           "For a back spasm, rest in a comfortable position with a warm pack, and move gently as soon as you can. "
           "Cramps that keep coming back, or a calf that stays swollen, red or painful, need your doctor.",
           show=False),
    intent("pins_needles", "Pins and needles", 7,
           ["pins and needles", "pin and needles", "tingling", "tingle", "tingles", "tingly", "semut semut",
            "rasa semut", "kebas lepas duduk", "kebas bila duduk"]
           + [f"{p} fell asleep" for p in ("foot", "feet", "leg", "legs", "thigh", "calf", "hamstring", "back", "arm",
                                           "arms", "hand", "hands", "toes", "fingers", "bum", "buttock")],
           ["pins and needles in my feet", "my foot fell asleep"],
           "Pins and needles usually come from sitting, kneeling or lying in one position, and pass within a few "
           "minutes once you move. "
           "Change position and move the arm or leg gently before you carry on. "
           "If it does not pass, keeps coming back, or you have diabetes, tell your doctor. "
           "Sudden numbness or weakness on one side of the body, a drooping face or slurred speech needs 999 at "
           "once.", show=False),
    intent("stiffness", "Stiff joints or muscles", 7,
           ["stiff", "stiffness", "morning stiffness", "stiff in the morning", "feel stiff", "feels stiff",
            "joints are stiff", "stiff joints", "tight muscles", "muscles are tight", "muscles feel tight",
            "feels tight", "kaku", "sendi kaku", "badan kaku", "rasa kaku"],
           ["my joints are stiff in the morning", "my muscles feel tight"],
           "Stiffness is common after rest, especially in the morning and with arthritis, and usually eases as you "
           "move. "
           "Loosen up first with a warm shower or a few minutes of gentle movement, then do your exercises slowly "
           "through a comfortable range. "
           "Morning stiffness that lasts more than an hour, with swollen or warm joints, is worth telling your "
           "doctor.", show=False),
    intent("stitch", "A stitch in your side", 6,
           ["stitch in my side", "stitch in the side", "side stitch", "got a stitch", "a stitch when",
            "a stitch during", "side ache", "stitch under my ribs", "senak bila jalan", "senak masa jalan",
            "senak bila berjalan", "senak perut", "senak tepi"],
           ["I get a stitch in my side when walking"],
           "A stitch is a sharp pain under the ribs when you walk or breathe fast. "
           "Slow down, breathe out slowly and press on the sore spot: it passes within a few minutes. "
           "Avoid a big meal or a lot to drink just before exercising. "
           "Pain in your chest, or pain with breathlessness, is different: stop and call 999.", show=False),
    intent("muscle_strain", "A pulled or strained muscle", 7,
           ["pulled hamstring", "pulled my hamstring", "pulled calf", "pulled my calf", "pulled a muscle",
            "pulled muscle", "pulled my back", "strained muscle", "muscle strain", "strained my", "tweaked my",
            "otot tertarik", "salah urat"],
           ["I pulled a muscle", "I think I strained my calf"],
           "A pulled (strained) muscle usually heals in a few days to a few weeks. "
           "For the first 2 to 3 days, rest it from the movement that hurts, and use a cold pack wrapped in a cloth "
           "for 15 minutes a few times a day. "
           "Then move it gently within what is comfortable and build back up; keep exercising the rest of your "
           "body. "
           "See a doctor if you cannot walk or bear weight, there is a big bruise or swelling, or it is not better "
           "after two weeks.", show=False),
    # 3.91: sleeping badly most nights ("i can't sleep at night" was the best time to exercise, "i have
    # insomnia" not recognised). A bad night once is the tired answer ("didn't sleep well").
    intent("sleep", "Sleeping better", 6,
           ["can't sleep", "cannot sleep", "cant sleep", "insomnia", "sleep better", "trouble sleeping",
            "hard to sleep", "sleep problem", "sleep problems", "help me sleep", "tak boleh tidur", "susah tidur",
            "wake up at night", "waking up at night", "sleep well at night"],
           ["I can't sleep at night", "how can I sleep better"],
           "Regular exercise usually helps you sleep better, as long as it is not in the last hour or two before "
           "bed. "
           "Keep a regular bedtime, get some daylight in the morning, and avoid coffee or tea after mid-afternoon and "
           "large meals late at night. "
           "If you sleep badly most nights for more than a few weeks, or snore loudly and feel sleepy in the day, "
           "tell your doctor.", show=False),
    # 3.98 (everyday questions probed by hand): "should i use ice or heat" and "can i talk to a real
    # physiotherapist" were not recognised, "can this app replace my physiotherapist" was the too-hard answer,
    # "my feet are always cold" the answer for a cold or flu.
    intent("ice_heat", "Ice or heat", 6,
           ["ice pack", "heat pack", "heating pad", "tuam", "tuam panas", "tuam ais", "tuaman", "letak ais", "demah"],
           ["should I use ice or heat", "ice pack or heat pack for my knee"],
           "Ice or heat can ease pain; choose by what the pain is like. "
           "Ice is for a new injury, swelling or a joint that feels hot, in the first 2 days: wrap an ice pack or a "
           "bag of frozen peas in a towel and hold it on for 10 to 15 minutes. "
           "Heat is for stiffness and old aches, for example a stiff back in the morning or before exercising: use a "
           "warm (not hot) towel or pack for up to 20 minutes, never on a swollen or hot joint. "
           "Never put ice or heat straight on the skin, and ask your doctor first if the skin there feels numb or "
           "you have diabetes or poor circulation.", show=False),
    intent("physio_role", "The app and your physiotherapist", 8,      # over "too hard" (difficulty, 7)
           ["real physiotherapist", "ahli fisioterapi", "jumpa fisioterapi", "cari fisioterapi"],
           ["can this app replace my physiotherapist", "can I talk to a real physiotherapist"],
           "HealthGuide helps with your home exercises, but it does not replace your doctor or physiotherapist. "
           "It cannot examine you or change your treatment, and its posture check is a guide only. "
           "Keep any physiotherapy or clinic appointments you have, and tell them which exercises you do here. "
           "To see a physiotherapist, ask your doctor for a referral, or contact the physiotherapy unit of a "
           "hospital or a private clinic.", show=False),
    intent("cold_hands_feet", "Cold hands or feet", 6,
           ["kaki sejuk", "tangan sejuk", "jari sejuk", "peredaran darah"],
           ["my feet are always cold", "cold hands and feet"],
           "Cold hands or feet are common when you sit still for a long time or in an air-conditioned room. "
           "Keep them warm with socks or a blanket, and move your ankles, toes and fingers often; your exercises "
           "help the blood flow too. "
           "Tell your doctor if they are often numb, pale or bluish, if your calves hurt when you walk and ease "
           "when you rest, or if you have diabetes. "
           "A hand or foot that is suddenly cold, pale and painful needs a doctor at once.", show=False),
    # 3.98: a carer helping someone up or along ("how to help my mother stand up" was "what can you do", "how
    # do i help my mother get out of a chair" the equipment answer)
    intent("helping_someone_move", "Helping someone stand up or walk", 7,
           ["out of a chair", "out of the chair", "gait belt", "bantu bangun", "bantu berjalan", "angkat pesakit"],
           ["how do I get my mother out of a chair", "using a gait belt for my father"],
           "To help someone stand up from a chair, let them do as much as they can. "
           "Ask them to move to the front of the seat with their feet flat and slightly apart, lean forward "
           "(nose over toes) and push up on the armrests while you stand at their side and steady them at the "
           "waist; never pull on their arms or neck. "
           "Let them stand still for a moment before walking, in case they feel dizzy. "
           "When walking, stay on their weaker side, a little behind, with a hand at their waist, and let them use "
           "their walking aid. "
           "If they cannot take most of their own weight, do not lift them alone; if they have fallen and are hurt "
           "or cannot get up with a little help, call 999.", show=False),
    intent("brace_support", "Knee braces and supports", 6,
           ["knee brace", "knee guard", "knee support", "knee sleeve", "knee strap", "back brace", "back support",
            "back belt", "lumbar support", "lumbar belt", "ankle brace", "ankle support", "wrist brace",
            "wrist support", "wrist splint", "splint", "brace", "pendakap", "pendakap lutut", "sokongan lutut",
            "korset", "tali pinggang sokongan"],
           ["can I use a knee brace during exercise", "should I use a back support"],
           "You can wear a brace or support that your doctor or physiotherapist gave you while exercising, unless "
           "they said otherwise. "
           "It should feel snug, not tight: take it off if your toes or fingers tingle, go numb or change colour. "
           "A support you chose yourself is fine for a short time, but your exercises are what build the muscles "
           "that support the joint; ask your physiotherapist how long to use it.", show=False),
    # 3.72: reached only by "what does <word> mean" for a word in TERMS (engine.match); the answer is that
    # word's meaning.
    intent("word_meaning", "What a word means", 6, [], [],
           "Which word would you like explained? For example, ask \u201cwhat does flexion mean\u201d or "
           "\u201cwhat is SpO2\u201d.", show=False),
    # Matched only as the whole message (engine.match): "meds", "my med" are medicines.
    intent("med_help", "Medicine or medical help", 9,
           [],
           [],
           "Do you mean your medicine, or do you need medical help? If someone needs urgent help now, call "
           "999. For questions about medicines, please ask your doctor or pharmacist: I cannot give advice "
           "about medicines.", show=False),
    # ---- 3.67 (21 Oct): everyday random inputs (tests/chat_everyday_set.py) ------------------------------
    intent("how_are_you", "How are you?", 2,
           ["how are you", "how are you doing", "how r u", "how are u", "how r you", "how's your day",
            "hows your day", "how is your day", "what's up", "whats up", "wassup", "sup", "apa khabar",
            "dah makan", "sudah makan", "have you eaten", "you ok", "are you ok"],
           ["how are you?", "what's up"],
           "I'm well, thank you for asking! How are you feeling today? If you have a question about your "
           "exercises, pain or your plan, type it or tap a topic below.", show=False, small_talk=True),
    intent("cannot_do", "Things I cannot do", 6,
           ["call my doctor", "call the doctor", "call doctor", "call my son", "call my daughter", "call my wife",
            "call my husband", "call someone", "call for me", "book an appointment", "book appointment",
            "make an appointment", "make appointment", "set an appointment", "appointment with", "play music",
            "play a song", "play song", "play some music", "order food", "order grab", "grab food", "foodpanda",
            "whatsapp", "send message", "send a message", "send whatsapp", "text my", "message my",
            "email my doctor", "buy me", "book a taxi", "call a taxi", "call grab"],
           ["call my doctor", "book an appointment", "play music"],
           "I cannot make calls, send messages, book appointments, order things or play music. I can answer "
           "questions about your exercises, pain, safety and your plan. In an emergency, call 999 yourself or "
           "ask someone near you to call.", show=False),
    intent("app_problem", "The app is not working", 7,
           ["update app", "update the app", "app crash", "app crashed", "app crashes", "keeps crashing",
            "app hang", "app hangs", "app stuck", "app freeze", "app froze", "app not working", "app is slow",
            "app slow", "app error", "app bug", "bug", "not loading", "won't load", "cannot open the app",
            "can't open the app", "app closed by itself"],
           ["the app keeps crashing", "how do I update the app"],
           "Sorry about that. First close the app fully and open it again. Check that your internet is on. Then "
           "update the app from the Play Store, or restart your phone. If it still happens, tell the team what "
           "you were doing when it went wrong.", show=False),
    # 3.49 (11 Oct): plans stop at 65 (Terms of Use, section 2). Anyone can ask why; a restricted user
    # gets RESTRICTIONS below instead, and sees this as the first category.
    intent("age_limit", "Why plans stop at 65", 4,
           # Not "too old" or "my age" alone: "am I too old to exercise?" is the safety answer.
           ["too old for a plan", "too old for plans", "too old for the plan", "too old to get a plan",
            "too old for this app", "age limit", "age limits", "age for a plan", "age for plans", "over 65", "after 65", "past 65",
            "older than 65", "65 or older", "65 and older", "at 65", "above 65", "65 and over", "65 and above",
            "aged 65", "65 years", "65 year old", "65 years old", "plan paused", "plans paused", "paused plan",
            "paused plans", "plan is paused", "plans are paused", "why paused", "why is it paused",
            "cannot get a plan", "can't get a plan", "cant get a plan", "can not get a plan", "no plan for me",
            "not allowed a plan", "not allowed to get a plan", "why no plan", "why can i not get a plan",
            "why can't i get a plan", "terlalu tua", "had umur", "had usia", "pelan dijeda", "warga emas"],
           ["why is my plan paused", "why can't I get a plan", "am I too old for a plan", "is there an age limit"],
           "Exercise plans are for users under 65. From 65 the app does not create plans, and a plan you already "
           "have is paused, as stated in the Terms of Use (section 2): the home exercise programmes proven for "
           "people aged 65 and over were set up and followed by a health professional, and this app has none. "
           "Exercise is still good for you: please ask your doctor or a registered physiotherapist to set up a "
           "programme, or ask about a hospital or community rehabilitation service. Your profile, health "
           "logging, past results and this chat assistant stay available.",
           show=False, action={"key": "open_age_limit", "label": "Why plans stop at 65"}),

    # ---- 3.51 (14 Oct, round 18): features added since round 17 -----------------------------------
    # Wording from the Terms of Use and Privacy Notice (assets/legal/terms.json, version 1.0).
    intent("privacy_data", "Your data and privacy", 7,
           ["my data", "my information safe", "my info safe", "data safe", "data secure", "is it safe to share",
            "who can see", "who can read", "who sees", "privacy", "private", "personal data", "personal info",
            "sell my data", "sell my info", "share my data", "share my info", "where is my data",
            "data stored", "data kept", "keep my data", "keep my videos", "keep my video", "keep the video", "keep my exercise video", "keep my exercise videos",
            "videos saved", "video saved", "store my video", "store my videos", "videos deleted", "video deleted",
            "copy of my data", "my health info", "my health information", "data protection", "pdpa",
            "data saya", "maklumat saya", "privasi"],
           ["is my data safe", "who can see my health information", "do you keep my exercise videos",
            "how long do you keep my data", "where is my data stored"],
           "Only you can see your data: each account can read only its own records, and it is not sold or shared "
           "with anyone. Your profile, plans, results, chat messages, reminders and logged readings are kept on "
           "our database provider's servers (Supabase) in Singapore. Exercise videos are checked and deleted "
           "straight after the check; only the score, repetitions and feedback are kept. Your data is kept while "
           "you use the app, and an account not used for 2 years is deleted with its data. You can correct your "
           "data in the app, ask for a copy at elwinksy-wm23@student.tarc.edu.my, or delete your account. The "
           "full Privacy Notice is in Profile, Terms of Use and Privacy Notice.",
           action={"key": "open_profile", "label": "Open my profile"}),
    intent("delete_account", "Deleting your account", 8,
           ["delete my account", "delete account", "delete acc", "delete my acc", "remove my account",
            "remove account", "close my account", "close account", "deactivate", "erase my data",
            "delete my data", "delete all my data", "remove my data", "undo deleting", "recover my account",
            "deleted my account", "padam akaun", "hapus akaun", "buang akaun", "padam data"],
           ["how do I delete my account", "I want to remove my account and data", "can I undo deleting my account"],
           "Open Profile and tap Delete my account (the last item under Account settings), then confirm. Your account and everything "
           "saved with it (profile, plans, results, chat messages and reminders) is deleted at once, and this "
           "phone's reminders are cancelled. It cannot be undone: to use the app again you would register as a "
           "new user. Deleting your account also withdraws your consent to the use of your health information.",
           action={"key": "open_profile", "label": "Open my profile"}),
    intent("terms_help", "Terms of Use", 6,
           ["terms and conditions", "terms of use", "terms & conditions", "t&c", "the terms", "terms again",
            "decline the terms", "reject the terms", "not accept the terms", "what did i agree",
            "what i agreed", "agreed to", "privacy notice", "terma", "syarat"],
           ["where can I read the terms", "why must I accept the terms again", "what happens if I decline the terms"],
           "You can read the Terms of Use and Privacy Notice any time in Profile, in English or Malay. They say "
           "what the app is (not a doctor or physiotherapist), who can use it (13 and over; plans only under 65), "
           "how to exercise safely, how plans are chosen and how your data is kept. When they change, the app "
           "shows the new version at your next login and you need to accept it to continue. If you decline, you "
           "are signed out and cannot use the app, but your account is not deleted.",
           action={"key": "open_profile", "label": "Open my profile"}),
    intent("guardian_consent", "Users under 18", 7,
           ["under 18", "below 18", "my child", "my kid", "my son use", "my daughter use", "children", "i am 13", "i am 14", "i am 15", "i am 16", "i am 17", "im 13", "im 14",
            "im 15", "im 16", "im 17", "i'm 13", "i'm 14", "i'm 15", "i'm 16", "i'm 17", "13 years old",
            "14 years old", "15 years old", "16 years old", "17 years old", "teenager", "teen",
            "parent need to agree", "parents need to agree", "parent needs to agree", "parent must agree",
            "parent agree", "guardian agree", "my parent", "my parents", "guardian", "age group",
            "turned 18", "now 18", "age does not match", "age doesn't match", "age not match",
            "bawah 18", "ibu bapa", "penjaga"],
           ["I'm 15, can I use this app", "why does my parent need to agree", "I turned 18, how do I change my age group"],
           "You can use the app from 13. Under 18, a parent or legal guardian must read the Terms and agree to "
           "them, and to the use of your health information, on the Terms screen; their name is recorded. If "
           "your age in the profile does not match the age group you chose in the Terms (for example you have "
           "turned 18), the profile asks you to tap Review Terms and choose your age group again before it saves.",
           action={"key": "open_profile", "label": "Open my profile"}),
    intent("doctor_clearance", "Checking with your doctor first", 7,
           ["check with my doctor first", "check with your doctor first", "check with doctor first",
            "doctor's ok", "doctors ok", "doctor ok", "doctor said ok", "doctor says ok", "doctor agreed",
            "doctor agrees", "doctor approved", "doctor's approval", "clearance", "under control",
            "not controlled", "uncontrolled", "not under control", "terkawal"],
           ["why can't I get a plan, it says check with my doctor first", "what does under control mean",
            "my doctor said OK, how do I get a plan"],
           "Some conditions ask in your health profile whether they are under control (for example asthma or "
           "blood pressure). Under control means your symptoms are stable with your usual treatment and your "
           "doctor has not told you to avoid exercise. If you answered No for a condition that needs it, the app "
           "does not make a new exercise plan until your doctor agrees, because exercise could make it worse. "
           "When your doctor says it is OK, open Profile, change that answer to Yes and save; then you can get "
           "a plan again.",
           action={"key": "open_profile", "label": "Open my profile"}),
    intent("report_answer", "Reporting a wrong answer", 5,
           ["answer was wrong", "answer is wrong", "wrong answer", "answer wrong", "not what i asked",
            "didnt answer my question", "didn't answer my question", "did not answer my question",
            "not answer my question", "not my question", "you misunderstood", "you got it wrong",
            "not helpful", "unhelpful", "report this answer", "report an answer", "report a wrong answer",
            "report the answer", "jawapan salah",
            # 3.66, Elwin's report ("report": "are you trying to report something?") and rude remarks.
            "report", "report this", "how to report", "i want to report", "report wrong answer",
            "report a problem", "you are stupid", "you're stupid", "ur stupid", "stupid bot", "useless bot",
            "you are useless", "you're useless", "you suck", "dumb bot", "bot bodoh"],
           ["your answer was wrong", "how do I report a wrong answer", "that didn't answer my question"],
           "Sorry about that. Tap Report this answer under the answer, and if you can, say what you expected "
           "and which topic you meant. Reports are read and checked by the team before anything in my answers "
           "changes. You can also try asking in other words, or pick a topic below."),

    # ---- 3.52 (14 Oct, round 19): app features the chatbot had no answer for --------------------------
    intent("plan_reasons", "Why a plan was chosen", 6,
           ["why this plan", "why was this plan", "plan chosen", "plan was chosen", "chosen for me",
            "why recommended", "why is this plan recommended", "why recommend", "why not the other",
            "why not other plans", "why not this plan", "other plans", "left out", "excluded", "sources",
            "source", "references", "app safety rule", "guidelines behind", "evidence", "kenapa pelan ini"],
           ["why was this plan chosen for me", "why not the other plans", "what are the sources under the reasons"],
           "Each plan card has Why this plan: tap it to see why the plan suits you (the body area, your recovery "
           "stage, your goal) and the safety rules it meets. Under the plans, Why not the other plans lists each "
           "plan that was left out and why, for example harder than your safety limit or for another body area. "
           "Each reason shows the guideline behind it; tap Source to read the full reference. App safety rule "
           "means a rule of this app itself, set to keep you safe, with no published guideline of its own.",
           action={"key": "open_planning", "label": "Open treatment planning"}),
    intent("risk_level", "Your risk level", 6,
           ["risk level", "high risk", "medium risk", "low risk", "my risk", "risk calculated",
            "lower my risk", "reduce my risk", "why high risk", "bmi", "body mass index", "risiko tinggi",
            "tahap risiko"],
           ["why am I high risk", "what does my risk level mean", "what is BMI"],
           "Your risk level comes from your health profile. Low: no health conditions or physical limitations. "
           "Medium: one condition that is under control, or an arm or leg limitation. High: two or more "
           "conditions; a heart, blood pressure, stroke or nerve condition (such as Parkinson's); a condition "
           "that is not under control; or a balance problem. A higher level means gentler limits: shorter, "
           "easier sessions, smaller movement targets in the posture check and fewer plans at once. It is not "
           "a diagnosis, and it is worked out again whenever you save your profile, so keep it up to date. "
           "Your BMI (weight divided by height squared) is shown for information; it does not change your risk "
           "level.",
           action={"key": "open_profile", "label": "Open my profile"}),
    intent("safety_limits", "Your safety limits", 6,
           ["safety limit", "safety limits", "intensity limited", "my intensity", "max intensity",
            "maximum intensity", "session only", "only 20 minutes", "only 30 minutes", "session length",
            "how long can my session", "daily limits", "daily limit", "had keselamatan"],
           ["what is my safety limit", "why is my intensity limited", "why is my session only 20 minutes"],
           "Your safety limits come from your risk level: low risk, up to moderate intensity and 45 minutes a "
           "session; medium risk, up to moderate intensity and 30 minutes; high risk, up to low intensity and "
           "20 minutes. Plans with harder exercises or longer sessions are left out, and Why not the other "
           "plans says so. Home also shows daily limits for food (calories, salt and sugar) worked out from "
           "your profile. They are recalculated when you save your profile.",
           action={"key": "open_profile", "label": "Open my profile"}),
    intent("planning_questions", "The planning questions", 5,
           ["recovery stage", "stage of recovery", "mobility level", "how well can you move",
            "which goal", "what goal", "main goal", "pick a goal", "choose a goal", "what does pace",
            "pace mean", "gentle steady faster", "early intermediate advanced", "how far along",
            "which stage", "what stage", "questionnaire", "four questions", "planning questions"],
           ["what is recovery stage", "which mobility level should I choose", "what goal should I pick"],
           "Treatment planning asks: the area that needs rehabilitation (on the body map or from the list); how "
           "far along your recovery is (Early: just started recovering; Intermediate: some movement is back; "
           "Advanced: nearly back to normal); how well you can move (Low: need support to move; Moderate: move "
           "slowly on my own; High: move freely); your main goal (build strength, move more freely, better "
           "balance, ease pain or more stamina); and, if you like, your pace (Gentle, about 3 days a week; "
           "Steady, about 4; Faster, about 5). If you are not sure, choose the lower option: plans for a later "
           "stage or a higher mobility level than yours are left out, so the lower choice is the safer one.",
           action={"key": "open_planning", "label": "Open treatment planning"}),
    intent("guide_animation", "The exercise animation", 5,
           ["moving figure", "stick figure", "stickman", "stick man", "animation", "animated",
            "the figure", "moving picture", "moving drawing", "demo figure", "animasi"],
           ["what is the moving figure in the exercise", "the animation is not showing"],
           "The moving figure shows one repetition of the exercise, made from recordings of it done correctly. "
           "Copy its range and its slow, steady pace; you can go slower than it if you need to. It is shown with "
           "the exercise's steps and in the camera view before you record. If it does not appear, close the "
           "exercise and open it again; an exercise without one yet (Wrist Extension) has only its written "
           "steps."),
    intent("health_connect", "Health Connect and devices", 5,
           ["health connect", "smartwatch", "smart watch", "fitness band", "fitness tracker", "fitbit",
            "garmin", "mi band", "galaxy watch", "apple watch", "my watch", "wearable", "device connection",
            "connect my device", "link my device", "jam pintar"],
           ["how do I connect my smartwatch", "what is Health Connect"],
           "Health Connect is Android's app for sharing health data, such as steps or heart rate from a "
           "smartwatch or fitness band. Profile, Device connection shows whether it is linked. Linking a device "
           "comes with the app's Health Monitoring part, which is not available in this version yet. You do not "
           "need a watch for your exercises: the posture check only uses your phone's camera."),
    intent("app_facts", "About the app", 5,
           ["is this app free", "is it free", "free to use", "cost", "how much", "pay", "subscription",
            "iphone", "ios", "apple phone", "ipad", "android", "old phone", "my phone is old", "phone too old",
            "will it work on my phone", "contact you", "contact the team", "email you", "who do i email",
            "email for help", "support email", "customer service", "percuma", "berbayar", "hubungi"],
           ["is this app free", "can I use it on iPhone", "how do I contact you"],
           "HealthGuide is free. It is a university final-year project prototype for evaluation, made for "
           "Android phones with a camera and an internet connection; there is no iPhone version. On an older "
           "phone the posture check may take longer, but it works the same. For help, or about your data, email "
           "elwinksy-wm23@student.tarc.edu.my."),
]

# 3.53: the answer to a short follow-up ("how to", "why", "more") when there is no previous answer to
# continue (engine.pure_follow_up). Never matched by keywords.
INTENTS.append(intent(
    "clarify", "Tell me a bit more", 1, [], [],
    "Could you tell me a bit more about what you mean? For example: \"how do I do the heel raise?\", "
    "\"why is my posture score low?\" or \"is it safe to exercise with knee pain?\". You can also pick a topic "
    "below.", show=False))

# 3.52 (round 19): wider wording for existing rules, found by a probe of the app's features.
EXTRA_KEYWORDS = {
    "posture_result": ["repetitions counted", "reps counted", "count my reps", "count the reps",
                       "counts repetitions", "counts reps", "how does it count", "how is it counted"],
    "plan_and_reminders": ["restart my plan", "restart the plan", "start my plan again", "start the plan again",
                           "start over", "begin again"],
    "best_time": ["fasting", "ramadan", "ramadhan", "puasa", "berpuasa"],
    "medication": ["blood thinner", "blood thinners", "warfarin", "anticoagulant", "aspirin", "ubat cair darah"],
}
# 3.55 (15 Oct, the 10 000-message random test): how users say it in two or three words. A dict of its
# own, merged into the one above: the same topic may appear in both.
EXTRA_KEYWORDS_355 = {
    "fall_alert": ["fall message", "fall warning", "fall alert", "possible fall", "says possible fall",
                   "fall detected", "detected a fall", "fall notification"],
    "medication": ["ubat", "ubat saya", "makan ubat", "my medicine", "medicine"],
    "exit_exercise": ["go back home", "back home", "go home", "back to home", "how to exit", "exit",
                      "exit button", "keluar"],
    "verification_code": ["kod", "kod tak sampai", "tak dapat kod", "kod pengesahan", "no code"],
    "app_facts": ["email support", "support email", "free", "app price", "harga app"],
    "motivation": ["no motivation", "not motivated", "lazy", "malas", "tak semangat", "no mood to exercise"],
    "partial_reps": ["partial", "half reps", "half rep", "half repetition", "half repetitions",
                     "half counted", "reps half"],
    "adjusted_targets": ["range reduced", "reduced range", "target less", "targets less", "lower target",
                         "target lower", "target reduced", "why target", "smaller target", "smaller range"],
    "treatment_nav": ["next exercise where", "where my plan", "where is my plan", "open my plan",
                      "my treatment plan", "find my plan", "where my exercise", "where to find my plan",
                      "open the plan", "where plan"],
    "plan_exercises": ["my exercises", "what exercises", "exercise list", "list of exercises",
                       "which exercises", "senarai senaman"],
    "video_quality": ["blurry video", "video blurry", "video is blurry", "video blur", "blur video",
                      "blurry recording", "recording blurry", "looks blurry", "cannot see me in the video",
                      "can't see me in the video", "cant see me in video", "not in the video", "phone too far",
                      "camera too far", "too far away", "too close to the camera", "too dark", "video gelap"],
    "bot_identity": ["you robot", "are you a robot", "robot", "you human", "are you human", "what are you",
                     "are you real", "real person", "bot"],
    "other_activity": ["gym", "go gym", "go to the gym", "jogging", "jog", "swim", "swimming", "badminton",
                       "cycling", "futsal", "yoga class"],
    "family_help": ["son can help", "daughter can help", "carer help", "carer", "can family help",
                    "family help", "family can help", "helper"],
    "difficulty": ["tough", "so tough", "too tough", "very tough"],
    "muscle_loss": ["bed rest weak", "weak after bed rest", "after bed rest", "weak after hospital",
                    "after hospital weak", "muscles weak after", "lost muscle", "muscle loss"],
    "bladder_leak": ["pee a little", "pee", "peeing", "urine leak", "kencing sikit", "terkencing"],
    "plan_and_reminders": ["restart plan", "stop plan", "switch plan", "change plan", "change my plan",
                           "stop my plan", "cancel plan", "tukar plan"],
    "google_setup": ["sign in google", "google sign in", "login google", "google login", "sign in with google",
                     "google"],
    "joint_noise": ["bunyi lutut", "bunyi sendi", "lutut berbunyi", "sendi berbunyi", "bunyi"],
    "app_help": ["app features", "features", "the tabs", "tabs", "what can this app do", "what can app do",
                 "what does this app do", "how app works"],
    "health_log_reminder": ["remind log", "remind me to log", "log blood pressure", "log reading reminder",
                            "reminder health reading", "health reading reminder", "log my readings"],
    "eating_concern": ["cannot eat", "can't eat", "cant eat", "no appetite", "skip meals", "skip meal",
                       "tak lalu makan", "tak selera"],
    "diagnosis": ["what is wrong with me", "what's wrong with me", "whats wrong with me", "wrong with me",
                  "is it torn", "torn"],
    "fear_of_falling": ["fear falling", "fear of falling", "afraid to fall", "scared to fall", "takut jatuh"],
    "planning_questions": ["pace", "pace meaning", "which goal", "goal meaning", "stage meaning"],
    "safety": ["safety tips", "safety tip", "safe tips", "tips to be safe"],
    "hot_weather": ["very hot", "so hot", "too hot", "panas", "cuaca panas"],
    "change_password": ["new password", "tukar password", "tukar kata laluan", "update password"],
    "doctor_said": ["doctor say", "doctor says", "doctor said", "physio said", "physio say", "physio says",
                    "doktor kata"],
    "how_to": ["exercise steps", "the steps", "langkah"],
    "getting_started": ["im new", "i'm new", "new here", "new user", "baru guna"],
    "diet": ["makan apa", "nak makan apa", "what to eat", "food"],
    "language": ["chinese", "mandarin", "tamil", "chinese can", "bahasa cina"],
    "text_size": ["cant read small", "cannot read small", "can't read small", "too small to read"],
    "missed_session": ["lupa exercise", "lupa senaman", "tak buat senaman", "skip exercise", "forget to do",
                       "forget to exercise", "forget my exercises", "forgot my exercises", "forget to do my exercises"],
    "low_mood": ["burden", "a burden", "burden to", "useless", "hopeless"],
}
# 3.55 batch 4: more wording; a dict of its own, merged like the one above (no key replaces another).
EXTRA_KEYWORDS_355B = {
    "equipment": ["what do i need", "what i need", "need anything", "anything i need", "what to prepare"],
    "acknowledge": ["baik", "ok baik", "baiklah", "okok", "ok ok", "okie", "okey", "orait", "alright"],
    "body_map": ["choose part", "part body", "body part", "which part", "choose body", "pick body part"],
    "fear_of_falling": ["what if fall", "if fall", "scared fall", "afraid fall", "fear fall", "afraid getting hurt",
                        "scared getting hurt", "worried fall", "worried about falling", "scared i will fall",
                        "fall when nobody", "fall when alone"],
    "privacy_data": ["keep data", "long keep data", "how long keep", "data kept how long", "store data"],
    "how_to": ["show how", "show me how"],
    "plan_progress": ["when can stop", "when to stop", "when stop", "when can i stop"],
    "tired": ["didnt sleep", "didn't sleep", "did not sleep", "no sleep", "sleep badly", "tak cukup tidur"],
    "risk_level": ["risk", "risk say high", "risk high", "risk is high", "risk tinggi"],
    "plan_reasons": ["why recommended", "plan recommended", "recommended plan", "why suggested", "suggested plan",
                     "why this one", "why was it chosen"],
    "video_quality": ["cannot see me in video", "can't see me in video", "see me in video", "not see me",
                      "cannot see video", "can't see video", "cant see video"],
    "history_help": ["see what i did", "what i did yesterday", "what i did", "where see", "yesterday result",
                     "yesterday score", "doctor see", "can doctor see", "show my doctor", "share my results",
                     "share results"],
    "other_activity": ["can walk", "can i walk", "go walking", "go for a walk", "walk outside", "brisk walk"],
    "planning_questions": ["goal pick", "pick goal", "choose goal", "goal should", "goal to pick",
                           "which goal to choose"],
}
for _k, _v in list(EXTRA_KEYWORDS_355.items()) + list(EXTRA_KEYWORDS_355B.items()):
    EXTRA_KEYWORDS[_k] = EXTRA_KEYWORDS.get(_k, []) + _v
EXTRA_KEYWORDS |= {
    "tired": ["had covid", "after covid", "covid recovery", "recovering from covid", "a cold", "have a cold", "flu", "fever", "demam", "selsema", "batuk", "cough"],
}
# 3.67 (21 Oct): everyday random inputs (tests/chat_everyday_set.py).
EXTRA_KEYWORDS_367 = {
    "greeting": ["nice to meet you", "good morning doc", "morning doc"],
    "motivation": ["bored", "boring", "so boring", "give up", "i give up", "want to give up", "quit", "want to quit",
                   "stop trying"],
    "low_mood": ["stressed", "stress", "so stressed", "angry", "upset", "anxious", "anxiety", "frustrated",
                 "irritated", "marah", "tertekan"],
    "tired": ["nausea", "nauseous", "loya"],
    "other_activity": ["taichi", "tai chi", "qigong", "hiking", "hike", "dance", "can i dance", "play basketball",
                       "play netball", "play pickleball", "go bowling", "aerobics", "line dance"],
    "diet": ["coffee", "kopi", "tea", "teh", "teh tarik", "milo", "nasi lemak", "roti canai", "durian", "rice",
             "nasi", "protein shake", "milk", "fruit", "eat banana", "banana after", "banana before", "oats", "kuih",
             "how much water"],
    "text_size": ["font", "dark mode", "night mode", "theme"],
    "recording_help": ["upload failed", "failed to upload", "upload fail", "cannot upload video",
                       "video upload failed"],
}
for _k, _v in EXTRA_KEYWORDS_367.items():
    EXTRA_KEYWORDS[_k] = EXTRA_KEYWORDS.get(_k, []) + _v
# 3.75 (conditions test, chat_conditions_set.py): conditions the health profile does not list, by the words
# people use for them. Each gets its own advice; the closing then says to add it as "Other condition (not
# listed)", which asks for the doctor's clearance. Before: "i have gout can i exercise" was the how-to answer,
# "dementia", "migraine", "carpal tunnel" were not recognised, "frozen shoulder" was the shoulder exercise.
UNLISTED_CONDITIONS = {
    "GOUT": (["gout", "gaut", "uric acid", "asid urik"],
             "With gout, regular gentle exercise and drinking enough water help between attacks. During an attack "
             "(a hot, swollen, very painful joint), rest that joint and see your doctor; exercise the rest of your "
             "body only if it does not hurt."),
    "DEMENTIA": (["dementia", "alzheimer", "alzheimers", "alzheimer's", "nyanyuk", "demensia"],
                 "With dementia, regular exercise helps strength, balance and mood. Exercise at the same time each "
                 "day with a family member or carer close by, keep to simple steps in a clear, safe space, and stop "
                 "if you feel confused, unsteady or upset."),
    "EPILEPSY": (["epilepsy", "epileptic", "penyakit sawan", "seizure", "seizures"],
                 "With epilepsy, exercise is usually safe and good for you when your seizures are controlled. Take "
                 "your medicines as usual, drink water, avoid getting overtired, and have someone nearby when you "
                 "exercise, especially if your seizures are not well controlled."),
    "HERNIA": (["hernia", "burut"],
               "With a hernia, avoid straining, holding your breath and heavy lifting, and stop if the bulge gets "
               "bigger or hurts. Ask your doctor which exercises are safe; after hernia surgery, follow your "
               "surgeon's advice on when to start. A hernia that becomes hard, very painful or comes with vomiting "
               "needs a doctor at once."),
    "SCOLIOSIS": (["scoliosis", "curved spine", "spine is curved"],
                  "With scoliosis, gentle strengthening and stretching are usually fine and can ease stiffness. "
                  "Keep movements smooth, stop if one side starts to hurt, and a physiotherapist can show you "
                  "exercises that suit your curve."),
    "PLANTAR_FASCIITIS": (["plantar fasciitis", "plantar fascitis", "heel spur", "heel spurs"],
                          "With plantar fasciitis (heel pain), wear supportive shoes rather than going barefoot, and "
                          "gentle calf and foot stretches help. Go easy on standing exercises such as heel raises if "
                          "they make the heel pain worse."),
    "FROZEN_SHOULDER": (["frozen shoulder", "adhesive capsulitis", "bahu beku"],
                        "With a frozen shoulder, gentle movement within a comfortable range helps it loosen over "
                        "time. Do not force the arm past where it stops or bounce at the end: a pulling feeling is "
                        "fine, sharp pain is not."),
    "CARPAL_TUNNEL": (["carpal tunnel"],
                      "With carpal tunnel syndrome, keep your wrist straight, avoid gripping hard or bending the "
                      "wrist for long, and stop if the numbness or tingling in your fingers gets worse. Gentle hand "
                      "exercises are usually fine."),
    "TENNIS_ELBOW": (["tennis elbow", "golfer's elbow", "golfers elbow", "golfer elbow"],
                     "With tennis elbow, avoid gripping and lifting with your palm facing down for now, and stop any "
                     "exercise that brings on the elbow pain. It usually settles over a few weeks; a "
                     "physiotherapist can give you exercises for it."),
    "LUPUS": (["lupus"],
              "With lupus, regular gentle exercise helps with tiredness and stiff joints. Pace yourself, rest on "
              "flare days, and protect your skin from the sun if you exercise outdoors."),
    "FIBROMYALGIA": (["fibromyalgia"],
                     "With fibromyalgia, gentle exercise built up slowly is one of the best ways to ease pain and "
                     "tiredness. Start with less than you think you can do, add a little each week, and expect some "
                     "muscle ache at first."),
    "OBESITY": (["obesity", "obese", "overweight", "berat badan berlebihan"],
                "Being overweight is no reason not to start: these exercises are gentle on the joints, and you can "
                "do many of them sitting. Build up slowly; for weight loss, the food advice in the Diet section "
                "helps most."),
    "ANAEMIA": (["anaemia", "anemia", "anaemic", "anemic", "low haemoglobin", "low hemoglobin", "kurang darah"],
                "With anaemia you may tire and get out of breath sooner. Go slowly, rest between sets, and stop if "
                "you feel dizzy, faint or short of breath. Treating the anaemia usually makes exercise easier."),
    "THYROID": (["thyroid", "hypothyroid", "hyperthyroid", "hypothyroidism", "hyperthyroidism", "tiroid", "goitre",
                 "goiter"],
                "With a thyroid problem that is treated and stable, exercise is usually fine. If your thyroid is "
                "overactive and not yet controlled (a racing heart, shaking, losing weight), ask your doctor before "
                "exercising."),
    "MIGRAINE": (["migraine", "migraines", "migrain"],
                 "With migraines, do not exercise during an attack. Between attacks, regular gentle exercise, "
                 "drinking enough water and not skipping meals can help; stop if exercise brings one on. A sudden, "
                 "severe headache unlike your usual ones needs 999."),
    "EYE_CONDITION": (["glaucoma", "glaukoma", "cataract", "cataracts", "katarak", "macular degeneration"],
                      "With an eye condition, exercise in a clear, well-lit space with a support nearby. With "
                      "glaucoma, avoid positions with your head lower than your heart; after eye surgery, ask your "
                      "eye doctor when you may bend and exercise again."),
    "VARICOSE_VEINS": (["varicose veins", "varicose vein", "urat timbul"],
                       "With varicose veins, walking and ankle and calf exercises help the blood flow in your legs; "
                       "raise your legs when you rest. A calf that is suddenly swollen, red, warm and painful needs a "
                       "doctor the same day."),
    "DVT": (["dvt", "deep vein thrombosis", "blood clot", "blood clots", "pembekuan darah"],
            "After a blood clot (DVT), follow your doctor's advice; once treatment has started, walking is usually "
            "encouraged. On blood thinners you bruise and bleed more easily, so take care not to fall. Sudden "
            "breathlessness or chest pain needs 999."),
    # 3.98: "i have sciatica" was "I cannot diagnose"
    "SCIATICA": (["sciatica", "sciatic nerve", "sciatic pain", "saraf siatik"],
                 "With sciatica (nerve pain from the lower back down the leg), keep gently active: walking and your "
                 "exercises usually help more than bed rest. Avoid movements that send the pain further down your "
                 "leg, and stop if they do. See your doctor if your leg becomes weak or numb, and get help at once if "
                 "you have numbness around your bottom or lose control of your bladder or bowels."),
    "SPINE_DISC": (["spinal stenosis", "stenosis", "herniated disc", "slipped disc", "prolapsed disc", "bulging disc",
                    "disc bulge", "degenerative disc", "spondylosis", "spondylolisthesis", "disc problem",
                    "cakera tergelincir"],
                   "With a disc problem or narrowing in the spine, gentle movement and strengthening usually help "
                   "more than rest. Avoid bending and lifting at the same time, stop if pain spreads down a leg or "
                   "numbness gets worse, and get help at once if you lose control of your bladder or bowels or your "
                   "legs become weak."),
    "ANKYLOSING_SPONDYLITIS": (["ankylosing spondylitis"],
                               "With ankylosing spondylitis, daily stretching and movement are an important part of "
                               "treatment and ease morning stiffness. Move smoothly within a comfortable range and "
                               "build up gradually."),
    "TENDON": (["bursitis", "tendinitis", "tendonitis", "trigger finger", "de quervain", "de quervain's"],
               "With an irritated tendon or bursa, rest from the movement that brings on the pain for a while, then "
               "build up gently. Mild discomfort that settles quickly is fine; sharp or worsening pain means stop."),
    "NEUROPATHY": (["neuropathy", "peripheral neuropathy", "nerve damage in my feet", "nerve damage in my legs"],
                   "With neuropathy (numb or tingling feet), check your feet every day, wear well-fitting shoes, and "
                   "keep a support within reach because balance can be harder. Sudden new numbness or weakness needs "
                   "999."),
    "FOOT_SHAPE": (["bunion", "bunions", "flat feet", "flat foot", "kaki leper"],
                   "With bunions or flat feet, wear wide, supportive shoes for standing exercises, or do them "
                   "barefoot on a non-slip floor if that is more comfortable. Stop if your foot hurts more "
                   "afterwards."),
    "MENOPAUSE": (["menopause", "menopausal", "hot flushes", "hot flashes", "monopaus", "putus haid"],
                  "Around the menopause, strength and standing exercises help protect your bones and lift your "
                  "mood. Exercise in a cool place and drink water if you get hot flushes."),
    "CHOLESTEROL": (["cholesterol", "high cholesterol", "kolesterol", "kolesterol tinggi"],
                    "With high cholesterol, regular exercise like your plan helps, together with the food advice in "
                    "the Diet section. If you also have heart disease, keep to the intensity in your plan."),
    "FATTY_LIVER": (["fatty liver", "hati berlemak"],
                    "With fatty liver, regular exercise and healthy eating are the main treatment: these exercises "
                    "help, and the Diet section has food advice."),
    "SLEEP_APNOEA": (["sleep apnea", "sleep apnoea", "cpap"],
                     "With sleep apnoea, regular exercise helps your sleep and energy. Use your breathing machine at "
                     "night as prescribed, and go gently on days you feel very sleepy."),
    "NERVE_MUSCLE": (["cerebral palsy", "polio", "muscular dystrophy", "myasthenia", "guillain barre",
                      "guillain-barre", "spinal cord injury"],
                     "With a long-term nerve or muscle condition, exercises chosen with your physiotherapist suit "
                     "you best. Use a support, rest between sets, and stop if you feel unsteady or much more tired "
                     "than usual."),
}
# Heart and lung conditions the profile lists under another name.
LISTED_NAMES = {"HEART_DISEASE": ["heart failure", "angina", "atrial fibrillation", "afib", "heart bypass",
                                  "bypass surgery", "lemah jantung", "jantung lemah", "heart valve", "valve problem"],
                "ASTHMA": ["asma"]}
CONDITION_CLOSING_OTHER = ("This condition is not on the health profile's list: add it as \u201cOther condition "
                           "(not listed)\u201d in your profile, and ask your doctor whether your plan suits you "
                           "before you start.")


# 3.77 (medicines test, chat_medicines_set.py): medicines by the names people in Malaysia take them under,
# generic and brand. They are the medicines answer's keywords (still "ask your doctor or pharmacist") and
# count as medicine for the overdose check ("i took 30 amlodipine" was not recognised; overdoses 205/512).
DRUG_NAMES = """aspirin cardiprin ibuprofen nurofen brufen naproxen diclofenac voltaren arcoxia etoricoxib celebrex
celecoxib ponstan mefenamic tramadol codeine morphine gabapentin pregabalin lyrica neurontin
metformin glucophage gliclazide diamicron sitagliptin januvia empagliflozin jardiance dapagliflozin
forxiga lantus mixtard novorapid amlodipine norvasc losartan cozaar perindopril coversyl lisinopril
enalapril hydrochlorothiazide bisoprolol atenolol metoprolol propranolol nifedipine frusemide
furosemide lasix spironolactone diuretic diuretics statin statins atorvastatin lipitor simvastatin
rosuvastatin crestor clopidogrel plavix rivaroxaban xarelto apixaban eliquis dabigatran isosorbide
digoxin nitroglycerin prednisolone prednisone dexamethasone steroid steroids cortisone ventolin
salbutamol seretide symbicort thyroxine levothyroxine euthyrox carbimazole allopurinol colchicine
alendronate fosamax zolpidem stilnox diazepam valium antidepressant antidepressants sertraline
fluoxetine escitalopram amitriptyline levodopa madopar sinemet jamu""".split()
DRUG_PHRASES = ["beta blocker", "beta blockers", "water pill", "water pills", "sleeping pill", "sleeping pills",
                "tongkat ali", "ubat tradisional", "ubat kampung", "chinese medicine", "herbal medicine",
                "calcium tablets", "vitamin d", "steroid injection"]


# 3.74 (numbers test): "can i exercise 3 times a day", "is 20 minutes enough". (3.67's heart rate words
# went from safety to health_readings.)
EXTRA_KEYWORDS_374 = {
    # 3.91: mood, belly fat, doing more than the plan
    "low_mood": ["help my mood", "improve my mood", "mood better", "exercise for depression", "exercise and mood",
                 # 3.95: "how can i get help for my mental health" was about the assistant
                 "mental health", "kesihatan mental", "my mental", "emotional health"],
    "calories": ["belly fat", "lose fat", "tummy fat", "perut buncit", "lose belly"],
    "difficulty": ["more than my plan", "more than the plan", "do extra", "extra exercises", "add more exercises"],
    # 3.87: an upset stomach is feeling unwell (skip and rest); "anxious about falling" is the fear of falling
    "tired": ["diarrhoea", "diarrhea", "stomach ache", "stomachache", "upset stomach", "food poisoning"],
    "fear_of_falling": ["anxious about falling", "nervous about falling", "anxious i will fall"],
    # 3.79: app questions in another topic's words ("can i use it on tablet" was the medicines answer, "how to
    # contact support" safety, "share my progress with my doctor" the plan's progress).
    "app_facts": ["on tablet", "on a tablet", "on my tablet", "use a tablet", "android tablet", "samsung tab",
                  "on tab", "contact support", "how to contact", "helpdesk", "help desk", "who to contact"],
    "history_help": ["share my progress", "show my progress", "progress with my doctor", "send my results",
                     "send my progress", "show the doctor my results"],
    # 3.78: soreness the day after; a joint that locks or catches
    "pain_mild": ["doms", "delayed onset muscle soreness", "sore the next day", "sore 2 days after", "sore two days after"],
    "joint_noise": ["knee locks", "knee locking", "knee gets stuck", "knee catches", "joint locks", "joint locking",
                    "knee locked"],
    "app_problem": ["screen stuck", "screen gets stuck", "screen is stuck", "screen frozen", "screen froze",
                    "stuck on the screen", "stuck on loading", "page stuck", "button not working"],
    "medication": DRUG_NAMES + DRUG_PHRASES,
    "condition_advice": [w for words, _ in UNLISTED_CONDITIONS.values() for w in words]
                        + [w for words in LISTED_NAMES.values() for w in words],
    "neck_not_covered": ["whiplash"],
    "hot_weather": ["temperature outside", "outside temperature", "degrees outside", "hot outside", "hot today"],
    "how_often": ["times a day", "times per day", "days a week", "days per week", "minutes a day",
                  "minutes per day", "minutes enough", "enough minutes"],
    # 3.98: everyday questions probed by hand ("can old people exercise", "is walking enough", "i wake up many
    # times at night", "i keep tripping", "i miss my wife", "it says i did 0 reps", "is this app approved by
    # doctors": not recognised, or another topic)
    "safety": ["seniors", "senior citizen", "senior citizens", "for the elderly"],
    "other_activity": ["brisk walk", "brisk walking", "jalan kaki", "jalan pagi", "berjalan kaki"],
    "sleep": ["sleepless", "terjaga malam", "selalu terjaga"],
    "posture_result": ["0 reps", "0 rep", "0 repetitions"],
    "language": ["tukar bahasa", "bahasa lain"],
    "bot_identity": ["siapa buat", "siapa yang buat", "siapa cipta", "siapa reka", "siapa bina"],
    "recording_help": ["kamera", "kamera tak nampak", "tak nampak saya"],
}
EXTRA_KEYWORDS_374["safety"] += ["orang tua buat", "orang tua boleh", "untuk orang tua", "orang tua senaman"]
# 3.98 (exercise probe): exercises or a plan for a body part are chosen on the body map (the plan's own area lists
# the plan: engine.plan_intents); "can i use armrest" was not recognised.
EXTRA_KEYWORDS_374["equipment"] = EXTRA_KEYWORDS_374.get("equipment", []) + [
    "armrest", "armrests", "arm rest", "arm rests"]
# 3.98 (third probe): "i had knee surgery 6 weeks ago" was "I cannot diagnose"; "why did the app give me this plan"
# the plan's exercises; "can i pause my plan" the plan's exercises; "how slow should i go" not recognised.
EXTRA_KEYWORDS_374["surgery"] = EXTRA_KEYWORDS_374.get("surgery", []) + [
    "kena bedah", "dibedah", "lepas bedah", "selepas pembedahan"]
EXTRA_KEYWORDS_374["plan_and_reminders"] = EXTRA_KEYWORDS_374.get("plan_and_reminders", []) + [
    "pause my plan", "pause the plan", "pause plan", "pause this plan"]
EXTRA_KEYWORDS_374["how_to"] = EXTRA_KEYWORDS_374.get("how_to", []) + ["laju atau perlahan", "perlahan atau laju"]
EXTRA_KEYWORDS_374["fear_of_falling"] += ["tersadung", "selalu tersadung", "after fall", "after my fall"]
EXTRA_KEYWORDS_374["low_mood"] += ["rindu", "rindu keluarga", "rindu arwah"]
EXTRA_KEYWORDS_374["app_facts"] += ["can i trust this app"]
# 4.07 (twelfth probe, mixed Malay and English)
for _k, _v in {"difficulty": ["terlalu senang", "senang sangat", "mudah sangat", "terlalu mudah"],
               "app_problem": ["app keluar sendiri", "aplikasi keluar sendiri", "keluar sendiri"],
               "app_help": ["aplikasi ni untuk apa", "apps ni untuk apa", "app ni untuk apa"]}.items():
    EXTRA_KEYWORDS_374[_k] = EXTRA_KEYWORDS_374.get(_k, []) + _v
# 4.06 (eleventh probe): the app, the account and feelings in everyday Malay
for _k, _v in {"forgot_password": ["tak boleh log masuk", "tak dapat log masuk", "gagal log masuk", "tak boleh masuk akaun",
                                   "tak dapat masuk akaun"],
               "account_help": ["log masuk", "log keluar", "daftar akaun", "buat akaun", "cipta akaun", "daftar masuk"],
               "history_help": ["keputusan lama", "tengok keputusan", "lihat keputusan", "sejarah sesi", "hantar keputusan",
                                "keputusan kepada doktor", "tunjuk keputusan"],
               "profile_help": ["tukar berat badan", "kemaskini berat badan", "tukar berat", "kemaskini berat",
                                "tukar tinggi", "kemaskini profil"],
               "risk_level": ["risiko sederhana", "risiko rendah", "risiko tinggi", "tahap risiko"],
               "reminders_help": ["tetapkan peringatan", "pasang peringatan", "buat peringatan",
                                  "tutup peringatan", "matikan peringatan", "hentikan peringatan", "tukar peringatan"],
               "app_problem": ["aplikasi tergantung", "app tergantung", "skrin tergantung", "tutup sendiri",
                               "skrin hitam", "skrin gelap", "skrin putih", "aplikasi rosak", "tak boleh buka aplikasi"],
               "motivation": ["bosan", "rasa bosan"],
               "low_mood": ["risau", "rasa risau", "bimbang", "cemas", "gelisah"]}.items():
    EXTRA_KEYWORDS_374[_k] = EXTRA_KEYWORDS_374.get(_k, []) + _v
# 4.05 (tenth probe, Malay)
for _k, _v in {"wrong_exercise": ["salah senaman", "senaman salah"],
               "recording_help": ["letak telefon", "telefon letak", "letak phone", "phone letak"],
               "how_to": ["rehat antara", "rehat antara ulangan", "rehat antara set", "lutut masuk ke dalam",
                          "lutut masuk dalam"],
               "plan_and_reminders": ["berhenti pelan", "berhenti plan", "henti pelan"],
               "missed_session": ["terlupa senaman", "lupa senaman", "lupa buat senaman"]}.items():
    EXTRA_KEYWORDS_374[_k] = EXTRA_KEYWORDS_374.get(_k, []) + _v
# 4.00: someone holding the phone
EXTRA_KEYWORDS_374["recording_help"] += ["hold the phone", "holding the phone", "hold my phone", "pegang phone",
                                         "pegang telefon"]
EXTRA_KEYWORDS_374["app_problem"] = EXTRA_KEYWORDS_374.get("app_problem", []) + ["phone panas", "telefon panas"]
# 3.99 (sixth probe): everyday Malay and English for feelings, reminders and the account
for _k, _v in {"low_mood": ["sunyi", "rasa sunyi", "kesunyian", "keseorangan", "sorang sorang",
                            "takut tak boleh jalan"],
               "session_done": ["dah buat senaman", "dah buat semua senaman", "sudah buat senaman", "dah siap buat",
                                "proud of myself"],
               "reminder_late_or_off": ["peringatan tak keluar", "notifikasi tak keluar", "notification tak keluar",
                                        "peringatan tak masuk", "tak dapat peringatan", "tak terima peringatan"],
               "app_help": ["susah guna", "susah nak guna", "sukar guna", "sukar digunakan",
                            # 4.03: "anak saya yang pasang aplikasi ini, saya tak tahu macam mana nak guna"
                            "macam mana nak guna", "tak tahu nak guna", "cara guna", "cara nak guna", "tak reti guna",
                            "tak pandai guna", "pasang aplikasi"],
               "pardon": ["tak faham", "tidak faham", "tak paham", "x faham", "kurang faham", "tak fhm"],
               "goodbye": ["selamat malam", "selamat tidur", "jumpa lagi"],
               "account_help": ["telefon baru", "handphone baru", "tukar phone"]}.items():
    EXTRA_KEYWORDS_374[_k] = EXTRA_KEYWORDS_374.get(_k, []) + _v

EXTRA_KEYWORDS_374["posture_result"] += ["markah", "markah saya", "markah rendah", "skor saya", "kenapa skor"]
for _k, _v in EXTRA_KEYWORDS_374.items():
    EXTRA_KEYWORDS[_k] = EXTRA_KEYWORDS.get(_k, []) + _v

# 3.98: families of phrases, as regular expressions over the cleaned message (engine.clean: lower case, Malay and
# synonyms mapped, "lift" -> "raise"). A match counts as a three-word keyword (engine.keyword_match). Patterns are
# not counted in the other-domain weights (build_domain_words), so the everyday words in them ("help", "him",
# "people") stay as likely in other domains as before: written out as keywords, 600 phrases had let 37 more
# questions of other domains through.
_PERSON = (r"(?:my (?:mother|father|mum|mom|dad|wife|husband|grandmother|grandfather|grandma|grandpa|parents?|"
           r"patient)|him|her|them|someone|somebody|a person|an elderly(?: person)?|an old person)")
_PART = (r"(?:knees?|shoulders?|back|lower back|hips?|legs?|arms?|hands?|wrists?|ankles?|elbows?|feet|foot|core|"
         r"neck)")
PATTERNS = {
    "helping_someone_move": [
        rf"\bhelp(?:ing)? {_PERSON} (?:to )?(?:stand|get up|walk|get out of|sit down|move|get into bed|go to the toilet)\b",
        # "lift my mother", not "lift her arms" (her: the person's, caregiver test)
        r"\b(?:raise|carry) (?:my (?:mother|father|mum|mom|dad|wife|husband|grandmother|grandfather)|someone|"
        r"somebody|a person|the patient)\b", r"\b(?:raise|carry) (?:her|him|them) (?:up|out of|from|into|onto|off)\b"],
    "family_help": [rf"\bhelp(?:ing)? {_PERSON} (?:to |with )?(?:do )?(?:the |my |his |her |their )?exercis"],
    "surgery": [r"\b(?:knee|hip|back|spine|spinal|shoulder|ankle|foot|wrist|hand|elbow|neck|heart|bypass|hernia|"
                r"cataract|eye|acl|ligament|stomach|abdominal|cancer|bowel|brain) (?:surgery|operation|op)\b",
                r"\b(?:surgery|operation) (?:\w+ )?(?:days?|weeks?|months?) ago\b", r"\boperated on\b"],
    "low_mood": [r"\bmiss(?:ing)? (?:my (?:late )?(?:wife|husband|family|children|kids|grandchildren|grandkids|son|"
                 r"daughter|mother|father|mum|mom|dad|parents|friends?|partner|old life)|him|her|them|home)\b"],
    "body_map": [rf"\b(?:exercises?|plans?) for (?:my |the )?{_PART}\b"],
    "safety": [r"\bold(?:er)? (?:people|person|persons|adults?|folks)\b"],
    "other_activity": [r"\b(?:is|are) walking (?:good|enough|ok|okay|better)\b", r"\bwalking (?:is )?(?:good|enough)\b",
                       r"\b(?:go|going|went) (?:for )?(?:a )?walk(?:s|ing)?\b", r"\bwalk (?:every day|daily)\b",
                       r"\b(?:morning|evening) walks?\b", r"\bwalk(?:ing)? instead\b",
                       # 4.01: "is it ok to walk", "walk safe or not" were not recognised
                       r"\b(?:ok|okay|safe|good|fine|alright) (?:for me )?to (?:go )?(?:for a )?walk(?:ing)?\b",
                       r"\bwalk(?:ing)? (?:is )?(?:ok|okay|safe|fine|alright)\b"],
    "app_facts": [r"\b(?:app|it) (?:is )?(?:approved|certified|legit|legitimate|verified)\b",
                  r"\b(?:approved|certified|verified|made) by (?:a )?doctors?\b", r"\b(?:doctor|medically) approved\b"],
    "ice_heat": [r"\b(?:put|apply|use|using|putting) (?:an? |some )?(?:ice|heat|hot pack|cold pack|heat pack|ice pack)\b",
                 r"\bice or heat\b", r"\bheat or ice\b", r"\b(?:ice|cold|hot|heat|warm) (?:packs?|compress(?:es)?|pads?)\b",
                 r"\bhot water bottle\b", r"\bice (?:it|my|on my)\b"],
    "physio_role": [r"\b(?:find|see|need|get|meet) (?:a |my )?physiotherapist\b", r"\bphysiotherapist near\b",
                    r"\breplace (?:my |a |the )?(?:physiotherapist|physiotherapy|doctor)\b",
                    r"\binstead of (?:going to |seeing )?(?:a |my )?(?:physiotherapist|physiotherapy)\b",
                    r"\b(?:talk|speak) to (?:a |my )?(?:real )?physiotherapist\b",
                    r"\bstill (?:need|go to|going to) (?:a |my )?(?:physiotherapist|physiotherapy)\b",
                    r"\bstop going to (?:physiotherapist|physiotherapy)\b"],
    "cold_hands_feet": [r"\bcold (?:hands?|feet|foot|toes|fingers)\b",
                        r"\b(?:hands?|feet|foot|toes|fingers) (?:are |is |feel |feels |always |so |very |too )*cold\b",
                        r"\b(?:poor|bad|blood) circulation\b"],
    "sleep": [r"\bwak(?:e|ing) up (?:many times|often|a lot|in the night|too early|very early)\b",
              r"\bkeep waking up\b", r"\b(?:can't|cannot|don't|not) sleep(?:ing)? well\b",
              r"\btidur tak lena\b", r"\btak lena tidur\b"],
    "pins_needles": [r"\bnumb(?:ness)? (?:every night|every morning|on and off|comes and goes)\b"],
    "language": [r"\b(?:change|switch) (?:the )?language\b", r"\b(?:other|another) language\b"],
    "fear_of_falling": [r"\b(?:keep|always|often) trip(?:ping)?\b", r"\btrip(?:ping)? (?:a lot|often|over things)\b"],
    "plan_reasons": [r"\b(?:give|gave|gives) me this plan\b",
                     r"\b(?:choose|chose|chooses|choosing|pick|picked|picks) (?:my|the|this) plan\b",
                     r"\bplans? (?:are |were |is |was )?chosen\b", r"\bhow (?:does|did) the app (?:choose|pick)\b",
                     r"\bwhy (?:did|do) i get this plan\b"],
    "plan_and_reminders": [r"\bstop a plan\b", r"\btake a break from (?:my|the) plan\b", r"\bhold my plan\b"],
    # 3.99: "i want to exercise" was the body map (a loose likeness to "exercise for my hand"); not "i don't want
    # to exercise" (motivation) or "want to exercise my hand" (the body map)
    "getting_started": [r"(?<!don't )(?<!not )(?<!never )\bwant to (?:start )?exercis(?:e|ing)\b(?! (?:my|the|for) )"],
    "app_help": [r"\b(?:app|apps|this) (?:is |so |very |too )*(?:hard|difficult|confusing) to use\b"],
    "session_done": [r"^(?:\w+ )?i did it$"],
    # 4.06: "set peringatan" as a pattern ("set" as a keyword let "can i set up mobile deposits" through)
    "reminders_help": [r"\bset peringatan\b"],
    # 4.07: "boleh buat masa period" (cleaned "time period"): a pattern, as "time" is a word of every domain
    "period": [r"\btime period\b"],
    # "new" as a keyword had let "chinese new year" and "new checks" through (other-domain weights)
    "account_help": [r"\b(?:a |my )?new (?:phone|handphone|mobile)\b", r"\b(?:changed?|switched?) (?:my )?phones?\b"],
    # 4.00 (seventh probe, the posture check): "should i wear tight clothes for recording" was the pain answer,
    # "there are other people in the room" equipment, "the picture is blurry" and "my phone gets hot" not
    # recognised, "the analysis takes very long" how often, "my score changed when i redid it" swelling ("red")
    "video_quality": [r"\b(?:wear|wearing|clothes|clothing|shirt|pants|trousers|sarong|baju)\b.{0,30}\b(?:record|recording|video|camera)\b",
                      r"\b(?:tight|loose|baggy|fitted) (?:clothes|clothing|shirt|pants|trousers)\b",
                      r"\b(?:other people|someone else|people|family|kids|children|cat|dog|pet)s? (?:are |is )?(?:in|walk(?:ed|ing|s)? (?:in front of|into|across)) (?:the |my )?(?:room|picture|video|frame|background|camera)\b",
                      r"\b(?:picture|video|image|recording|camera)(?: is| looks)? (?:blurry|blurred|blur|kabur)\b"],
    # 4.00: "my knee is warm" was the safety answer (warm up)
    "pain_swelling": [r"\b(?:knee|joint|ankle|hip|elbow|wrist|shoulder)s? (?:is |are |feels? |feel |getting |gets )?(?:very |so )?(?:warm|hot)\b"],
    "app_problem": [r"\banaly[sz](?:is|ing|e)\b.{0,20}\b(?:long|slow|forever|stuck|taking)\b",
                    r"\bphone (?:gets |is |getting |becomes |goes )?(?:very |so |too )?(?:hot|warm|overheat|overheating|panas)\b"],
    # 4.01: "why only 20 min" (the daily limit) was how often; also typed "why olby 20 min"
    "safety_limits": [r"\bwhy (?:\w{2,6} )?\d+ ?(?:min|mins|minutes)\b"],
    # 3.99: "i don't want to exercise today" was the plan's exercises ("exercises today")
    "motivation": [r"\b(?:don't|do not|not|never) (?:really )?(?:want|feel like) (?:to )?(?:do (?:my |the |any )?)?exercis"],
    "posture_result": [r"\bscore (?:changed|went down|dropped|is different|different|lower|went up)\b",
                       r"\b(?:different|lower|another) score\b", r"\bcounted (?:only )?\d+\b",
                       r"\b(?:zero|none|no) (?:reps?|repetitions?) (?:counted|recorded)\b",
                       r"\b(?:did|says|shows|counted) (?:0|zero)\b", r"\bcounted (?:none|nothing)\b",
                       r"\b(?:didn't|did not) count any\b"],
    "how_to": [r"\bhow (?:fast|slow|slowly|quickly) (?:should|do|to|must|can)\b", r"\bspeed of each\b"],
}


def _no_repeated_keys():
    import ast
    for node in ast.walk(ast.parse(Path(__file__).read_text(encoding="utf-8"))):
        if isinstance(node, ast.Dict):
            keys = [k.value for k in node.keys if isinstance(k, ast.Constant)]
            repeated = {k for k in keys if keys.count(k) > 1}
            assert not repeated, f"line {node.lineno}: repeated keys {repeated} (the later one replaces the earlier)"


_no_repeated_keys()
for _i in INTENTS:
    _i["keywords"] += [k for k in EXTRA_KEYWORDS.get(_i["key"], []) if k not in _i["keywords"]]
    if PATTERNS.get(_i["key"]):
        _i["patterns"] = PATTERNS[_i["key"]]
# Answered when asked, but not offered as topic chips (the list stays short, as before 3.51).
for _i in INTENTS:
    if _i["key"] in {"privacy_data", "delete_account", "terms_help", "guardian_consent", "doctor_clearance",
                     "report_answer", "plan_reasons", "risk_level", "safety_limits", "planning_questions",
                     "guide_animation", "health_connect", "app_facts"}:
        _i["show"] = False

# What a restricted user is told instead (the app sends the restriction it got from the recommender).
# "replace": answers that would send the patient to a plan, a recording or plan reminders; "note_on":
# general exercise advice that stays, with a line first. Plan-specific rules (plan_*) are replaced too,
# and exercise:* get the note. Safety answers (crisis, red flags, poisoning) always come first.
RESTRICTIONS = {
    "AGE_65_PLUS": {
        "title": "Your plans are paused",
        "answer": "Your exercise plans are paused because plans are for users under 65, as stated in the Terms of "
                  "Use (section 2). The home exercise programmes proven for people aged 65 and over were set up "
                  "and followed by a health professional, and this app has none. Please ask your doctor or a "
                  "registered physiotherapist to set up a programme for you, or ask about a hospital or community "
                  "rehabilitation service. You can still use your profile, health logging, reminders to log your "
                  "health readings, your past results and this chat assistant.",
        "action": {"key": "open_age_limit", "label": "Why plans are paused"},
        "replace": ["age_limit", "getting_started", "how_to", "missed_session", "recording_help", "treatment_nav",
                    "multiple_plans", "body_map", "plan_and_reminders", "partial_reps", "video_quality",
                    "wrong_exercise", "exit_exercise", "how_often", "adjusted_targets", "reminders_help",
                    "family_help"],
        "note": "Your plans are paused (plans are for users under 65, Terms of Use section 2), so please exercise "
                "under the guidance of your doctor or a physiotherapist.",
        "note_on": ["safety", "condition_advice", "equipment", "difficulty", "tired", "weakness_balance", "best_time",
                    "muscle_loss", "fear_of_falling", "other_activity", "hot_weather", "motivation", "app_help",
                    "pain_or_discomfort", "pain_mild", "doctor_said"],
    },
}

GOAL_TEXT = {
    "MOBILITY": "move your joints more freely",
    "STRENGTH": "build the strength of your muscles",
    "BALANCE": "improve your balance and steadiness",
    "PAIN_RELIEF": "ease discomfort and support your back",
    "ENDURANCE": "build your stamina for daily activities",
}

# Alternative names patients use for each exercise (matched as whole phrases; longer phrases win).
ALIASES = {
    "sit_to_stand": ["sit to stand", "sit-to-stand", "chair stand", "chair stands", "chair squat", "stand up from chair",
                     "standing up from a chair", "stand up from the chair", "sitting to standing", "sit stand"],
    "shoulder_abduction": ["shoulder abduction", "side arm raise", "side arm raises", "lateral arm raise",
                           "lateral raise", "arm raise to the side", "raise my arms to the side", "arms sideways",
                           "raise arms side", "arms to the side", "arm side raise"],
    "shoulder_flexion": ["shoulder flexion", "front arm raise", "front arm raises", "forward arm raise",
                         "raise my arms forward", "arms forward", "arm raise to the front"],
    "hip_abduction": ["hip abduction", "standing hip abduction", "side leg raise", "side leg raises",
                      "leg raise to the side", "lift my leg to the side", "leg sideways", "leg out to the side",
                      "leg out side", "leg to the side"],
    "knee_extension": ["knee extension", "seated knee extension", "knee extensions", "straighten my knee",
                       "straightening my knee", "leg extension", "seated leg raise", "leg straightening"],
    "wrist_extension": ["wrist extension", "wrist lift", "lift my wrist", "lifting the wrist", "wrist exercise",
                        "wrist exercises", "bend my wrist up", "wrist up", "lift wrist"],
    "hand_open_close": ["hand open and close", "open and close", "open my hand", "opening the hand", "hand opening",
                        "make a fist", "open close hand", "finger exercise", "finger exercises", "fingers",
                        "hand exercise", "hand exercises", "grip exercise", "open close"],
    "elbow_flexion": ["elbow flexion", "bicep curl", "bicep curls", "biceps curl", "arm curl", "arm curls", "curl",
                      "curls", "elbow bend", "bend my elbow"],
    "wall_push_up": ["wall push up", "wall push-up", "wall pushup", "wall push ups", "wall push-ups", "wall pushups",
                     "push up against the wall", "push up on the wall", "close to the wall", "far from the wall",
                     "distance from the wall"],
    "heel_raise": ["heel raise", "heel raises", "calf raise", "calf raises", "tiptoe", "tiptoes", "toe raise",
                   "rise on my toes", "stand on my toes", "my heels", "raise my heels",
                   "lift my heels", "heels up", "heels go", "how high heels", "how high my heels"],
    "mini_squat": ["mini squat", "mini squats", "half squat", "small squat", "partial squat", "squat", "squats"],
    "seated_marching": ["seated marching", "seated march", "sitting march", "marching while sitting",
                        "march while sitting", "march sitting down", "march", "marching"],
    "glute_bridge": ["glute bridge", "glute bridges", "hip bridge", "bridge exercise", "bridging", "bridge"],
    "tandem_stance": ["tandem stance", "tandem stand", "heel to toe", "heel-to-toe", "one foot in front of the other",
                      "balance stand", "heel toe", "heel toe stand", "stand heel toe"],
    "bird_dog": ["bird dog", "bird-dog", "birddog", "bird dogs", "opposite arm and leg"],
    "step_up": ["step up", "step-up", "step ups", "step-ups", "stepping up", "stair step", "my step",
                "step height", "high step", "step too high", "step is"],
    "march_in_place": ["march in place", "marching in place", "march on the spot", "marching on the spot",
                       "standing march", "marching standing", "march", "marching", "march place",
                       "march spot", "marching place", "marching spot"],
}
# 3.80: the exercises described in everyday words, English and Malay ("walking on the spot", "the one where i
# kneel on all fours", "push against the wall", "small knee bend" were not recognised or another topic).
for _k, _v in {
    "glute_bridge": ["lift my hips", "lift my bottom", "lift my bum", "bum lift", "butt lift", "hip lift",
                     "hips up lying down", "angkat punggung"],
    "heel_raise": ["up on my toes", "on my toes", "toes up and down", "angkat tumit", "jengket", "jinjit"],
    "sit_to_stand": ["sitting down standing up", "sit down stand up", "stand up sit down", "get up from the chair",
                     "get up from a chair", "duduk bangun", "bangun dari kerusi"],
    "wall_push_up": ["push against the wall", "push the wall", "pushing the wall", "wall press", "tolak dinding"],
    "bird_dog": ["all fours", "on all fours", "hands and knees", "kneel on all fours", "crawling position",
                 "merangkak"],
    "march_in_place": ["walking on the spot", "walk on the spot", "walking in place", "walk in place",
                       "jalan setempat"],
    "seated_marching": ["lift knees while sitting", "lift my knees sitting", "lift my knees while sitting",
                        "knee lifts sitting", "sitting knee lift", "sitting knee lifts"],
    "knee_extension": ["straighten leg while sitting", "straighten my leg sitting", "straighten my leg while sitting",
                       "kick out my leg", "leg kick sitting", "luruskan kaki"],
    "mini_squat": ["small knee bend", "small knee bends", "knee bends", "bend my knees a little", "shallow squat",
                   "cangkung sikit"],
    "tandem_stance": ["feet in line", "feet in a line", "one foot in front"],
    "step_up": ["step onto a stair", "step onto the step", "step on and off", "naik tangga"],
    "shoulder_flexion": ["arm up in front", "arms up in front", "lift my arms in front", "raise arms in front",
                         "angkat tangan ke depan"],
    "shoulder_abduction": ["angkat tangan ke tepi"],
    "hand_open_close": ["squeeze my hand", "genggam tangan", "buka tutup tangan"],
}.items():
    ALIASES[_k] = ALIASES[_k] + [a for a in _v if a not in ALIASES[_k]]
# 4.04: the exercises by their Malay names (ninth probe: "cara buat tekan dinding", "cara angkat kaki ke sisi",
# "cara buat separuh cangkung", "cara buat jambatan", "cara berkawad di tempat" were not recognised)
for _k, _v in {
    "wall_push_up": ["tekan dinding", "tekan tubi dinding", "push up dinding"],
    "shoulder_abduction": ["angkat tangan ke sisi", "angkat lengan ke sisi", "angkat lengan ke tepi",
                           "depakan tangan"],
    "shoulder_flexion": ["angkat lengan ke depan", "angkat tangan ke atas", "angkat lengan ke atas"],
    "hip_abduction": ["angkat kaki ke sisi", "angkat kaki ke tepi", "hayun kaki ke sisi"],
    "elbow_flexion": ["bengkokkan siku", "bengkok siku", "lentur siku", "lenturan siku"],
    "mini_squat": ["separuh cangkung", "cangkung separuh", "squat kecil", "cangkung kecil"],
    "glute_bridge": ["jambatan", "angkat pinggul", "jambatan punggung"],
    "tandem_stance": ["berdiri tumit ke jari", "tumit ke jari", "berdiri satu garisan", "kaki satu garisan"],
    "bird_dog": ["anjing burung", "merangkak angkat tangan"],
    "march_in_place": ["berkawad di tempat", "kawad di tempat", "kawad setempat", "berkawad setempat"],
    "seated_marching": ["kawad sambil duduk", "berkawad sambil duduk", "kawad duduk", "angkat lutut sambil duduk"],
    "wrist_extension": ["angkat pergelangan tangan", "lentur pergelangan tangan", "pergelangan tangan ke atas"],
    "knee_extension": ["luruskan lutut sambil duduk"],
    "step_up": ["naik turun tangga", "naik anak tangga"],
}.items():
    ALIASES[_k] = ALIASES[_k] + [a for a in _v if a not in ALIASES[_k]]

CONDITION_NOTES = {
    "HYPERTENSION": "Because you have high blood pressure: breathe out as you lift and never hold your breath, and "
                    "stop if you get a headache, blurred vision or feel dizzy.",
    "DIABETES": "Because you have diabetes: keep a sugary drink or snack nearby and stop if you feel shaky, sweaty "
                "or confused, which can mean low blood sugar. Wear well-fitting shoes and check your feet afterwards.",
    "HEART_DISEASE": "Because you have heart disease: warm up first, keep to the intensity in your plan, and stop "
                     "straight away if you feel chest discomfort, unusual breathlessness or a racing heartbeat.",
    "STROKE": "Because you have had a stroke: exercise next to a sturdy support, go slowly on your weaker side, and "
              "stop if you notice new weakness, numbness or difficulty speaking.",
    "ARTHRITIS": "Because you have arthritis: some joint stiffness at the start is normal; move within a "
                 "comfortable range and do not push into sharp joint pain.",
    "OSTEOPOROSIS": "Because you have osteoporosis: avoid twisting or bending forward sharply, and keep a support "
                    "within reach to prevent falls.",
    "ASTHMA": "Because you have asthma: keep your reliever inhaler nearby and stop if you start wheezing or your "
              "chest feels tight.",
    # 3.50 (11 Oct): the conditions added to the health profile (sources: lib/core/constants/evidence_sources.dart)
    "PREGNANCY": "Because you are pregnant or have recently given birth: do not lie flat on your back after the "
                 "first months, keep a support nearby, drink water and do not overheat; stop and contact your "
                 "doctor or midwife if you have bleeding, dizziness, pain or leaking fluid.",
    "JOINT_REPLACEMENT": "Because you have had a joint replacement: your surgeon's and physiotherapist's movement "
                         "advice comes first, and stop if the joint becomes red, hot, swollen or more painful.",
    "RHEUMATOID_ARTHRITIS": "Because you have rheumatoid arthritis: move within a comfortable range, and during a "
                            "flare rest hot, swollen joints and do fewer repetitions.",
    "COPD": "Because you have chronic lung disease: go at a pace where you can still speak, breathe out slowly "
            "through pursed lips, and stop if you are too breathless to talk.",
    "CANCER": "Because you have or had cancer: follow your doctor's advice on exercise during treatment, go "
              "gently on tired days, and stop if you have new bone pain, a fever or unusual tiredness.",
    "KIDNEY_DISEASE": "Because you have kidney disease: keep to a comfortable, moderate effort, drink as your "
                      "kidney team advises, and on dialysis days ask them when it is best to exercise.",
    "PARKINSONS": "Because you have Parkinson's disease: exercise next to a sturdy support, take your time when "
                  "standing up and turning, and stop if you feel unsteady.",
    "MULTIPLE_SCLEROSIS": "Because you have multiple sclerosis: keep cool (a fan, cool water, a cool room), rest "
                          "between sets, and stop if your symptoms get worse; they usually settle once you cool "
                          "down.",
    "FOOT_ULCER": "Because you have a foot ulcer or wound: do your exercises sitting or lying, keep weight off the "
                  "foot, and check your feet every day.",
    "OTHER": "Because of the other condition in your profile: follow your doctor's advice on exercise, and stop "
             "if anything feels wrong.",
}
LIMITATION_NOTES = {
    "BALANCE_IMPAIRMENT": "Because you declared a balance limitation: always keep one hand on a sturdy support.",
    "LEFT_LEG_MOBILITY": "Go gently with your left leg and keep a support within reach.",
    "RIGHT_LEG_MOBILITY": "Go gently with your right leg and keep a support within reach.",
    "LEFT_ARM_MOBILITY": "Only move your left arm within a range that feels comfortable.",
    "RIGHT_ARM_MOBILITY": "Only move your right arm within a range that feels comfortable.",
}
RISK_NOTES = {
    "High": "Your risk level is High: follow your plan exactly as set and check with a healthcare professional "
            "before doing more.",
}

RED_FLAGS = [
    # 3.82: Malay chest tightness and breathlessness with "senak" (not a stitch)
    "senak dada", "dada senak", "dada rasa senak", "senak di dada", "senak nafas", "nafas senak", "dada sesak",
    "sesak dada",
    # 4.07: chest tight (sempit), heavy (berat) or pressed (tekan, himpit) in everyday Malay, and "something sitting
    # on my chest": were not recognised (the last was seated marching)
    "dada sempit", "dada rasa sempit", "sempit dada", "rasa sempit dada", "sempit di dada", "dada berat",
    "dada rasa berat", "berat dada", "rasa berat di dada", "berat di dada", "dada kena tekan", "dada macam kena tekan",
    "dada rasa ditekan", "dada ditekan", "dada tertekan", "dada rasa tertekan", "tekanan di dada", "dada dihimpit",
    "dada rasa dihimpit", "sitting on my chest", "elephant on my chest", "weight on my chest",
    # 3.85: as whole phrases too, so a slip in one word is mended ("felll and cannot get up"); the looser
    # checks find them typed right. (Not "can't get up from the floor": "...the floor exercise without help".)
    "fell and cannot get up", "fell and can't get up", "fell and cant get up", "fallen and cannot get up",
    "fallen and can't get up",
    # 3.75 (conditions test): a seizure or fit happening now ("she is having a fit" was not recognised, "my
    # father had a seizure just now" the answer for a family member). Not "seizures" alone: "my seizures are
    # controlled" is epilepsy advice; "had a seizure last year" is past (engine.HISTORY_EVENTS).
    "having a seizure", "had a seizure", "has a seizure", "is seizing", "seizure now", "seizure just now",
    "having a fit", "had a fit", "having fits", "fitting now", "convulsion", "convulsions", "convulsing",
    "kena sawan", "dia sawan", "sedang sawan", "tengah sawan",
    "chest pain", "chest pains", "chest tightness", "tight chest", "pain in my chest", "heart attack",
    "can't breathe", "cannot breathe", "cant breathe", "can't breath", "cant breath", "cannot breath",
    "hard to breathe", "difficulty breathing", "struggling to breathe", "breathless", "short of breath",
    "shortness of breath", "faint", "fainted", "fainting", "passed out", "pass out", "blacked out", "black out",
    "dizzy", "dizziness", "light headed", "lightheaded", "giddy", "giddiness", "pening", "pening kepala",
    "vertigo", "head spinning", "head is spinning", "room spinning", "room is spinning", "severe pain", "extreme pain", "severe swelling",
    "very swollen", "badly swollen", "numb", "numbness", "heart racing", "racing heart", "heart is racing", "heart beating fast", "heart pounding",
    "heart is pounding", "palpitations", "irregular heartbeat", "had a fall", "hit my head", "hit my hip",
    "slurred speech", "speech is slurred", "slurring", "slurred", "face drooping", "face is drooping", "sudden weakness", "can't feel my", "cannot feel my",
    "coughing blood", "coughing up blood", "cough up blood", "cough blood", "batuk darah",
    "vomiting", "unconscious", "pengsan", "not answering", "not responding", "unresponsive", "tak sedar",
    "tidak sedar", "not waking up", "won't wake up", "will not wake up", "not breathing",
    # Falling onto a body part ("lost balance and fell on my bum").
    "fell on my back", "fell on my hip", "fell on my knee", "fell on my bum", "fell on my head", "fell on my side",
    "fell on my arm", "fell on my wrist", "fell on my face", "lost balance and fell", "lost my balance and fell",
    "blue lips", "lips turning blue", "lips going blue", "lips are blue", "lips turned blue", "lips blue",
    "bibir biru",
    "hit his head", "hit her head", "banged my head", "banged his head", "banged her head", "knocked my head",
    "knocked his head", "knocked her head", "fell and hit his", "fell and hit her", "fell and hit my",
    # Slipping is a fall only with a fall, a hit or a slippery place (laptop pass 4: "slipped me a note",
    # "slipped into the chair" are not).
    "slipped and fell", "slipped and hit", "slipped and hurt",
    # Vision going dark (near-fainting), not about the video.
    "everything went dark", "everything went black", "vision went dark", "vision went black", "greyed out",
    "grayed out",
]
# Falls, collapses, slips: only with a PERSON in front (8 Oct, laptop safety passes 2 and 3), so a
# phone, a mat, a score or a price that "fell" or "slipped" is not an emergency. Malay "jatuh" /
# "terjatuh" and family words (emak, ayah, nenek...) are mapped to English before matching.
_WHO = ["i", "he", "she", "my mum", "my mom", "my mother", "my dad", "my father", "my husband", "my wife",
        "my grandma", "my grandpa", "my grandmother", "my grandfather", "mum", "dad", "father", "mother",
        "husband", "wife", "grandma", "grandpa", "grandmother", "grandfather", "my son", "my daughter"]
RED_FLAGS += [f"{w} {v}" for w in _WHO for v in (
    "collapsed", "has collapsed", "fall down", "falls down", "fall over", "falls over", "keep falling", "fell",
    "slipped and", "slipped in the", "slipped on the", "tripped and", "tripped over", "slip and", "trip and",
    "has fallen", "have fallen", "had fallen", "'ve fallen", "overdosed",
    # round 14: "i just fell", "she has just fallen"
    "just fell", "just fallen", "has just fallen", "just had a fall", "just collapsed", "just slipped and",
    "has just collapsed", "had just collapsed", "suddenly collapsed", "has suddenly collapsed", "just fainted",
    "has fainted")]
# "fell today", "fell just now" without a person are judged by _recent_fall() in the engine (not "my phone fell today").
RED_FLAGS += ["dia fell", "baru fell"]
# Laptop pass 11 (8 Oct): emergencies in less obvious words. Allergic reaction, sudden severe
# headache, unable to pass urine, bleeding from the gut.
RED_FLAGS += ["anaphylaxis", "allergic reaction", "epipen", "epi pen", "throat closing", "throat is closing",
              "throat feels tight", "throat is tight", "worst headache", "thunderclap headache",
              "cannot pee", "can't pee", "cant pee", "unable to pee", "not able to pee", "cannot urinate",
              "can't urinate", "unable to urinate", "tak boleh kencing", "not can kencing", "black stool",
              "black stools", "black poo", "black poop", "tarry stool", "blood in my stool", "blood in stool",
              "bloody stool", "blood in my poo", "vomiting blood", "vomit blood", "vomited blood",
              "throwing up blood", "berak hitam", "najis hitam"]
# PC safety pass 14 (9 Oct, generated probe of emergencies in everyday words): gasping, losing
# consciousness, bleeding that will not stop, speech that suddenly goes wrong (not when long-standing:
# engine CHRONIC).
RED_FLAGS += ["gasping for air", "gasping for breath", "gasp for air",
              "lost consciousness", "loss of consciousness", "lose consciousness", "losing consciousness",
              "bleeding a lot", "bleeding heavily", "heavy bleeding", "bleeding won't stop", "bleeding will not stop",
              "won't stop bleeding", "will not stop bleeding", "can't stop the bleeding", "cannot stop the bleeding",
              "bleeding badly", "losing a lot of blood", "lost a lot of blood",
              # 3.55 (15 Oct, random test): the words users leave out
              "short breath", "have short breath", "feel short breath", "bleeding lot", "bleed a lot",
              "slipped hit", "slip hit", "fell hit", "hit head", "hit hip", "fell bum", "fell on bum",
              "fell on my bum", "out breath", "out of breath marching", "slipped kitchen", "slipped bathroom",
              "slipped toilet", "today slipped", "slipped today", "he's floor",
              "she's floor", "is on floor", "on floor cannot", "hasn't been same since", "not been same since",
              "not same since", "fell during exercise", "fell down during exercise", "fall down during exercise",
              "fell while exercising", "fell during the exercise", "fell during senaman", "help fell",
              "help i fell", "need help fell", "fell down help", "fell now", "i fell now",
              "cannot move one side", "can't move one side", "fell hit head", "fell hit my head",
              "pressure chest", "chest pressure",
              # 3.54 (15 Oct, generated warning signs)
              "heart beating very fast", "heart beating so fast", "heart beating too fast", "heart beat very fast",
              "heartbeat very fast", "heart is beating very fast", "heart beats very fast", "heart racing fast",
              "i have collapsed", "i've collapsed", "not able to breathe", "unable to breathe",
              "cannot breathe properly", "can't breathe properly", "not able to breath",
              # PC safety pass 16: a low blood sugar told in words
              "having a hypo", "having hypo", "going hypo", "i'm hypo", "i am hypo", "hypo now", "hypo attack",
              "feeling hypo", "feel hypo", "kena hypo", "sugar very low", "sugar is very low", "sugar too low",
              "sugar is too low", "sugar so low", "gula rendah sangat", "gula sangat rendah", "gula terlalu rendah"] + ['cannot talk properly', "can't talk properly", 'cannot speak properly', "can't speak properly", 'cannot get my words out', "can't get my words out", 'cannot get the words out', "can't get the words out", 'words come out wrong', 'words are jumbled', 'talking funny', 'speech is strange']
# Crisis (8 Oct, laptop review): thoughts of suicide or self-harm. Checked before everything else,
# including the red flags. "hurt myself" on its own is left out: "will I hurt myself doing squats"
# is about injury. Overdose wording must be a statement ("going to take all my pills"), not "can I
# take all my medicine before exercise".
CRISIS = [
    "end my life", "end it all", "kill myself", "killing myself", "want to die", "wanna die", "wish i was dead",
    "wish i were dead", "better off dead", "suicide", "suicidal", "take my own life", "no reason to live",
    "nothing to live for", "give up on life", "giving up on life", "want to hurt myself", "going to hurt myself",
    "harm myself", "self harm", "self-harm", "cut myself", "don't want to live", "dont want to live",
    "do not want to live", "bunuh diri", "nak mati", "ingin mati", "mahu mati", "tak nak hidup",
    # laptop safety pass 2: indirect wording, someone else, misspellings.
    "tired of living", "tired of life", "sick of living", "penat hidup", "letih hidup", "no point anymore",
    "no point going on", "no point in living", "point of living", "point in living", "sleep and not wake up",
    "never wake up", "don't want to wake up", "dont want to wake up", "do not want to wake up",
    "better if i was gone", "better if i were gone", "better off without me", "burden to my", "burden to everyone",
    "a burden to", "want to end it", "end it now", "kill herself", "kill himself", "end her life", "end his life",
    "take her own life", "take his own life", "sucide", "suicde", "suiside", "suicid", "sucidal",
    # overdose as a statement
    "going to take all my", "gonna take all my", "take all my pills at once", "swallow all my", "took an overdose",
    # 3.55 (random test): the same without the small words users leave out
    "want die", "wanna die", "want end life", "want end my life", "want to end life", "want end it all",
    "dont want wake up", "don't want wake up", "no point going", "no point living", "no point go on",
    "better if gone", "better off without", "take all pills", "take all my pills", "going take all",
    "tired of living", "burden children", "burden to children", "burden family",
    "dont want live", "don't want live", "do not want live", "not want live anymore", "what's point living",
    "whats point living", "what point living", "point of living", "no point living", "tired living",
    "wish sleep not wake", "sleep not wake up", "sleep and not wake", "could sleep and not wake",
    "thinking ending all", "thinking of ending", "ending it all", "end it all", "want end it",
    "wish dead", "wish i were dead", "wants die", "wants to die", "want to live anymore", "want live anymore",
    "take an overdose", "taken an overdose", "overdose on",
    "saving up my pills", "saving up my sleeping pills", "saving my sleeping pills", "saving up pills",
    # laptop safety pass 3
    "hang myself", "hanging myself", "jump from the", "jump off the", "thinking about jumping", "jump in front",
    "rat poison", "poison myself", "drink poison", "want to disappear", "point of anything",
    "point in anything", "won't be here much longer", "wont be here much longer", "not be here much longer",
    "goodbye everyone", "life has no meaning", "no meaning in life", "baik saya mati", "lebih baik mati",
    "baik mati", "tak ada makna", "tiada makna", "tidak ada makna",
    # laptop safety pass 4: goodbyes, sleeping forever, ending things
    "sleep forever", "end things tonight", "end things", "end everything", "goodbye letter", "goodbye letters",
    "wrote goodbye", "said my goodbyes", "saying my goodbyes", "giving away my things", "give away my things",
    "giving my things away",
    # PC safety pass 15 (9 Oct, generated probe: 800/960 before): life not worth living, cannot go on,
    # ending it, and Malay "tamatkan hidup". Not "can't go on with the exercise".
    "life is not worth living", "life isn't worth living", "life not worth living", "not worth living",
    "no longer worth living", "can't go on anymore", "cannot go on anymore", "cant go on anymore",
    "can't go on any more", "cannot go on any more", "can't go on like this", "cannot go on like this",
    "can't carry on anymore", "cannot carry on anymore", "don't want to go on living", "do not want to go on living",
    "thinking about ending it", "thinking of ending it", "think about ending it", "ending it all", "end it all",
    "want to end it all", "going to end it all", "tamatkan hidup", "tamatkan nyawa", "akhiri hidup",
    "mengakhiri hidup", "tamatkan riwayat", "hidup tak berguna", "tak guna hidup", "tidak guna hidup",
    # 3.73 (caregiver test): told of someone else ("my dad wishes he was dead", "she keeps talking about
    # killing herself"). Not "cut herself" or "hurt himself": "my mum cut herself cooking" is an accident.
    "wish he was dead", "wish she was dead", "wish he were dead", "wish she were dead", "wishes he was dead",
    "wishes she was dead", "wishes he were dead", "wishes she were dead", "wished he was dead",
    "wished she was dead", "wishes to die", "wished to die", "killing himself", "killing herself",
    "harm himself", "harm herself", "hang himself", "hang herself", "end his own life", "end her own life",
    "wants to end his life", "wants to end her life",
    # 3.84: without the small words ("want give up life" was motivation)
    "give up life", "giving up life", "give up my life", "suicidal thoughts", "suicide thoughts",
    "thoughts of suicide", "thinking of suicide", "thoughts of killing myself",
]
# 3.73: the same help for a family member who talks of dying or self-harm ("my mother keeps saying she
# wants to die"), worded for the person helping them.
CRISIS_ANSWER_OTHER = ("I am sorry you are going through this. Talk of dying or self-harm needs help today.\n"
                       "1) If they are in danger now or might act on these thoughts, call 999 or take them to the "
                       "nearest emergency department. Stay with them.\n"
                       "2) Talk to someone now: Befrienders KL 03-7627 2929 (24 hours, free and confidential) or "
                       "Talian HEAL 15555 (8 am to midnight daily). You can call for them or with them.\n"
                       "3) Keep medicines and anything they could hurt themselves with out of reach, and tell "
                       "their doctor.\n"
                       "I am only an exercise assistant, but these people can help.")
CRISIS_ANSWER = ("I am really sorry you are feeling this way, and I am glad you said it. You are not alone.\n"
                 "1) If you are in danger now or might act on these thoughts, call 999 or go to the nearest "
                 "emergency department.\n"
                 "2) Talk to someone right now: Befrienders KL 03-7627 2929 (24 hours, free and confidential) or "
                 "Talian HEAL 15555 (8 am to midnight daily).\n"
                 "3) Please also tell a family member or your doctor how you feel.\n"
                 "I am only an exercise assistant, but these people can help you.")
# Emergencies described in free words: an anchor word with a symptom word close to it, in any order
# ("my chest feels heavy and painful", "i can hardly breathe", "my arm suddenly cannot move").
# [anchors, symptoms, window in words]. A "no"/"not"/"never" just before the anchor cancels it
# ("no chest pain"); "can't"/"cannot" do not, they are part of the symptom ("cannot breathe").
RED_FLAG_COMBOS = [
    # 3.78: sudden tingling, or tingling in the face, is a stroke sign ("sudden tingling in my face and arm" was
    # pins and needles); pins and needles after sitting are not sudden.
    [["sudden", "suddenly", "tiba tiba", "tiba-tiba"], ["tingling", "tingly", "tingle", "tingles", "pins and needles"],
     6],
    [["face", "muka", "lips", "tongue"], ["tingling", "tingly", "tingle", "tingles", "pins and needles"], 3],
    # 3.75: a blood clot with swelling, pain or breathlessness now ("i have a blood clot in my leg, it is
    # swollen and painful" was the swelling answer).
    [["blood clot", "clot", "dvt", "thrombosis"], ["swollen", "swelling", "bengkak", "painful", "calf pain",
                                                   "leg pain", "breathless", "short of breath", "chest pain"], 6],
    # Laptop pass 11: swelling of the lips, tongue, face or throat (allergic reaction).
    [["lips", "lip", "tongue", "face", "throat", "eyelids", "bibir"],
     ["swelling", "swollen", "swell", "swells", "puffy", "closing"], 3, ["knee", "ankle", "joint"]],
    [["swallow", "swallowing", "telan"], ["hard", "difficult", "difficulty", "can't", "cannot", "unable", "tight",
                                          "suddenly", "susah"], 3,
     ["pill", "pills", "tablet", "tablets", "capsule", "capsules", "big", "ubat"]],
    # A sudden, severe headache (bleeding in the brain), not a mild one.
    [["headache", "head pain"], ["worst", "sudden", "suddenly", "severe", "exploding", "explosive", "thunderclap",
                                 "like being hit", "very bad"], 4,
     ["mild", "slight", "little", "sikit", "hangover", "for years"]],
    # A limb suddenly cold and pale (blocked artery), not cold hands in winter.
    [["suddenly cold", "cold and pale", "pale and cold", "turned white", "turned blue", "gone white", "gone pale",
      "turned pale", "cold pale"], ["leg", "legs", "foot", "feet", "arm", "hand", "toes", "fingers", "kaki", "tangan"],
     5, ["winter", "weather", "aircon", "air con", "raynaud", "raynauds", "always", "every morning"]],
    # A swollen, hot calf (blood clot), not a sore calf after heel raises.
    [["calf", "calves", "betis"], ["swollen", "swelling", "hot", "red"], 4, ["cramp", "cramps", "sore muscles"]],
    # Confusion with a fever (infection; delirium in older people).
    [["confused", "confusion", "keliru", "not making sense", "delirious"],
     ["fever", "feverish", "high temperature", "temperature", "demam", "shivering", "chills"], 6],
    # An infected wound with pus or a fever.
    [["wound", "incision", "stitches", "scar", "luka"],
     ["pus", "oozing", "fever", "demam", "smells", "spreading", "red streaks", "nanah"], 6],
    # Sudden blurred or double vision (round 14: stroke, very high blood pressure or low sugar), not a
    # blurry video or long-standing cataracts.
    [["blurry", "blurred", "kabur", "double vision", "seeing double", "see double", "can't see properly",
      "cannot see properly", "cant see properly", "lost my vision", "lost vision", "losing my vision",
      "went blind", "go blind", "can't see out of", "cannot see out of"],
     ["suddenly", "sudden", "all of a sudden", "just now", "during", "while", "after the exercise",
      "after exercising", "after exercise", "one eye", "everything", "dizzy", "headache", "vision", "eyesight",
      "eyes", "eye", "mata", "pandangan"], 7,
     ["video", "photo", "picture", "camera", "screen", "recording", "cataract", "cataracts", "glasses",
      "spectacles", "for years", "always", "old age", "reading", "app", "instructions", "words", "text",
      "writing", "font", "every morning", "when i wake up", "wake up", "mengantuk", "sleepy", "drowsy", "fogged",
      "sweat", "sweating", "phone", "for a long time", "presbyopia"]],
    # Malaysian "blur" also means confused ("i'm so blur about the app"): only with the eyes.
    [["blur"], ["eye", "eyes", "mata", "vision", "eyesight", "pandangan", "seeing"], 3,
     ["mengantuk", "drowsy", "sleepy", "every morning", "wake up", "glasses", "cataract", "cataracts", "reading",
      "when reading", "for years", "for a long time", "presbyopia", "baca", "always", "spectacles"]],
    # Cannot take weight on the leg (laptop pass 8: possible fracture), not "can't bear weight on my toes
    # for the heel raise, too hard" (pass 9).
    [["can't put weight on", "cannot put weight on", "cant put weight on", "unable to put weight on",
      "can't bear weight", "cannot bear weight", "cant bear weight", "unable to bear weight"], ["weight"], 1,
     ["toes", "tiptoe", "heel raise", "too hard", "for long", "too long", "difficult", "susah"]],
    # Someone unable to get up or move after a fall, or on the floor / in bed ("my father fell and
    # cannot get up", "he is on the floor and can't move his leg"); not "can't get up early".
    # Pass 4: only with a fall, the floor, "since" or "lying" (not "can't get up from bed early",
    # "stairs: can't walk up them yet"), and not in a planning question.
    [["floor", "fell", "fall", "fallen", "since", "lying"],
     ["cannot get up", "can't get up", "cant get up", "unable to get up", "cannot stand", "can't stand",
      "cant stand", "unable to stand", "cannot move", "can't move", "cant move", "cannot walk", "can't walk",
      "cant walk", "unable to walk", "not answering", "not responding", "still on"], 6,
     ["any easier", "easier exercise", "which plan", "where do i", "where should i", "is there a",
      "chair version"]],
    # Round 15 (9 Oct): pain after a fall told with no person in front ("hip pain after falling this
    # morning", "after the fall my leg hurts", Malay "sakit lepas jatuh tadi" -> "pain after fell just now")
    # was not urgent: only "I fell" / "she fell" counted. In older people it can be a broken hip. Only
    # with pain or an injury word, so "what if I can't get up after a fall" stays a question.
    [["after a fall", "after the fall", "after my fall", "after her fall", "after his fall", "after falling",
      "after fell", "selepas fell", "since the fall", "since my fall", "since falling", "from the fall",
      "from falling", "fall yesterday", "fall this morning", "fall just now", "fall today"],
     ["pain", "painful", "hurt", "hurts", "hurting", "sakit", "swollen", "swelling", "bruise", "bruised",
      "can't walk", "cannot walk", "limp", "limping", "numb", "headache", "dizzy", "confused", "bleeding",
      "can't put weight", "cannot put weight", "sore", "aching", "lebam"], 6,
     ["what if", "in case", "prevent", "avoid", "how to get up", "how do i get up", "afraid of", "scared of",
      "worried about", "fear of", "get hurt", "getting hurt"]],
    # PC safety pass 13 (generated probe of 6,160 fall messages): a fall, trip or slip with an injury word
    # close by, told without a time word or without a person ("dad tripped on the stairs and cannot stand
    # up", "fell, hip hurts", "jatuh, kepala sakit"). Not in questions about preventing or fearing falls,
    # and not "my pain fell to 3".
    [["fell", "fall", "fallen", "tripped", "slipped", "collapsed"],
     ["hurts", "hurt", "pain", "painful", "sakit", "swollen", "swelling", "bengkak", "bruise", "bruised",
      "bleeding", "berdarah", "cannot stand", "can't stand", "cant stand", "cannot get up", "can't get up",
      "cant get up", "tak boleh bangun", "cannot walk", "can't walk", "limp", "limping", "pening", "dizzy",
      "confused", "keliru", "vomiting", "muntah", "looks bent", "deformed", "broken", "patah", "numb",
      "headache", "hit my head", "hit her head", "hit his head",
      # 3.62: "fell over, hip sore" was not urgent while "fell over, hip hurts" was.
      "sore", "aching", "lebam"], 12,
     ["what if", "in case", "prevent", "prevention", "avoid", "afraid of", "scared of", "worried about",
      "fear of", "get hurt", "getting hurt", "risk of", "how to get up", "how do i get up", "pain fell",
      "pain has fallen", "pain level fell", "pain score fell", "swelling has fallen", "swelling fell",
      "score fell", "accuracy fell", "phone fell", "fell asleep", "slept", "will fall", "might fall", "may fall",
      "could fall", "would fall", "going to fall", "afraid she", "afraid he", "afraid i", "scared she",
      "scared he", "worried she", "worried he"]],
    # Round 15: a stiff or painful neck with a fever (meningitis), whatever the neck answer says.
    [["neck", "leher", "tengkuk"], ["fever", "feverish", "high temperature", "demam", "rash"], 6],
    # A person lying on the floor, not doing the exercise ("my father is lying on the kitchen floor").
    [["lying"], ["mum", "mom", "mother", "dad", "father", "husband", "wife", "grandma", "grandpa",
                 "grandmother", "grandfather", "he", "she", "son", "daughter"], 3,
     ["bridge", "exercise", "mat", "bird dog", "doing", "for the", "resting", "rest", "nap", "session", "sofa",
      "relax", "relaxing"]],
    # Someone found on the floor ("found my mum on the floor"): a person must be named.
    [["found"], ["mum", "mom", "mother", "dad", "father", "husband", "wife", "grandma", "grandpa",
                 "grandmother", "grandfather", "him", "her", "son", "daughter"], 3],
    # PC safety pass 14: one side of the body suddenly weak or numb (stroke), not a long-standing weaker side.
    [["one side", "sebelah", "half of my body", "half my body", "half of his body", "half of her body"],
     ["weak", "weakness", "numb", "numbness", "cannot move", "can't move", "paralysed", "paralyzed", "lumpuh",
      "drooping", "droop", "heavy", "no feeling"], 5,
     ["since my stroke", "since the stroke", "after my stroke", "from my stroke", "old stroke", "for years",
      "years ago", "always", "stronger", "weaker than", "since birth", "for a long time", "exercise one side",
      "one side at a time"]],
    # One side of the face drooping (stroke), in everyday words ("face one side drop").
    [["face", "mouth"], ["drop", "droop", "drooping", "dropping", "dropped", "crooked", "lopsided",
                         "one side"], 3],
    [["chest"], ["pain", "painful", "hurt", "hurts", "hurting", "heavy", "heaviness", "pressure", "tight",
                 "tightness", "squeeze", "squeezing", "ache", "aching", "burning", "crushing"], 4],
    # Not "breathing hard after sit to stand" (PC pass 14: panting after effort is the tired answer's;
    # "hard to breathe" and "can't breathe" are urgent phrases of their own).
    [["breathe", "breath", "breathing"], ["hardly", "barely", "can't", "cannot", "difficult", "difficulty",
                                          "trouble", "struggle", "struggling", "hard", "gasping"], 3,
     ["breathing hard", "breathe hard", "breathing heavily", "breathing heavy", "breathe heavily"]],
    [["suddenly", "sudden", "tiba tiba", "tiba-tiba", "mengejut"], ["weak", "weakness", "numb", "numbness",
                                                                    "can't move", "cannot move",
                              "paralysed", "paralyzed", "drooping", "droop", "slurred", "can't speak",
                              "cannot speak", "collapse", "collapsed", "confused", "can't see", "cannot see",
                              "cannot talk", "can't talk", "cant talk", "talk properly", "speak properly",
                              "cannot lift", "can't lift", "cant lift", "cannot raise", "can't raise"], 5],
]

RED_FLAG_ANSWER = ("Stop exercising now.\n"
                   "1) Chest pain, trouble breathing, fainting, sudden weakness or numbness, slurred speech, or "
                   "severe swelling: call 999 or go to the nearest emergency department.\n"
                   "2) Other new pain, dizziness or a fall: sit down, rest, and contact your doctor before "
                   "exercising again.")


def duration(sec: int) -> str:
    if sec < 60:
        return f"{sec} seconds"
    m, s = divmod(sec, 60)
    return f"{m} minute{'s' if m > 1 else ''}" + (f" {s} seconds" if s else "")


def clean_instruction(text: str) -> str:
    """Drops the 'Camera: ...' sentence, which is for recording, not for doing the exercise."""
    return re.sub(r"^Camera:[^.]*\.\s*", "", text).strip()


# Buttons under the answer (the app maps each key to a screen).
ACTIONS = {
    "how_to": {"key": "open_treatment", "label": "Open my treatment plan"},
    "missed_session": {"key": "open_treatment", "label": "Open my treatment plan"},
    "recording_help": {"key": "open_treatment", "label": "Record an exercise"},
    "posture_result": {"key": "open_history", "label": "See my results"},
    "plan_and_reminders": {"key": "open_planning", "label": "Open treatment planning"},
    "multiple_plans": {"key": "open_planning", "label": "Open treatment planning"},
    "body_map": {"key": "open_planning", "label": "Open treatment planning"},
    "wrong_exercise": {"key": "open_treatment", "label": "Record an exercise"},
    "condition_advice": {"key": "open_profile", "label": "Update my health conditions"},
    "account_help": {"key": "open_profile", "label": "Open my profile"},
}

# A second button when the answer names a second screen (3.48).
MORE_ACTIONS = {
    "account_help": [{"key": "open_reset_password", "label": "Reset password"}],
    "multiple_plans": [{"key": "open_treatment", "label": "Open my treatment plan"}],
    "plan_and_reminders": [{"key": "open_reminders", "label": "Open reminders"}],
}

# Rules about doing the exercises: the reply also considers the patient's local time of day
# (late at night -> advise to rest; condition-specific timing).
# Also tailored to the patient's conditions (besides the rules created with tailor=True).
TAILORED = {"tired", "getting_started", "treatment_nav", "missed_session", "diet"}

TIME_AWARE = {"treatment_nav", "getting_started", "how_to", "how_often", "missed_session", "safety", "condition_advice",
              "equipment", "difficulty", "best_time", "recording_help"}

# Periods by the phone's local hour: late night 22:00-05:59, early morning 06:00-08:59,
# daytime 09:00-17:59, evening 18:00-21:59.
LATE_NIGHT_NOTE = ("It is {time} where you are. Late at night is not a good time for your exercises: tiredness and "
                   "dim light raise the risk of a fall, and activity close to bedtime can disturb your sleep. Rest "
                   "now and do them tomorrow, ideally in the late morning or late afternoon.")
# Main answer to "can I exercise with my condition?" for each condition the patient has (profile or
# named in the message). General guidance only; every answer ends by pointing to their doctor.
CONDITION_DETAIL = {
    "HYPERTENSION": "With high blood pressure, regular gentle exercise like your plan can help lower it over "
                    "time. Breathe out as you lift and never hold your breath or strain. If a home reading is "
                    "180/110 or higher, do not exercise that day: rest and contact your doctor.",
    "DIABETES": "With diabetes, exercise helps control your blood sugar. If you take insulin or tablets that can "
                "cause low sugar, check your level before you start and have a small snack if it is low; keep "
                "glucose sweets nearby, and stop if you feel shaky, sweaty or confused. Check your feet "
                "afterwards.",
    "HEART_DISEASE": "With heart disease, keep to the intensity in your plan: you should still be able to talk "
                     "while exercising. Warm up and cool down for about five minutes. Stop at once if you get "
                     "chest discomfort, unusual breathlessness, dizziness or a racing heartbeat, and call 999 if "
                     "it does not settle with rest.",
    "STROKE": "After a stroke, these exercises help you regain strength and balance. Do them next to a sturdy "
              "support, go slowly on your weaker side, and stop and call 999 if you notice new weakness, "
              "numbness, a drooping face or slurred speech.",
    "ARTHRITIS": "With arthritis, moving keeps your joints flexible and the muscles around them strong. Some "
                 "discomfort is fine if it settles within about two hours; if it lasts longer, do fewer "
                 "repetitions next time. Rest a joint that is hot and swollen during a flare.",
    "OSTEOPOROSIS": "With osteoporosis, strengthening and standing exercises help your bones. Avoid bending "
                    "forward from the waist, twisting and jerky movements, and keep a support within reach to "
                    "prevent falls.",
    "ASTHMA": "With asthma, warm up gradually and keep your reliever inhaler within reach; use it before "
              "exercising if your doctor has told you to. Stop if you start wheezing or your chest feels tight, "
              "and avoid exercising in cold air or when your asthma is not well controlled.",
    # Named in a message only (not health-profile options).
    "PREGNANCY": "During pregnancy, gentle exercise is usually safe and helpful when the pregnancy is going "
                 "well, but check with your doctor or midwife first. After the first three months avoid lying "
                 "flat on your back for long (as in the glute bridge), exercise on a firm, non-slip surface with a "
                 "support nearby for balance, drink "
                 "water and do not overheat. Stop and contact your doctor if you have bleeding, dizziness, chest "
                 "pain, calf pain or swelling, contractions or leaking fluid.",
    "JOINT_REPLACEMENT": "After a hip or knee replacement, your surgeon's and physiotherapist's exercises and "
                         "precautions come first: they decide how far you may bend and when you may do more. "
                         "After a new hip, avoid bending it past 90 degrees (a right angle), crossing your legs and "
                         "twisting, and keep the leg facing forward, until they say it is safe. Ask them before starting this plan, and stop if the wound "
                         "becomes red, hot, swollen or more painful, or you get calf pain or a fever.",
    "RHEUMATOID_ARTHRITIS": "With rheumatoid arthritis, regular exercise is part of standard care: it keeps "
                            "your joints moving and the muscles around them strong. Move within a comfortable "
                            "range; during a flare, rest hot, swollen joints, do fewer repetitions and build up "
                            "again as it settles.",
    "COPD": "With chronic lung disease, exercise improves your breathing and strength. Go at a pace where you can "
            "still speak, breathe out slowly through pursed lips, and rest between sets. Stop and contact your "
            "doctor if you are much more breathless than usual, cough up blood or have chest pain.",
    "CANCER": "During and after cancer treatment, staying active helps with tiredness and strength, but follow "
              "your doctor's advice first, especially during treatment. Go gently on tired days, and stop and "
              "tell your doctor if you have new bone pain, a fever, or feel unusually tired or breathless.",
    "KIDNEY_DISEASE": "With chronic kidney disease, regular moderate exercise is recommended as you can manage it. "
                      "Keep to a comfortable effort, drink as your kidney team advises, and on dialysis days ask "
                      "them when it is best to exercise. Stop if you feel dizzy, breathless or have chest pain.",
    "PARKINSONS": "With Parkinson's disease, strength and balance exercises help you move more easily and "
                  "confidently. Exercise next to a sturdy support, take your time when standing up and turning, "
                  "and stop if you feel unsteady or about to fall.",
    "MULTIPLE_SCLEROSIS": "With multiple sclerosis, strength exercises help, but heat can make symptoms worse for "
                          "a while. Keep cool with a fan, cool water and a cool room, rest between sets, and stop "
                          "if symptoms get worse; they usually settle once you cool down. During a relapse, rest "
                          "and ask your doctor before starting again.",
    "FOOT_ULCER": "With a foot ulcer or an open wound on the foot, do not put weight on it: do your exercises "
                  "sitting or lying until it has healed, check your feet every day, and see your doctor if the "
                  "wound gets bigger, red, hot or smelly.",
    "SURGERY_WOUND": "A little oozing from a surgical wound can be normal in the first days, but if it keeps "
                     "bleeding, soaks the dressing, or turns red, hot, swollen or smelly, or you get a fever, "
                     "contact your surgeon or clinic today, and do not exercise that area until they have "
                     "checked it.",
    "INJURY": "With a recent fracture, sprain or a cast, do not exercise the injured part until your doctor "
              "or physiotherapist says it is ready. Exercises that do not use it are usually fine, but check "
              "with them first, and stop if the injured area hurts or swells.",
}
CONDITION_CLOSING = ("Your plan was chosen within the safety limits set from your health profile, so follow it "
                     "as set and check with your doctor before doing more.")


# Food and drink answers get diet notes for the patient's conditions (not exercise reminders).
DIET_NOTES = {
    "HYPERTENSION": "With high blood pressure, keep salt low: your daily sodium limit is on the Home page.",
    "DIABETES": "With diabetes, spread carbohydrates through the day and exercise 1 to 3 hours after a meal; "
                "your daily sugar limit is on the Home page.",
    "HEART_DISEASE": "With heart disease, keep salt and saturated fat low and avoid exercising after a large "
                     "meal.",
}

# Direct answer to "can I exercise now?" for each part of the day (best_time only; late night uses
# LATE_NIGHT_NOTE).
NOW_NOTES = {
    "early_morning": "It is {time} where you are. Early morning is fine once you have been up for a while, had "
                     "something light to eat and warmed up.",
    "daytime": "It is {time} where you are, a good time for your exercises if you feel well and have not just "
               "eaten a large meal.",
    "evening": "It is {time} where you are. A session now is fine; finish at least an hour or two before bed so "
               "it does not disturb your sleep.",
}
TIME_NOTES = {
    # code -> {period: note}
    "DIABETES": {
        "evening": "With diabetes, avoid exercising late in the evening: it can make your blood sugar drop "
                   "overnight. Exercise earlier in the day, about 1 to 3 hours after a meal.",
        "late_night": "With diabetes, exercising at night can make your blood sugar drop while you sleep.",
        "early_morning": "With diabetes, avoid exercising on an empty stomach first thing; have breakfast and "
                         "exercise about 1 to 3 hours after it.",
        "daytime": "With diabetes, exercise about 1 to 3 hours after a meal rather than on an empty stomach.",
    },
    "HYPERTENSION": {
        "early_morning": "Blood pressure is naturally higher in the first hours after waking: wait about an hour "
                         "after you get up, warm up slowly and keep the effort gentle.",
    },
    "HEART_DISEASE": {
        "early_morning": "Heart strain is more likely in the early morning: wait about an hour after waking, warm "
                         "up slowly and avoid exercising right after a large meal.",
    },
    "ARTHRITIS": {
        "early_morning": "Joints are often stiffest first thing in the morning: a warm shower and a few gentle "
                         "movements first, or exercising later in the morning, can make it easier.",
    },
    "ASTHMA": {
        "early_morning": "Cool morning air can trigger asthma: exercise indoors and warm up gradually.",
        "late_night": "Cool night air can trigger asthma, another reason to wait until tomorrow.",
    },
    "OSTEOPOROSIS": {
        "early_morning": "Make sure the room is well lit and the floor is clear: falls are more likely when you "
                         "have just woken up.",
        "evening": "Make sure the room is well lit and the floor is clear: falls are more likely when it is dark "
                   "or you are tired.",
    },
    "STROKE": {
        "evening": "Exercise when you are not tired, with good lighting and someone nearby if possible.",
    },
    "BALANCE_IMPAIRMENT": {
        "early_morning": "With your balance limitation, wait until you are fully awake and steady, and keep the "
                         "room well lit.",
        "evening": "With your balance limitation, exercise in a well-lit room with someone nearby if possible.",
    },
}



# ---- what the posture check's mistake names mean (8 Oct, round 11) ------------------------------
# (meaning, what to do). The "what to do" lines are the posture check's own feedback where the name
# belongs to one exercise; names shared by several exercises get a general line.
MISTAKE_MEANING = {
    "not_closed": ("your hand did not close into a fist between openings",
                   "Between openings, close your hand into a gentle fist."),
    "arm_leg_low": ("your arm and leg did not reach the level of your back",
                    "Stretch your arm and leg a little further, towards the level of your back, only as far as feels steady."),
    "back_arch": ("your lower back bent backwards as your arms went up",
                  "Keep your back still; do not lean backwards as your arms go up."),
    "back_sag": ("your lower back dipped or your hips tilted while you stretched",
                 "Keep your back flat and your hips level."),
    "bent_elbow": ("your elbows were bent while your arms were raised", "Keep your elbows straight as you lift."),
    "bent_knee": ("the knee of your lifting leg was bent", "Keep the knee of the lifting leg straight."),
    "body_swing": ("you rocked your body back to help lift", "Keep your body still; do not rock back to lift."),
    "drop_down": ("you came down from the step too quickly", "Step down slowly, holding the rail, and let your foot touch down gently."),
    "feet_far": ("your feet were too far from your buttocks", "Bring your feet closer to your buttocks."),
    "feet_forward": ("your feet were too far in front of you when you started to stand",
                     "Bring your feet back so your knees are above your ankles before you stand."),
    "feet_not_in_line": ("your feet were side by side or apart instead of one in front of the other",
                         "Place one foot directly in front of the other, heel touching toe."),
    "hands_used": ("your hands pushed on your legs or the chair to help you stand",
                   "If you can, stand up with your arms crossed; if you need your hands to stand safely, that is fine."),
    "heels_lift": ("your heels came off the floor", "Keep your heels on the floor."),
    "hips_back": ("your hips were pushed back, so your body bent at the hips",
                  "Keep your body straight; do not push your hips back."),
    "hips_sag": ("your hips dropped towards the wall, so your body was not straight",
                 "Keep your body straight from head to heels."),
    "incomplete_extension": ("your knee did not straighten fully",
                             "Straighten your knee so your leg is straight out in front, as far as is comfortable."),
    "incomplete_stand": ("you did not stand up fully straight at the top",
                         "Stand up fully: straighten your hips and knees at the top, as far as you safely can."),
    "fingers_not_spread": ("your fingers stayed close together when your hand opened",
                           "Spread your fingers wide as you open your hand, only as far as is comfortable."),
    "head_tilt": ("your head tilted to one side as you lifted", "Keep your head level and look straight ahead."),
    "knee_not_straight": ("your leading leg was not fully straight at the top of the step",
                          "Straighten your leading leg at the top, holding the rail, as far as is comfortable."),
    "knees_bend": ("your knees bent as you rose onto your toes", "Keep your knees straight as you rise."),
    "leaning": ("you leaned on the counter or to the side", "Stand upright with a light touch on the counter, rather than leaning your weight on it."),
    "leaning_back": ("you leaned your upper body backwards", "Sit or stand tall; do not lean back."),
    "leaning_forward": ("you leaned your upper body forwards", "Keep your upper body upright."),
    "leg_forward": ("your leg went forwards instead of straight out to the side",
                    "Lift the leg straight out to the side, not forwards."),
    "low_hips": ("your hips did not lift high enough",
                 "Lift your hips a little higher, towards a straight line from shoulders to knees, without pain in your back."),
    "low_knee_lift": ("your knees did not lift high enough", "Lift your knees a little higher, only as far as is comfortable."),
    "low_raise": ("your heels did not rise high enough", "Rise a little higher onto your toes, holding the chair, only as far as feels steady."),
    "low_range": ("the movement did not go as far as the exercise asks",
                  "Move a little further each time, as far as is comfortable; the exercise steps say how far."),
    "no_arm_swing": ("your arms stayed still while you marched", "If you feel steady, swing your arms as you march; if not, keep one hand on the chair."),
    "no_forward_lean": ("you did not lean your chest forward before standing up",
                        "Lean your chest forward a little before you stand up."),
    "no_hold": ("you did not hold the top position", "Pause and hold for about 2 seconds before lowering."),
    "over_arch": ("your hips went too high, so your lower back arched",
                  "Do not push your hips too high; keep your lower back from arching."),
    "shoulder_shrug": ("your shoulders lifted up towards your ears", "Relax your shoulders down, away from your ears."),
    "slouching": ("you slumped or leaned back away from the chair back",
                  "Sit up straight with your back against the chair."),
    "stepping_out": ("you stepped out of position during the hold", "If you wobble, step out or hold the counter: that is the safe thing to do. With practice you will hold it for longer."),
    "swinging": ("you swung your arms up quickly instead of lifting slowly",
                 "Lift slowly and pause at the top instead of swinging."),
    "thigh_lift": ("your whole thigh lifted off the seat", "Keep your thigh resting on the seat; only the lower leg moves."),
    "toes_up": ("your toes turned up or outwards as the leg lifted", "Keep your toes pointing forwards."),
    "too_deep": ("you bent your knees further than a mini squat", "Only bend your knees a little, about a third of the way down."),
    "trunk_forward": ("you bent forward at the waist", "Stand tall and keep your chest up."),
    "trunk_lean": ("your body leaned to the side", "Keep your body upright; do not lean to the side."),
    "uncontrolled_sit": ("you sat down too quickly instead of lowering yourself slowly", "Sit down slowly: reach back for the chair with your hands and lower yourself gently."),
    "uneven_arms": ("one arm went higher than the other", "Lift both arms together to the same height."),
    "upper_arm_moves": ("your upper arm moved away from your side", "Keep your upper arms still against your body."),
    "using_hands": ("your hands pulled your leg up", "Lift your legs without pulling them up with your hands."),
}
# Other ways people write a name.
MISTAKE_ALIASES = {"uneven arm": "uneven_arms", "hip sag": "hips_sag", "hips sagging": "hips_sag",
                   "shoulders shrug": "shoulder_shrug", "shrugging": "shoulder_shrug", "low arm": "low_range", "head tilt": "head_tilt",
                   "knee not straight": "knee_not_straight", "heel lift": "heels_lift", "hand used": "hands_used"}


# 3.72: the words the app's answers use, in plain words ("what does flexion mean", "apa maksud BMI").
# An exercise's full name ("tandem stance", "heel raise") gets the exercise's own answer instead.
TERMS = {
    "abduction": ("Abduction means moving an arm or a leg out to the side, away from your body. Shoulder "
                  "abduction lifts your arms out to the sides; hip abduction lifts a leg out to the side."),
    "adduction": "Adduction means moving an arm or a leg back in, towards your body.",
    "flexion": ("Flexion means bending a joint, or lifting a limb forward. Elbow flexion bends your elbow; "
                "shoulder flexion lifts your arm forward and up."),
    "extension": ("Extension means straightening a joint. Knee extension straightens your knee; wrist extension "
                  "lifts the back of your hand."),
    "range of motion": "Range of motion is how far a joint can move, for example how high you can lift your arm.",
    "repetition": ("A repetition (rep) is one complete movement of an exercise, for example lifting your arm up "
                   "and lowering it once."),
    "set": "A set is a group of repetitions done one after the other before you rest.",
    "intensity": ("Intensity is how hard an exercise feels. Low intensity feels easy: you can talk and sing. "
                  "Moderate intensity is a little harder: you can talk, but not sing."),
    "moderate intensity": ("Moderate intensity means the exercise feels a little hard: you breathe faster and "
                           "can still talk, but you cannot sing."),
    "low intensity": "Low intensity means the exercise feels easy: you can talk and even sing while doing it.",
    "rehabilitation": ("Rehabilitation (rehab) is exercise and care that help your body get back its strength and "
                       "movement after an illness, an injury, an operation or a long rest."),
    "physiotherapist": ("A physiotherapist (physio) is a health professional trained to help people recover "
                        "movement and strength with exercise."),
    "posture": ("Posture is the position of your body. In this app it means how you hold and move your body "
                "while you do an exercise."),
    "bmi": ("BMI (body mass index) is your weight in kilograms divided by your height in metres squared. It "
            "gives a rough idea of whether your weight suits your height; in this app it is shown for "
            "information only."),
    "warm up": "A warm-up is a few minutes of gentle movement before exercising, to get your muscles ready.",
    "cool down": "A cool-down is a few minutes of slow, gentle movement after exercising, to let your body settle.",
    "glute": "The glutes are the muscles of your buttocks. The glute bridge exercise makes them stronger.",
    "quadriceps": "The quadriceps (quads) are the large muscles at the front of your thigh. They straighten your knee.",
    "hamstrings": "The hamstrings are the muscles at the back of your thigh. They bend your knee.",
    "calf": "The calf is the muscle at the back of your lower leg. The heel raise exercise makes it stronger.",
    "core": "Your core is the muscles around your tummy and lower back that keep your body steady.",
    "mobility": "Mobility is how easily you can move, for example walk, stand up or reach.",
    "stamina": "Stamina (endurance) is how long you can keep going before you get tired.",
    "inflammation": ("Inflammation is swelling, warmth, redness or pain where your body is healing or "
                     "irritated."),
    "hold": "Hold means keeping a position still for a few seconds before you move again.",
    "atrophy": ("Atrophy means a muscle getting smaller and weaker because it has not been used, for example after "
                "weeks in bed. Regular exercise builds it back."),
    # 3.93: the words of the newer answers (readings, situations, conditions, symptoms)
    "spo2": ("SpO2 (oxygen saturation) is how much oxygen your blood is carrying, measured with a clip on your "
             "finger (a pulse oximeter). 95 to 100% is normal; 92% or lower needs a doctor."),
    "api": ("The API (Air Pollutant Index) measures air quality in Malaysia: up to 50 is good, 51 to 100 moderate, "
            "and above 100 unhealthy. On unhealthy days, exercise indoors."),
    "dvt": ("DVT (deep vein thrombosis) is a blood clot in a deep vein, usually in the leg. A calf that is suddenly "
            "swollen, red, warm and painful needs a doctor the same day."),
    "sahur": "Sahur is the meal eaten before dawn during the fasting month.",
    "iftar": "Iftar (berbuka puasa) is the meal that breaks the fast at sunset.",
    "sarcopenia": ("Sarcopenia is the loss of muscle size and strength with age or a long time without moving much. "
                   "Strength exercises and enough protein help to build it back."),
    "osteoporosis": ("Osteoporosis means the bones have become thin and weak, so they break more easily. Strength and "
                     "standing exercises help keep bones strong."),
    "hypertension": "Hypertension means high blood pressure: readings of 140/90 or higher, again and again.",
    "hypo": ("A hypo (hypoglycaemia) is a low blood sugar, usually below 4.0 mmol/L. It can make you shaky, sweaty, "
             "dizzy or confused: take something sugary at once."),
    "pursed lip breathing": ("Pursed-lip breathing means breathing in through your nose and out slowly through lips held "
                             "as if to whistle. It helps when you are short of breath."),
    "reliever inhaler": ("A reliever inhaler (often blue, such as Ventolin) opens the airways quickly when asthma symptoms "
                         "start."),
    "cardiac rehab": ("Cardiac rehabilitation (cardiac rehab) is a supervised programme of exercise and advice after a "
                      "heart attack or heart surgery, run by a hospital team."),
    "doms": ("DOMS (delayed onset muscle soreness) is the muscle ache that comes a day or two after exercise. It is "
             "normal and eases within a few days."),
    "bpm": "BPM means beats per minute: how fast your heart beats.",
    "resting heart rate": ("Your resting heart rate is your pulse after sitting quietly for a few minutes: 60 to 100 "
                           "beats a minute is usual."),
    "stitch": ("A stitch can mean two things: a sudden sharp pain under the ribs when you walk or breathe fast, or a "
               "thread a doctor uses to close a wound."),
    "blood thinner": ("A blood thinner (an anticoagulant, such as warfarin) makes the blood clot more slowly. People who "
                      "take one bruise and bleed more easily, so a fall needs extra care."),
    "cpap": ("CPAP is a machine that blows air through a mask while you sleep, to keep the airway open in sleep "
             "apnoea."),
}
TERM_ALIASES = {"abduct": "abduction", "adduct": "adduction", "flex": "flexion", "rom": "range of motion",
                "reps": "repetition", "rep": "repetition", "repetitions": "repetition", "sets": "set",
                "rehab": "rehabilitation", "physio": "physiotherapist", "physiotherapy": "physiotherapist",
                "body mass index": "bmi", "warm-up": "warm up", "warmup": "warm up", "cool-down": "cool down",
                "glutes": "glute", "quads": "quadriceps", "quad": "quadriceps", "hamstring": "hamstrings",
                "calves": "calf", "endurance": "stamina", "muscle atrophy": "atrophy", "disuse atrophy": "atrophy",
                "range of movement": "range of motion",
                # 3.81: the same words in Malay ("apa maksud fleksi")
                "fleksi": "flexion", "ekstensi": "extension", "abduksi": "abduction", "adduksi": "adduction",
                "julat pergerakan": "range of motion", "ulangan": "repetition", "pemulihan": "rehabilitation",
                "fisioterapi": "physiotherapist", "fisioterapis": "physiotherapist", "ahli fisioterapi": "physiotherapist",
                "postur": "posture", "intensiti": "intensity", "intensiti sederhana": "moderate intensity",
                "intensiti rendah": "low intensity", "memanaskan badan": "warm up", "menyejukkan badan": "cool down",
                "otot teras": "core", "atrofi": "atrophy", "keradangan": "inflammation", "mobiliti": "mobility",
                "daya tahan": "stamina", "indeks jisim badan": "bmi",
                # 3.93
                "sp02": "spo2", "oxygen saturation": "spo2", "oximeter": "spo2", "pulse oximeter": "spo2",
                "air pollutant index": "api", "ipu": "api", "deep vein thrombosis": "dvt", "berbuka": "iftar",
                "buka puasa": "iftar", "hypoglycaemia": "hypo", "hypoglycemia": "hypo", "pursed lip": "pursed lip breathing",
                "pursed lips breathing": "pursed lip breathing", "blue inhaler": "reliever inhaler",
                "cardiac rehabilitation": "cardiac rehab", "delayed onset muscle soreness": "doms",
                "beats per minute": "bpm", "anticoagulant": "blood thinner", "blood thinners": "blood thinner",
                "a stitch": "stitch"}




# 4.05: each tip as a patient describes it in Malay (tenth probe: "dia kata lutut saya tak lurus", "saya condong ke
# depan", "saya guna tangan masa bangun", "tangan saya tak sama tinggi" were not recognised). The English names
# are matched as names (glossary); these are keywords. No "jatuh" (fall) in them: hips dropping is "turun".
MISTAKE_KEYWORDS = {
    "not_closed": ["tangan tak tutup", "tak genggam penuh", "genggam tak penuh"],
    "arm_leg_low": ["tangan dan kaki rendah", "kaki dan tangan rendah"],
    "back_arch": ["belakang melengkung", "pinggang melengkung"],
    "back_sag": ["belakang melendut", "pinggang melendut", "pinggul senget"],
    "bent_elbow": ["siku bengkok", "siku tak lurus"],
    "bent_knee": ["lutut bengkok", "lutut tak lurus masa angkat kaki"],
    "body_swing": ["badan berayun", "hayun badan", "goyang badan"],
    "drop_down": ["turun terlalu cepat", "turun laju sangat", "turun tangga laju"],
    "feet_far": ["kaki terlalu jauh", "kaki jauh sangat", "kaki jauh dari punggung"],
    "feet_forward": ["kaki terlalu ke depan", "kaki ke depan sangat"],
    "feet_not_in_line": ["kaki tak segaris", "kaki tak satu garisan", "kaki sebelah menyebelah"],
    "hands_used": ["guna tangan masa bangun", "guna tangan untuk bangun", "tolak dengan tangan", "tolak kerusi",
                   "pegang lutut masa bangun"],
    "heels_lift": ["tumit terangkat", "tumit naik"],
    "hips_back": ["punggung ke belakang", "tolak punggung ke belakang"],
    "hips_sag": ["pinggul turun", "punggung turun", "punggung jatuh", "pinggul jatuh"],
    "incomplete_extension": ["lutut tak lurus sepenuhnya", "kaki tak lurus sepenuhnya", "tak luruskan lutut"],
    "incomplete_stand": ["tak berdiri tegak", "tak berdiri lurus", "tak bangun sepenuhnya"],
    "fingers_not_spread": ["jari tak terbuka", "jari tak buka luas", "jari rapat"],
    "head_tilt": ["kepala senget", "kepala condong"],
    "knee_not_straight": ["lutut tak lurus", "lutut tidak lurus", "kaki tak lurus"],
    "knees_bend": ["lutut bengkok masa jengket", "lutut bengkok bila naik"],
    "leaning": ["bersandar pada kaunter", "condong ke tepi", "bersandar kat kaunter"],
    "leaning_back": ["condong ke belakang", "sandar ke belakang"],
    "leaning_forward": ["condong ke depan", "badan condong ke depan", "tunduk ke depan"],
    "leg_forward": ["kaki ke depan bukan ke sisi", "kaki pergi ke depan"],
    "low_hips": ["pinggul tak cukup tinggi", "punggung tak cukup tinggi"],
    "low_knee_lift": ["lutut tak cukup tinggi", "lutut rendah sangat"],
    "low_raise": ["tumit tak cukup tinggi", "jengket tak tinggi"],
    "low_range": ["pergerakan tak cukup", "gerak tak cukup jauh"],
    "no_arm_swing": ["tangan tak hayun", "tak hayun tangan"],
    "no_forward_lean": ["tak condong ke depan", "tak bongkok ke depan"],
    "no_hold": ["tak tahan di atas", "tak tahan sekejap", "tak berhenti di atas"],
    "over_arch": ["punggung terlalu tinggi", "pinggul terlalu tinggi"],
    "shoulder_shrug": ["bahu terangkat", "bahu naik", "angkat bahu"],
    "slouching": ["duduk bongkok", "badan bongkok", "membongkok", "belakang bengkok"],
    "stepping_out": ["terlangkah keluar", "kaki terkeluar", "terkeluar dari posisi"],
    "swinging": ["hayun tangan laju", "angkat tangan laju"],
    "thigh_lift": ["paha terangkat", "peha terangkat", "paha naik"],
    "toes_up": ["jari kaki terangkat", "jari kaki ke atas", "jari kaki ke luar"],
    "too_deep": ["cangkung terlalu dalam", "turun terlalu rendah"],
    "trunk_forward": ["bongkok di pinggang", "badan tunduk"],
    "trunk_lean": ["badan condong ke tepi", "badan senget"],
    "uncontrolled_sit": ["duduk terlalu cepat", "duduk laju sangat", "hempas duduk"],
    "uneven_arms": ["tangan tak sama tinggi", "tangan tak sama"],
    "upper_arm_moves": ["lengan atas bergerak", "lengan tak rapat badan"],
    "using_hands": ["tarik kaki dengan tangan", "guna tangan tarik kaki"],
}


def mistake_intents():
    out = []
    for label, (meaning, tip) in MISTAKE_MEANING.items():
        words = label.replace("_", " ")
        out.append(intent(f"mistake:{label}", words.capitalize(), 6, MISTAKE_KEYWORDS.get(label, []),
                          [f"what does {words} mean", f"the result said {words}"],
                          f"\u201c{words.capitalize()}\u201d in your posture result means {meaning}. {tip}", show=False,
                          action={"key": "open_history", "label": "See my results"}))
    return out


def glossary():
    """Phrase -> mistake intent key, for questions that ask what a name means."""
    g = {label.replace("_", " "): f"mistake:{label}" for label in MISTAKE_MEANING}
    g.update({label: f"mistake:{label}" for label in MISTAKE_MEANING if "_" in label})
    g.update({alias: f"mistake:{label}" for alias, label in MISTAKE_ALIASES.items()})
    return g


def build() -> dict:
    cat = json.loads(CATALOGUE.read_text(encoding="utf-8"))
    exercises = {}
    for e in cat["exercises"]:
        key = e["pose_key"]
        exercises[key] = {"name": e["exercise_name"], "aliases": ALIASES.get(key, [e["exercise_name"].lower()]),
                          "instruction": clean_instruction(e["instruction_text"]),
                          "camera": (re.match(r"^Camera:([^.]*)\.", e["instruction_text"]) or [None, ""])[1].strip()}
    plans = {}
    for p in cat["plans"]:
        items = sorted(p["plan_exercise"], key=lambda x: x["sequence_order"])
        plans[p["plan_id"]] = {
            "plan_name": p["plan_name"], "goal": p.get("goal"), "frequency_per_week": p["frequency_per_week"],
            "goal_text": GOAL_TEXT.get(p.get("goal") or "", "support your recovery"),
            "exercises": [{"pose_key": x["exercise"]["pose_key"], "name": x["exercise"]["exercise_name"],
                           "repetitions": x["prescribed_repetitions"], "duration": duration(x["prescribed_duration_sec"]),
                           "order": i} for i, x in enumerate(items, 1)],
        }
    for i in INTENTS:
        if i["key"] in ACTIONS and not i.get("action"):
            i["action"] = ACTIONS[i["key"]]
        if i["key"] in MORE_ACTIONS and not i.get("more_actions"):
            i["more_actions"] = MORE_ACTIONS[i["key"]]
        i["time_aware"] = i["key"] in TIME_AWARE
        if i["key"] in TAILORED:
            i["tailor"] = True
    for i in INTENTS:
        i["answer"] = layout(i["answer"])
    restrictions = {k: {**v, "answer": layout(v["answer"])} for k, v in RESTRICTIONS.items()}
    rules = {
        "version": VERSION,
        "not_recognised": NOT_RECOGNISED,
        "intents": INTENTS + [{**m, "answer": layout(m["answer"])} for m in mistake_intents()],
        "glossary": glossary(),
        "exercises": exercises,
        "plans": plans,
        "condition_notes": CONDITION_NOTES,
        "limitation_notes": LIMITATION_NOTES,
        "risk_notes": RISK_NOTES,
        "late_night_note": LATE_NIGHT_NOTE,
        "time_notes": TIME_NOTES,
        "now_notes": NOW_NOTES,
        "condition_detail": {k: layout(v) for k, v in CONDITION_DETAIL.items()}
        | {k: layout(text) for k, (_, text) in UNLISTED_CONDITIONS.items()},
        "condition_closing": CONDITION_CLOSING,
        "condition_closing_other": CONDITION_CLOSING_OTHER,
        "drug_names": DRUG_NAMES,
        "unlisted_conditions": sorted(UNLISTED_CONDITIONS),
        "condition_words": {**{w: code for code, (words, _) in UNLISTED_CONDITIONS.items() for w in words},
                            **{w: code for code, words in LISTED_NAMES.items() for w in words}},
        "diet_notes": DIET_NOTES,
        "red_flags": RED_FLAGS,
        "crisis": CRISIS,
        "crisis_answer": CRISIS_ANSWER,
        "crisis_answer_other": CRISIS_ANSWER_OTHER,
        "red_flag_combos": RED_FLAG_COMBOS,
        "red_flag_answer": RED_FLAG_ANSWER,
        "restrictions": restrictions,
        "terms": {k: layout(v) for k, v in TERMS.items()},
        "term_aliases": TERM_ALIASES,
    }
    OUT.write_text(json.dumps(rules, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return rules


if __name__ == "__main__":
    r = build()
    shown = sum(1 for i in r["intents"] if i["show"])
    print(f"{VERSION}: {len(r['intents'])} intents ({shown} shown), {len(r['exercises'])} exercises, "
          f"{len(r['plans'])} plans, {len(r['red_flags'])} red-flag phrases -> {OUT}")
