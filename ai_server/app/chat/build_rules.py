"""Builds rules.json for the rehabilitation chatbot (M500.2, FR500_17 to FR500_22).

General categories are written here by hand. The two plan-specific categories
are generated from the catalogue (assets/seed/catalogue.json), so their
answers always list each plan's real exercises, repetitions and frequency.
Re-run after the catalogue changes:

    python ai_server/app/chat/build_rules.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CATALOGUE = ROOT / "assets" / "seed" / "catalogue.json"
OUT = Path(__file__).with_name("rules.json")

GENERAL = [
    {"key": "how_to", "title": "How to do the exercises",
     "keywords": ["how to do", "how do i do", "correct way", "proper form", "technique", "instructions", "steps"],
     "examples": ["how do I do the exercises", "what is the correct way to do this exercise",
                  "how do I know my form is right", "can you explain the steps"],
     "answer": "Open the exercise in your plan to see its steps and safety points. Move slowly and smoothly, "
               "and record yourself so the app can check your posture and give you tips."},
    {"key": "pain_or_discomfort", "title": "Pain or discomfort",
     "keywords": ["pain", "hurt", "hurts", "sore", "soreness", "ache", "aching", "discomfort", "stiff"],
     "examples": ["my knee hurts when I exercise", "is it normal to feel sore after exercising",
                  "what should I do if I feel pain", "my muscles ache the next day"],
     "answer": "Mild muscle tiredness or soreness for a day or two is normal when you start. Sharp pain, or pain "
               "that gets worse during an exercise, is not: stop that exercise and rest. If the pain lasts more "
               "than a few days, contact your doctor or physiotherapist before continuing."},
    {"key": "how_often", "title": "How often to exercise",
     "keywords": ["how often", "how many times", "every day", "daily", "per week", "frequency", "schedule",
                  "how long", "rest day"],
     "examples": ["how often should I exercise", "can I do this every day", "how many times a week",
                  "how long should each session be"],
     "answer": "Follow the number of sessions per week shown in your plan, with a rest day in between when you "
               "can. Your reminders are set to match this schedule. Quality matters more than doing extra sessions."},
    {"key": "missed_session", "title": "Missed a session",
     "keywords": ["missed", "skip", "skipped", "forgot", "did not exercise", "didn't exercise", "behind"],
     "examples": ["I missed my session yesterday", "what if I skip a day", "I forgot to exercise"],
     "answer": "That is fine. Do your next session as usual; do not do two sessions in one day to catch up. "
               "If you miss several days, start again gently with fewer repetitions."},
    {"key": "safety", "title": "Exercising safely",
     "keywords": ["safe", "safety", "dizzy", "fall", "falling", "balance", "careful", "breath", "breathing"],
     "examples": ["is it safe for me to exercise", "how do I avoid falling", "what if I feel dizzy",
                  "should I hold my breath"],
     "answer": "Exercise near a stable chair or counter, on a non-slip floor, and breathe normally; do not hold "
               "your breath. Stop if you feel dizzy, short of breath or unwell. Your plan already respects the "
               "safety limits from your health profile."},
    {"key": "equipment", "title": "What you need",
     "keywords": ["equipment", "need", "chair", "mat", "weights", "dumbbell", "step", "shoes", "clothes"],
     "examples": ["what equipment do I need", "do I need weights", "what kind of chair should I use",
                  "what should I wear"],
     "answer": "Most exercises only need a firm chair without wheels, pushed against a wall. Floor exercises need "
               "a mat, and step-ups need a low step with a rail. Wear comfortable clothes and non-slip shoes. "
               "A light water bottle can be used as a weight if your plan says so."},
]

GOAL_TEXT = {
    "MOBILITY": "move your joints more freely",
    "STRENGTH": "build the strength of your muscles",
    "BALANCE": "improve your balance and steadiness",
    "PAIN_RELIEF": "ease discomfort and support your back",
    "ENDURANCE": "build your stamina for daily activities",
}

RED_FLAGS = ["chest pain", "chest tightness", "can't breathe", "cannot breathe", "cant breathe", "can't breath",
             "cant breath", "cannot breath", "hard to breathe", "difficulty breathing", "breathless",
             "short of breath",
             "faint", "fainted", "passed out", "dizzy", "severe pain", "severe swelling", "swollen",
             "numb", "numbness", "heart racing", "fell down", "i fell"]

RED_FLAG_ANSWER = ("Stop the exercise now. If you have chest pain, trouble breathing, fainting or severe "
                   "swelling, call 999 or go to the nearest emergency department. For other new pain or "
                   "numbness, rest and contact your doctor or physiotherapist before continuing.")


def duration(sec: int) -> str:
    return f"{sec} seconds" if sec < 60 else f"{sec // 60} minute" + ("s" if sec >= 120 else "") + \
        (f" {sec % 60} seconds" if sec % 60 else "")


def plan_categories(p: dict) -> list[dict]:
    items = sorted(p["plan_exercise"], key=lambda e: e["sequence_order"])
    lines = "; ".join(f"{i}. {e['exercise']['exercise_name']}, {e['prescribed_repetitions']} repetitions "
                      f"(about {duration(e['prescribed_duration_sec'])})" for i, e in enumerate(items, 1))
    goal = GOAL_TEXT.get(p.get("goal") or "", "support your recovery")
    return [
        {"key": "plan_exercises", "title": "What is in my plan",
         "keywords": ["what exercises", "which exercises", "my plan", "in my plan", "exercise list", "order",
                      "repetitions", "how many reps"],
         "examples": ["what exercises are in my plan", "which exercise do I do first", "how many repetitions",
                      "what is in this plan"],
         "answer": f"{p['plan_name']} has {len(items)} exercises, done in this order: {lines}. "
                   f"Do it {p['frequency_per_week']} times a week."},
        {"key": "plan_progress", "title": "Progress and results",
         "keywords": ["results", "progress", "improve", "improvement", "how long until", "when will", "better",
                      "working", "next plan", "harder"],
         "examples": ["when will I see results", "how do I know I am improving", "is the plan working",
                      "what happens when I finish this plan"],
         "answer": f"This plan aims to help you {goal}. Most people notice a difference after two to four weeks "
                   f"of regular sessions. Your progress bar moves forward each time you complete an exercise "
                   f"with good posture; when the plan is complete, ask for a new recommendation to move on."},
    ]


def build() -> dict:
    cat = json.loads(CATALOGUE.read_text(encoding="utf-8"))
    rules = {
        "general": GENERAL,
        "plans": {p["plan_id"]: {"plan_name": p["plan_name"], "categories": plan_categories(p)} for p in cat["plans"]},
        "red_flags": RED_FLAGS,
        "red_flag_answer": RED_FLAG_ANSWER,
    }
    OUT.write_text(json.dumps(rules, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return rules


if __name__ == "__main__":
    r = build()
    print(f"{len(r['general'])} general categories, {len(r['plans'])} plans -> {OUT}")
