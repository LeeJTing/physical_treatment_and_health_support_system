"""Round 3 of the continuous chatbot improvement (7 Oct, rules 3.7 -> 3.8): odd and random input.

Emojis, all caps, heavy typos, repeated letters, other scripts, links, code-like text, follow-ups
with no context, and very short replies. Unknown or meaningless input must get the exact
FR500_22 "not recognised" answer (None), never a confident wrong topic. Written before looking
at the rules; the first run is the honest score.
"""
from chat_round1_set import KNEE

ROUND3 = [
    (KNEE, "😀😀😀", None),
    (KNEE, "👍", "acknowledge"),
    (KNEE, "🙏 thank you", "thanks"),
    (KNEE, "MY KNEE HURTS SO MUCH", "pain_or_discomfort"),
    (KNEE, "HOW DO I START", "getting_started"),
    (KNEE, "hiiiii", "greeting"),
    (KNEE, "helloooo", "greeting"),
    (KNEE, "thx thx", "thanks"),
    (KNEE, "okayyy", "acknowledge"),
    (KNEE, "my kneee hurtss", "pain_or_discomfort"),
    (KNEE, "how to recrod vidoe", "recording_help"),
    (KNEE, "remindr not working", "reminders_help"),
    (KNEE, "我的膝盖痛", None),
    (KNEE, "https://example.com", None),
    (KNEE, "select * from users", None),
    (KNEE, "<script>alert(1)</script>", None),
    (KNEE, "why?", None),
    (KNEE, "and then?", None),
    (KNEE, "what about the second one", None),
    (KNEE, "yes", None),
    (KNEE, "no", None),
    (KNEE, "asdf jkl qwerty", None),
    (KNEE, "........", None),
    (KNEE, "a", None),
    (KNEE, "help me", "bot_identity"),
    (KNEE, "i need help with my password", "forgot_password"),
    (KNEE, "i need help, i fell down", "red_flag"),
    (KNEE, "can you call a doctor for me", ("diagnosis", None)),
    (KNEE, "are you chatgpt", "bot_identity"),
    (KNEE, "i love this app", ("thanks", None)),   # 3.8: a compliment gets the thank-you reply
]
