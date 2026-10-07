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
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CATALOGUE = ROOT / "assets" / "seed" / "catalogue.json"
OUT = Path(__file__).with_name("rules.json")
VERSION = "chat-rules-3.30"

NOT_RECOGNISED = "The question is not recognised, please try asking other question."   # UC400 M7, FR500_22


def intent(key, title, priority, keywords, examples, answer, show=True, follow_ups=(), tailor=False,
           negatable=False, anchor_start=False, small_talk=False, action=None):
    """negatable: a keyword right after "no"/"not" does not count ("I have no pain").
    anchor_start: keywords count only at the start of the message (greetings).
    small_talk: wins outright when the whole message is three words or fewer ("good morning", "help").
    action: a button the app shows under the answer, {"key": ..., "label": ...}; the app maps the key
    to a screen (open_reset_password, open_planning, open_profile, open_treatment)."""
    return {"key": key, "title": title, "show": show, "priority": priority, "keywords": list(keywords),
            "examples": list(examples), "answer": answer, "follow_ups": list(follow_ups), "tailor": tailor,
            "negatable": negatable, "anchor_start": anchor_start, "small_talk": small_talk, "action": action}


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
           action={"key": "open_planning", "label": "Open treatment planning"}),
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
            "broken bone", "broke my", "sprain", "sprained"],
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
            "worn out", "sleepy", "drained", "fell asleep", "out of breath", "breathing hard", "panting", "not feeling well", "feel unwell", "unwell", "sick", "ill", "fever",
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
            "lost my balance", "feel like falling", "jelly", "no strength", "not strong", "heavy legs"],
           ["my leg feels wobbly when standing", "my legs feel weak", "I feel unsteady on my feet",
            "my knee gives way", "I lose my balance"],
           "Legs that feel weak or wobbly are common after a long period of less activity, and this is what your "
           "exercises are building up. Always keep one hand on a sturdy chair or counter, do fewer repetitions, "
           "and rest when the shaking starts. If weakness comes on suddenly, or affects one side of your body, "
           "stop and get medical help straight away.", tailor=True, negatable=True),
    intent("recording_help", "Recording your exercise video", 5,
           ["record", "recording", "recorded", "video", "videos", "camera", "film", "filming", "phone position",
            "put my phone", "put the phone", "where to put", "tripod", "stand for my phone", "full body",
            "not detected", "can't detect", "cannot detect", "can't see me", "cannot see me", "can't see my",
            "upload", "uploading", "angle", "frame", "720p", "resolution", "too long", "too short", "front or side",
            "in front or", "at the side", "lighting", "dark", "someone record", "record for me",
            "no repetition", "no repetitions", "no reps found", "repetition found", "no complete repetition",
            "landscape", "portrait", "horizontal or vertical", "sideways or upright", "phone stand",
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
           action={"key": "open_planning", "label": "Open treatment planning"}),
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
            "volume", "ringtone"],
           ["how do I change my reminder time", "I am not getting reminders", "how do I turn off reminders"],
           "Your reminders follow your plan's weekly schedule. Open Reminders to change the time or switch a "
           "reminder off and on. If none arrive, check that notifications are allowed for HealthGuide in your "
           "phone settings. If you have already exercised that day, the reminder is skipped. The reminder "
           "sound and volume follow your phone's notification settings.",
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
           "so your whole body fills most of the picture, from head to feet.", show=False,
           action={"key": "open_treatment", "label": "Record an exercise"}),
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
            "after a fall", "get up after a fall", "get up from the floor", "get up if i fall", "nobody is home",
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
           "app's text grows with it. A family member can also sit with you while you use the app.",
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
    intent("plan_and_reminders", "Changing your plan or reminders", 5,
           ["two plans", "more than one plan", "both plans", "second plan", "get a new plan", "new plan",
            "change plan", "change my plan", "new plan", "different plan", "another plan", "switch plan",
            "switch to", "stop plan", "stop the plan", "stop this plan", "change this plan", "end this plan",
            "quit this plan", "leave this plan", "stop my plan", "end my plan", "delete plan", "cancel plan", "quit"],
           ["how do I change my plan", "can I get a different plan", "how do I stop this plan"],
           "To change plan, open AI-assisted planning and choose Retrieve physical treatment to get new "
           "recommendations; selecting a new plan replaces the current one. You can stop a plan from the "
           "Physical Treatment page. Reminders follow your plan's weekly schedule; check that notifications are "
           "allowed for the app in your phone settings if they do not appear."),
    intent("forgot_password", "Forgot password", 7,
           ["forgot password", "forgot my password", "forget password", "forget my password", "forgotten password",
            "forgot pasword", "forgot passwrod", "forgot pass", "pasword", "passwrod", "passward", "pass word",
            "password", "my password", "help with my password",
            "change pasword", "reset pasword",
            "reset password", "reset my password", "password reset", "change password", "change my password",
            "new password", "cant remember my password", "can't remember my password", "lost my password",
            "wrong password", "password not working", "locked out", "account locked", "cannot log in",
            "can't log in", "cant log in", "unable to log in", "cannot login", "can't login", "cant login"],
           ["I forgot my password", "how do I reset my password", "I can't log in", "how do I change my password"],
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
            "email never came", "no email from you", "didn't get email", "didnt get email"],
           ["I did not get the verification code", "the code is not working", "how do I verify my email"],
           "The 6-digit code is sent to the email you registered with. Check your spam or junk folder, and make "
           "sure the address is spelled correctly. You can tap Resend code once a minute; a code stops working "
           "after a while, so always use the newest one. If you clicked a link in the email instead, return to "
           "the app and log in.", show=False),
    intent("account_help", "Account and login", 6,
           ["my information", "my info", "my data", "who can see", "privacy", "private", "personal data", "data safe", "delete my account", "delete account",
            "log in", "login", "log out", "logout", "sign in", "sign out", "account", "email",
            "username", "google sign in",
            "change my details", "delete my account", "my data", "privacy"],
           ["how do I log in", "how do I update my health profile", "is my data private"],
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
           ["sharp", "stabbing", "shooting", "getting worse", "worse", "worsening", "sudden pain", "pain during",
            "can't move", "cannot move", "very painful", "really hurts", "unbearable", "won't go away", "not going away",
            "every time", "keeps hurting"],
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
           ["medicine", "medicines", "medication", "medications", "pill", "pills", "tablet", "tablets", "painkiller",
            "painkillers", "pain killer", "panadol", "paracetamol", "ibuprofen", "aspirin", "insulin", "drug", "drugs",
            "dose", "dosage", "prescription", "supplement", "supplements", "vitamin", "vitamins", "cream", "ointment",
            "injection", "inhaler dose"],
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
            "go to hospital", "see a physiotherapist", "should i see"],
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
            "app is great", "very helpful", "so helpful"],
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
            "how do you work", "chatbot", "chat bot"],
           ["what can you do", "what can I ask you", "are you a real person"],
           "I am the rehabilitation assistant for your treatment plan. I answer common questions using answers "
           "prepared in advance, so I cannot diagnose or give medical advice. You can ask about how to do your "
           "exercises, pain, safety, how often to exercise, recording your video, your posture score, and "
           "your plan or reminders.", show=False, small_talk=True),
]

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
                     "standing up from a chair", "stand up from the chair", "sitting to standing"],
    "shoulder_abduction": ["shoulder abduction", "side arm raise", "side arm raises", "lateral arm raise",
                           "lateral raise", "arm raise to the side", "raise my arms to the side", "arms sideways"],
    "shoulder_flexion": ["shoulder flexion", "front arm raise", "front arm raises", "forward arm raise",
                         "raise my arms forward", "arms forward", "arm raise to the front"],
    "hip_abduction": ["hip abduction", "standing hip abduction", "side leg raise", "side leg raises",
                      "leg raise to the side", "lift my leg to the side", "leg sideways"],
    "knee_extension": ["knee extension", "seated knee extension", "knee extensions", "straighten my knee",
                       "straightening my knee", "leg extension", "seated leg raise", "leg straightening"],
    "elbow_flexion": ["elbow flexion", "bicep curl", "bicep curls", "biceps curl", "arm curl", "arm curls", "curl",
                      "curls", "elbow bend", "bend my elbow"],
    "wall_push_up": ["wall push up", "wall push-up", "wall pushup", "wall push ups", "wall push-ups", "wall pushups",
                     "push up against the wall", "push up on the wall", "close to the wall", "far from the wall",
                     "distance from the wall"],
    "heel_raise": ["heel raise", "heel raises", "calf raise", "calf raises", "tiptoe", "tiptoes", "toe raise",
                   "rise on my toes", "stand on my toes", "my heels", "raise my heels",
                   "lift my heels", "heels up"],
    "mini_squat": ["mini squat", "mini squats", "half squat", "small squat", "partial squat", "squat", "squats"],
    "seated_marching": ["seated marching", "seated march", "sitting march", "marching while sitting",
                        "march while sitting", "march sitting down", "march", "marching"],
    "glute_bridge": ["glute bridge", "glute bridges", "hip bridge", "bridge exercise", "bridging", "bridge"],
    "tandem_stance": ["tandem stance", "tandem stand", "heel to toe", "heel-to-toe", "one foot in front of the other",
                      "balance stand"],
    "bird_dog": ["bird dog", "bird-dog", "birddog", "bird dogs", "opposite arm and leg"],
    "step_up": ["step up", "step-up", "step ups", "step-ups", "stepping up", "stair step", "my step",
                "step height", "high step", "step too high", "step is"],
    "march_in_place": ["march in place", "marching in place", "march on the spot", "marching on the spot",
                       "standing march", "marching standing", "march", "marching"],
}

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
]
CRISIS_ANSWER = ("I am really sorry you are feeling this way, and I am glad you said it. You are not alone. If you "
                 "are in danger now or might act on these thoughts, call 999 or go to the nearest emergency "
                 "department. You can talk to someone right now: Befrienders KL 03-7627 2929 (24 hours, free and "
                 "confidential) or Talian HEAL 15555 (8 am to midnight daily). Please also tell a family member "
                 "or your doctor how you feel. I am only an exercise assistant, but these people can help you.")
# Emergencies described in free words: an anchor word with a symptom word close to it, in any order
# ("my chest feels heavy and painful", "i can hardly breathe", "my arm suddenly cannot move").
# [anchors, symptoms, window in words]. A "no"/"not"/"never" just before the anchor cancels it
# ("no chest pain"); "can't"/"cannot" do not, they are part of the symptom ("cannot breathe").
RED_FLAG_COMBOS = [
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
    # A person lying on the floor, not doing the exercise ("my father is lying on the kitchen floor").
    [["lying"], ["mum", "mom", "mother", "dad", "father", "husband", "wife", "grandma", "grandpa",
                 "grandmother", "grandfather", "he", "she", "son", "daughter"], 3,
     ["bridge", "exercise", "mat", "bird dog", "doing", "for the", "resting", "rest", "nap", "session", "sofa",
      "relax", "relaxing"]],
    # Someone found on the floor ("found my mum on the floor"): a person must be named.
    [["found"], ["mum", "mom", "mother", "dad", "father", "husband", "wife", "grandma", "grandpa",
                 "grandmother", "grandfather", "him", "her", "son", "daughter"], 3],
    # One side of the face drooping (stroke), in everyday words ("face one side drop").
    [["face", "mouth"], ["drop", "droop", "drooping", "dropping", "dropped", "crooked", "lopsided",
                         "one side"], 3],
    [["chest"], ["pain", "painful", "hurt", "hurts", "hurting", "heavy", "heaviness", "pressure", "tight",
                 "tightness", "squeeze", "squeezing", "ache", "aching", "burning", "crushing"], 4],
    [["breathe", "breath", "breathing"], ["hardly", "barely", "can't", "cannot", "difficult", "difficulty",
                                          "trouble", "struggle", "struggling", "hard", "gasping"], 3],
    [["suddenly", "sudden"], ["weak", "weakness", "numb", "numbness", "can't move", "cannot move",
                              "paralysed", "paralyzed", "drooping", "droop", "slurred", "can't speak",
                              "cannot speak", "collapse", "collapsed", "confused", "can't see", "cannot see",
                              "cannot talk", "can't talk", "cant talk", "talk properly", "speak properly",
                              "cannot lift", "can't lift", "cant lift", "cannot raise", "can't raise"], 5],
]

RED_FLAG_ANSWER = ("Stop exercising now. If you have chest pain, trouble breathing, fainting, sudden weakness or "
                   "numbness, slurred speech, or severe swelling, call 999 or go to the nearest emergency "
                   "department. For other new pain, dizziness or a fall, sit down, rest, and contact your doctor "
                   "before exercising again.")


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
    "condition_advice": {"key": "open_profile", "label": "Update my health conditions"},
    "account_help": {"key": "open_profile", "label": "Open my profile"},
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
                         "Stand up fully: straighten your hips and knees at the top."),
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
                   "shoulders shrug": "shoulder_shrug", "shrugging": "shoulder_shrug", "low arm": "low_range",
                   "knee not straight": "knee_not_straight", "heel lift": "heels_lift", "hand used": "hands_used"}


def mistake_intents():
    out = []
    for label, (meaning, tip) in MISTAKE_MEANING.items():
        words = label.replace("_", " ")
        out.append(intent(f"mistake:{label}", words.capitalize(), 6, [],
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
        i["time_aware"] = i["key"] in TIME_AWARE
        if i["key"] in TAILORED:
            i["tailor"] = True
    rules = {
        "version": VERSION,
        "not_recognised": NOT_RECOGNISED,
        "intents": INTENTS + mistake_intents(),
        "glossary": glossary(),
        "exercises": exercises,
        "plans": plans,
        "condition_notes": CONDITION_NOTES,
        "limitation_notes": LIMITATION_NOTES,
        "risk_notes": RISK_NOTES,
        "late_night_note": LATE_NIGHT_NOTE,
        "time_notes": TIME_NOTES,
        "now_notes": NOW_NOTES,
        "condition_detail": CONDITION_DETAIL,
        "condition_closing": CONDITION_CLOSING,
        "diet_notes": DIET_NOTES,
        "red_flags": RED_FLAGS,
        "crisis": CRISIS,
        "crisis_answer": CRISIS_ANSWER,
        "red_flag_combos": RED_FLAG_COMBOS,
        "red_flag_answer": RED_FLAG_ANSWER,
    }
    OUT.write_text(json.dumps(rules, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return rules


if __name__ == "__main__":
    r = build()
    shown = sum(1 for i in r["intents"] if i["show"])
    print(f"{VERSION}: {len(r['intents'])} intents ({shown} shown), {len(r['exercises'])} exercises, "
          f"{len(r['plans'])} plans, {len(r['red_flags'])} red-flag phrases -> {OUT}")
