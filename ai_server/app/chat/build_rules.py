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
VERSION = "chat-rules-3.11"

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
           ["rest between", "between reps", "between sets", "between exercises", "break between", "how to do", "how do i do", "how should i do", "how to perform", "correct way", "right way", "proper way",
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
            "how many sessions", "session length", "duration", "minutes", "weekend", "weekends", "consecutive"],
           ["how often should I exercise", "can I do this every day", "how many times a week", "how long should each session be",
            "should I take rest days", "what time of day is best"],
           "Follow the number of sessions per week shown in your plan, with a rest day in between when you can. "
           "Each session only takes a few minutes, and any time of day that suits you is fine, as long as it is "
           "not straight after a big meal. Your reminders already follow this schedule. Doing the exercises well "
           "matters more than doing extra sessions.", tailor=True),
    intent("missed_session", "Missed a session", 5,
           ["missed", "miss", "skip", "skipped", "skipping", "forgot", "forgotten", "didn't exercise", "did not exercise",
            "haven't exercised", "have not exercised", "fell behind", "behind schedule", "catch up", "make up",
            "lazy", "no time", "too busy", "busy", "stopped exercising", "break from"],
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
            "sugar reading"],
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
           ["sitting down", "seated version", "while sitting", "do it sitting", "cannot lift", "can't lift", "cannot raise", "can't raise", "not high enough", "cannot reach", "can't reach",
            "too easy", "too hard", "too difficult", "difficult", "struggle", "struggling", "can't finish",
            "cannot finish", "can't complete", "can't do", "cannot do", "unable to", "harder", "easier",
            "challenging", "not challenging", "progress to", "increase", "decrease", "fewer reps", "more reps",
            "add more", "level up", "too much", "too little", "boring", "modify", "instead of these exercises", "instead of the exercises",
            "instead of this exercise", "something else", "other exercise", "another exercise", "different exercise",
            "replace", "can only",
            "only do", "only manage", "only managed", "only able"],
           ["the exercises are too easy", "this is too hard for me", "I can't finish all the repetitions",
            "can I make it harder", "can I do more repetitions"],
           "If an exercise is too hard, do fewer repetitions with good form and rest between them; it should feel "
           "like effort, not pain. If it feels too easy, keep the same plan until you finish it, then request a "
           "new recommendation from the planning page: it will suggest a plan for your new level. Do not add "
           "weight, extra sets or other exercises on your own.", tailor=True),
    intent("tired", "Feeling tired or unwell", 6,
           ["didn't sleep well", "did not sleep well", "not sleep well", "slept badly", "slept poorly", "poor sleep",
            "bad sleep", "no sleep", "sleepy", "not enough sleep", "tired", "tiring", "exhausted", "exhausting", "fatigue", "fatigued", "no energy", "low energy",
            "worn out", "sleepy", "drained", "not feeling well", "feel unwell", "unwell", "sick", "ill", "fever",
            "cold", "flu", "cough", "headache", "period", "bad day"],
           ["I feel too tired to exercise", "I am exhausted after the session", "I'm not feeling well today",
            "should I exercise when I am sick"],
           "Feeling a little tired after exercising is normal. If you are unusually exhausted, unwell, or have a "
           "fever, skip today's session and rest; continue when you feel better. If tiredness lasts for days or "
           "comes with breathlessness, contact your doctor.", negatable=True),
    intent("weakness_balance", "Weak or unsteady legs", 7,
           ["walking stick", "use a stick", "walking cane", "walker", "walking frame", "zimmer", "crutch", "crutches", "wheelchair", "lose my balance", "lose balance",
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
            "in front or", "at the side", "lighting", "dark", "someone record", "record for me"],
           ["how do I record my exercise", "where should I put my phone", "the app cannot detect my body",
            "why does it say my full body is not visible", "how long should the video be"],
           "Put your phone on a stand, upright, at about waist height and 2.5 to 3 metres away, so your whole "
           "body from head to feet stays in the picture during the movement. Use good light in front of you "
           "and record 10 to 30 seconds. Each exercise says whether the camera should face you or be at your "
           "side. Someone else may hold the phone for you if it stays still. If the app cannot see your whole "
           "body, step back a little and record again."),
    intent("posture_result", "Understanding your posture score", 6,
           ["frustrated", "always low", "keep failing", "never pass",
            "score", "scores", "accuracy", "percent", "percentage", "my result", "the result", "result mean",
            "results page", "feedback", "posture check", "posture analysis", "retry", "try again", "low score",
            "app said", "the app says", "app told me", "it said my", "said my", "says my", "too far forward",
            "failed", "fail", "pass", "passed", "80", "correction", "corrections", "tips", "what did i do wrong",
            "wrong posture", "bad posture"],
           ["what does my posture score mean", "why is my accuracy low", "what do I do if I fail the posture check",
            "should I retry the exercise"],
           "The posture score shows how closely your movement matched the correct form, as a percentage, with "
           "tips on what to change. At 80% or more your progress is updated automatically. Below that you can "
           "read the tips and retry, or continue; every attempt is saved so you can see your improvement."),
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
            "how to use the app", "how to use app", "app works", "using this app", "use this app"],
           ["how does this app work", "how do I use this app"],
           "HealthGuide has five tabs. Home shows today's session and your daily limits. Treatment holds your "
           "plan: get one in AI-assisted treatment planning, then do each exercise and record it so the app can "
           "check your posture. Profile holds your health details, which keep your advice safe. You can ask me "
           "about any of these at any time.", show=False,
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
            "turn off reminders", "stop reminders", "turn on reminders", "missed reminder"],
           ["how do I change my reminder time", "I am not getting reminders", "how do I turn off reminders"],
           "Your reminders follow your plan's weekly schedule. Open Reminders to change the time or switch a "
           "reminder off and on. If none arrive, check that notifications are allowed for HealthGuide in your "
           "phone settings. If you have already exercised that day, the reminder is skipped.",
           show=False, action={"key": "open_reminders", "label": "Open reminders"}),
    intent("history_help", "Your past results", 6,
           ["see my score", "see my scores", "score last week", "scores last week", "last week", "my score history", "past scores", "past results", "previous results", "my results", "session history",
            "previous sessions", "past sessions", "how did i do", "accuracy history",
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
           ["verification code", "verify code", "no code", "didn't get the code", "didnt get the code",
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
           "medicines as prescribed unless they tell you otherwise.", show=False),
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
           ["who are you", "what are you", "your name", "are you human", "are you a robot", "are you a bot",
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
                     "push up against the wall", "push up on the wall"],
    "heel_raise": ["heel raise", "heel raises", "calf raise", "calf raises", "tiptoe", "tiptoes", "toe raise",
                   "rise on my toes", "stand on my toes"],
    "mini_squat": ["mini squat", "mini squats", "half squat", "small squat", "partial squat", "squat", "squats"],
    "seated_marching": ["seated marching", "seated march", "sitting march", "marching while sitting",
                        "march while sitting", "march sitting down"],
    "glute_bridge": ["glute bridge", "glute bridges", "hip bridge", "bridge exercise", "bridging", "bridge"],
    "tandem_stance": ["tandem stance", "tandem stand", "heel to toe", "heel-to-toe", "one foot in front of the other",
                      "balance stand"],
    "bird_dog": ["bird dog", "bird-dog", "birddog", "bird dogs", "opposite arm and leg"],
    "step_up": ["step up", "step-up", "step ups", "step-ups", "stepping up", "stair step"],
    "march_in_place": ["march in place", "marching in place", "march on the spot", "marching on the spot",
                       "standing march", "marching standing"],
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
    "dizzy", "dizziness", "light headed", "lightheaded", "severe pain", "extreme pain", "severe swelling",
    "very swollen", "badly swollen", "numb", "numbness", "heart racing", "racing heart", "heart is racing", "heart beating fast", "heart pounding",
    "heart is pounding", "palpitations", "irregular heartbeat", "fell down", "i fell", "i've fallen", "had a fall", "hit my head",
    "slurred speech", "speech is slurred", "slurring", "slurred", "face drooping", "face is drooping", "sudden weakness", "can't feel my", "cannot feel my", "coughing blood",
    "vomiting", "unconscious",
]
# Emergencies described in free words: an anchor word with a symptom word close to it, in any order
# ("my chest feels heavy and painful", "i can hardly breathe", "my arm suddenly cannot move").
# [anchors, symptoms, window in words]. A "no"/"not"/"never" just before the anchor cancels it
# ("no chest pain"); "can't"/"cannot" do not, they are part of the symptom ("cannot breathe").
RED_FLAG_COMBOS = [
    [["chest"], ["pain", "painful", "hurt", "hurts", "hurting", "heavy", "heaviness", "pressure", "tight",
                 "tightness", "squeeze", "squeezing", "ache", "aching", "burning", "crushing"], 4],
    [["breathe", "breath", "breathing"], ["hardly", "barely", "can't", "cannot", "difficult", "difficulty",
                                          "trouble", "struggle", "struggling", "hard", "gasping"], 3],
    [["suddenly", "sudden"], ["weak", "weakness", "numb", "numbness", "can't move", "cannot move",
                              "paralysed", "paralyzed", "drooping", "droop", "slurred", "can't speak",
                              "cannot speak", "collapse", "collapsed", "confused", "can't see", "cannot see"], 5],
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
        "intents": INTENTS,
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
