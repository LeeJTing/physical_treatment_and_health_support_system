"""Round 19 (14 Oct, PC): one question per app feature the chatbot had no answer for (Elwin: "make the
chatbot more complete"). Written before changing the rules, from a probe of 57 feature and health
questions: plan reasons and sources, risk level, safety limits, the planning questions, the exercise
animation, Health Connect, app facts (free, phone, contact), plus questions that went to the wrong
answer (a child using the app, counting repetitions, restarting a plan, an old phone, fasting,
blood thinners, a cold or COVID).
"""
from chat_round1_set import KNEE

ROUND19 = [
    # Why this plan / why not (11 Oct)
    (KNEE, "why was this plan chosen for me", "plan_reasons"),
    (KNEE, "why not the other plans", "plan_reasons"),
    (KNEE, "what are the sources under the reasons", "plan_reasons"),
    (KNEE, "what does app safety rule mean", "plan_reasons"),
    (KNEE, "why is this plan recommended", "plan_reasons"),
    # Risk level and BMI
    (KNEE, "why am i high risk", "risk_level"),
    (KNEE, "what does my risk level mean", "risk_level"),
    (KNEE, "how is my risk calculated", "risk_level"),
    (KNEE, "how to lower my risk level", "risk_level"),
    (KNEE, "what is bmi", ("risk_level", "word_meaning")),        # 3.72: the BMI meaning itself
    # Safety limits
    (KNEE, "what is my safety limit", "safety_limits"),
    (KNEE, "why is my intensity limited", "safety_limits"),
    (KNEE, "why is my session only 20 minutes", "safety_limits"),
    (KNEE, "what are the daily limits on home", "safety_limits"),
    # The planning questions
    (KNEE, "what is recovery stage", "planning_questions"),
    (KNEE, "which mobility level should i choose", "planning_questions"),
    (KNEE, "what goal should i pick", "planning_questions"),
    (KNEE, "what does pace mean", "planning_questions"),
    # The exercise animation (11 Oct)
    (KNEE, "what is the moving figure in the exercise", "guide_animation"),
    (KNEE, "the animation is not showing", "guide_animation"),
    (KNEE, "the stick figure moves too fast", "guide_animation"),
    # Health Connect and devices
    (KNEE, "how to connect my smartwatch", "health_connect"),
    (KNEE, "what is health connect", "health_connect"),
    (KNEE, "can i link my fitness band", "health_connect"),
    # App facts
    (KNEE, "is this app free", "app_facts"),
    (KNEE, "can i use it on iphone", "app_facts"),
    (KNEE, "my phone is old will it work", "app_facts"),
    (KNEE, "how to contact you", "app_facts"),
    (KNEE, "who do i email for help", "app_facts"),
    # Went to the wrong answer in the probe
    (KNEE, "can my child use this app", "guardian_consent"),
    (KNEE, "how are repetitions counted", "posture_result"),
    (KNEE, "can i restart my plan", "plan_and_reminders"),
    (KNEE, "can i exercise during ramadan fasting", "best_time"),
    (KNEE, "i take blood thinners can i exercise", "medication"),
    (KNEE, "i just had covid can i exercise", "tired"),
    (KNEE, "can i exercise if i have a cold", "tired"),
]
