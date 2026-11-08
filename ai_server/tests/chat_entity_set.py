"""Every exercise, health condition and posture mistake, asked about in many ways (Elwin, 15 Oct: "continue
making it more complete"). Generated, not hand-picked: names (and their other names, typos and Malay
words) x question templates. evaluate_chat_entities.py runs them all; tests/test_chat_entities.py a sample.
"""

# Exercise questions: {x} is the exercise's name. The answer must be that exercise; "also" lists other
# answers that fit the question as well.
EXERCISE_TEMPLATES = [
    ("how to do {x}", ()), ("how do i do the {x}", ()), ("{x}", ()), ("{x}?", ()), ("{x} steps", ()),
    ("explain {x}", ()), ("show me {x}", ()), ("teach me the {x}", ()), ("what is {x}", ()),
    ("{x} how many reps", ()), ("how many {x} should i do", ()), ("how long for {x}", ()),
    ("is {x} safe for me", ("safety",)), ("can you explain the {x}", ()), ("{x} instructions", ()),
    ("cara buat {x}", ()), ("{x} macam mana", ()), ("how to {x} correctly", ()), ("{x} pls", ()),
    ("where to put my phone for {x}", ("recording_help",)), ("camera for {x}", ("recording_help",)),
    ("{x} is too hard", ("difficulty",)), ("i cant do {x}", ("difficulty",)),
    ("{x} too easy", ("difficulty",)),
]

# Pain during an exercise: the pain answer comes first, whatever the exercise.
PAIN_TEMPLATES = [
    "my knee hurts when i do {x}", "pain during {x}", "{x} hurts my back", "sakit bila buat {x}",
]

# Condition questions: {c} is a way to name the condition. The answer must be condition advice that
# includes that condition's own detail.
CONDITION_TEMPLATES = [
    "can i exercise with {c}", "i have {c}", "i have {c} is it safe to exercise", "{c} exercise",
    "is this plan ok for {c}", "exercise for {c}", "i got {c} can i do the exercises", "saya ada {c}",
    "what exercise is good for {c}", "{c} can exercise or not",
]

# Ways users name each condition (from engine.CONDITION_WORDS, plus everyday and Malay words).
CONDITION_NAMES = {
    "HYPERTENSION": ["high blood pressure", "hypertension", "darah tinggi", "high bp"],
    "DIABETES": ["diabetes", "kencing manis", "high blood sugar", "type 2 diabetes"],
    "HEART_DISEASE": ["heart disease", "a heart problem", "a pacemaker", "sakit jantung"],
    "STROKE": ["stroke", "a stroke before", "angin ahmar"],
    "ARTHRITIS": ["arthritis", "osteoarthritis", "sakit sendi"],
    "OSTEOPOROSIS": ["osteoporosis", "weak bones", "tulang rapuh"],
    "ASTHMA": ["asthma", "penyakit lelah", "saya ada lelah"],
    "PREGNANCY": ["pregnancy", "i am pregnant", "hamil", "just gave birth"],
    "JOINT_REPLACEMENT": ["knee replacement", "hip replacement", "a new knee"],
    "RHEUMATOID_ARTHRITIS": ["rheumatoid arthritis", "rheumatoid"],
    "COPD": ["copd", "emphysema", "chronic lung disease"],
    "CANCER": ["cancer", "chemo", "kanser"],
    "KIDNEY_DISEASE": ["kidney disease", "dialysis", "sakit buah pinggang"],
    "PARKINSONS": ["parkinsons", "parkinson's disease"],
    "MULTIPLE_SCLEROSIS": ["multiple sclerosis", "ms"],
    "FOOT_ULCER": ["a foot ulcer", "diabetic foot", "a wound on my foot"],
}

# Posture mistake questions: {m} is the mistake's name as the result screen shows it.
MISTAKE_TEMPLATES = [
    "what does {m} mean", "it says {m}", "how to fix {m}", "{m}?", "my result said {m}", "why {m}",
]


def typo(name: str) -> str:
    """The same name with one letter dropped from its longest word (a common slip)."""
    words = name.split()
    i = max(range(len(words)), key=lambda k: len(words[k]))
    w = words[i]
    if len(w) < 5:
        return name
    words[i] = w[:len(w) // 2] + w[len(w) // 2 + 1:]
    return " ".join(words)
