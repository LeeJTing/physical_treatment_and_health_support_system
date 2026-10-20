"""Short follow-ups that point back at the previous answer (Elwin, 14 Oct: "handle single or double words
like 'how to' and link back to the previous response; make thousands of combinations, then fix them").

The app sends the previous answer's category with each question (previous_category). A message made
only of follow-up words ("how to", "why", "more", "how many", "is it safe", "kenapa", "macam mana")
continues that topic; a message with a topic of its own ("knee pain", "how do i log in") is answered
for itself whatever came before, and safety always comes first.

Generated, not hand-picked: every previous topic x every follow-up below (several thousand pairs), and
every previous topic x every control question.
"""

# Follow-ups a user types after an answer, in English, Malaysian English and Malay.
FOLLOW_UPS = [
    "how to", "how", "how?", "how to do", "how to do it", "how do i do it", "how do i", "how ah", "steps",
    "the steps", "show me", "show me how", "cara", "caranya", "macam mana", "camne", "macam mana nak buat",
    "why", "why?", "why ah", "why like that", "how come", "kenapa", "kenapa ya", "apasal",
    "more", "tell me more", "more info", "more details", "details", "explain", "explain more",
    "can explain", "elaborate", "what do you mean", "what does that mean", "meaning", "maksud",
    "apa maksud", "huh", "huh?", "i dont understand", "tak faham", "say again", "again", "ulang",
    "how many", "how many times", "how long", "how often", "berapa", "berapa kali", "berapa lama",
    "is it safe", "safe?", "selamat ke", "then?", "and then", "what next", "lepas tu", "after that",
    "where", "where is it", "kat mana", "really?", "betul ke", "for example", "example", "so?",
    "what about it", "tell me", "pls explain", "can you explain that",
]

# Questions with a topic of their own: the previous answer must not change where they go.
CONTROLS = [
    ("knee pain", "pain_or_discomfort"),
    ("my knee hurts when i bend", "pain_or_discomfort"),
    ("chest pain", "red_flag"),
    ("i feel dizzy and my chest hurts", "red_flag"),
    ("how do i log in", "account_help"),
    ("forgot password", "forgot_password"),
    ("why my score so low", "posture_result"),
    ("how to record my video", "recording_help"),
    ("is my data safe", "privacy_data"),
    ("delete my account", "delete_account"),
    ("thanks", "thanks"),
    ("ok", "acknowledge"),
    ("bye", "goodbye"),
    ("hello", "greeting"),
    ("i missed my session yesterday", "missed_session"),
    ("can i exercise after eating", "best_time"),
    ("why am i high risk", "risk_level"),
    ("what is my safety limit", "safety_limits"),
]

# Previous answers a follow-up does not continue: small talk, and nothing recognised.
NO_CONTEXT = {None, "greeting", "thanks", "acknowledge", "goodbye", "language", "bot_identity", "pardon"}


def variants(q: str) -> list[str]:
    """The ways a user types the same follow-up: capitals, punctuation, a word before or after, short
    forms and typos (one letter dropped or doubled)."""
    out = {q, q.upper(), q.capitalize(), q + "??", q + "!!", q + "...", q + " ?", "ok " + q, "so " + q,
           q + " pls", q + " ah", q + " lah", "and " + q, "hmm " + q}
    words = q.split()
    for i, w in enumerate(words):
        if len(w) >= 4 and w.isalpha():
            out.add(" ".join(words[:i] + [w[:-1]] + words[i + 1:]))          # last letter dropped
            out.add(" ".join(words[:i] + [w + w[-1]] + words[i + 1:]))       # last letter doubled
    short = {"why": "y", "how": "hw", "you": "u", "what": "wat", "explain": "explane", "more": "mor",
             "please": "pls", "details": "detail"}
    out.add(" ".join(short.get(w, w) for w in words))
    if q in ("how to", "how to do"):
        out.add(q.replace(" ", ""))                                          # "howto"
    return sorted(out)
