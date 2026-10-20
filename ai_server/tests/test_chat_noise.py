"""Random characters (tests/chat_noise_set.py, chat-rules-3.57) as a guard: a sample of messages with
nothing to answer and of known questions with random characters added must keep today's level, and
hostile input (code, odd Unicode, very long or emoji-only messages) must never fail, be slow or be read
as an emergency. The full evaluation, with the Big List of Naughty Strings and CLINC150, is
evaluate_chat_noise.py (docs/chat_noise_eval.json).
"""
import random
import time

from fastapi.testclient import TestClient

from app.chat import engine
from app.main import app
from app.routers.chat import visible_length
from chat_noise_set import add_noise, noise
from chat_round1_set import KNEE
from evaluate_chat_noise import FINE_FOR_NOISE, URGENT, seeds

client = TestClient(app)
DEV = {"Authorization": "Bearer dev-token"}


def _got(plan, text):
    x = engine.reply(plan, None, text)
    return x["category"] if x["is_matched"] else None


def test_random_characters_are_not_given_a_topic_or_an_emergency():
    rng = random.Random(7)
    got = [(t, _got(KNEE, t)) for t in (noise(rng)[1] for _ in range(300))]
    assert not [(t, g) for t, g in got if g in URGENT]
    fine = sum(g in FINE_FOR_NOISE for _, g in got)
    assert fine / len(got) >= 0.9, [(t[:40], g) for t, g in got if g not in FINE_FOR_NOISE][:20]


def test_questions_with_random_characters_keep_their_answer():
    rng, base = random.Random(7), seeds()
    cases = []
    for _ in range(300):
        plan, q, want = rng.choice(base)
        cases.append((plan, add_noise(q, rng)[1], want))
    good = [(t, _got(p, t), w) for p, t, w in cases]
    assert sum(g in w for _, g, w in good) / len(good) >= 0.97, [(t, g) for t, g, w in good if g not in w][:20]


HOSTILE = ["'; DROP TABLE users; --", "<script>alert(1)</script>", "${jndi:ldap://x}", "../../etc/passwd",
           "{{7*7}}", "https://example.com/a?b=c", "someone@example.com", "​​​", "﻿",
           "Ṱ̺̺̕o͞ ̷i̲̬͇̪͙n̝̗͕v̟̜̘̦͟o̶̙̰̠kè͚̮̺̪̹̱̤ ̖t̝͕̳̣̻̪͞h̼͓̲̦̳̘̲e͇̣̰̦̬͎ ̢̼̻̱̘h͚͎͙̜̣̲ͅi̦̲̣̰̤v̻͍e̺̭̳̪̰-m̢iͅn̖̺̞̲̯̰d̵̼̟͙̩̼̘̳ ̞̥̱̳̭r̛̗̘e͙p͠r̼̞̻̭̗e̺̠̣͟s̘͇̳͍̝͉e͉̥̯̞̲͚̬͜ǹ̬͎͎̟̖͇̤t͍̬̤͓̼̭͘ͅi̪̱n͠g̴͉ ͏͉ͅc̬̟h͡a̫̻̯͘o̫̟̖͍̙̝͉s̗̦̲.̨̹͈̣",
           "‮txet sdrawkcab", "👨‍👩‍👧‍👦" * 50, "🇲🇾" * 100, "1️⃣2️⃣3️⃣", "null", "undefined", "NaN", "-1e308",
           "0x0", "%s%s%s%n", "\\x00\\n\\r", "a" * 500, "!@#$%^&*()" * 50]


def test_hostile_input_never_fails_is_quick_and_is_not_an_emergency():
    for t in HOSTILE:
        start = time.time()
        g = _got(KNEE, t)
        assert time.time() - start < 3, t[:40]
        assert g not in URGENT, (t[:40], g)


def test_an_emoji_counts_as_one_character_as_in_the_app():
    assert visible_length("👍🏽") == 1 and visible_length("❤️") == 1 and visible_length("1️⃣") == 1
    assert visible_length("👨‍👩‍👧‍👦") == 1 and visible_length("🇲🇾") == 1 and visible_length("knee pain") == 9
    assert client.post("/chat", headers=DEV, json={"plan_id": KNEE, "text": "👨‍👩‍👧‍👦" * 400}).status_code == 200
    # 300 thumbs with a skin tone are 600 code points but 300 characters in the app's 500-character box.
    assert client.post("/chat", headers=DEV, json={"plan_id": KNEE, "text": "👍🏽" * 300}).status_code == 200
    assert client.post("/chat", headers=DEV, json={"plan_id": KNEE, "text": "❤️" * 500}).status_code == 200
    assert client.post("/chat", headers=DEV, json={"text": "x" * 501}).status_code == 422
    assert client.post("/chat", headers=DEV, json={"text": "́" * 6001}).status_code == 422


def test_the_longest_message_the_app_allows_is_answered_quickly():
    rng = random.Random(1)
    words = " ".join("".join(rng.choice("abcdefghijklmnopqrstuvwxyz") for _ in range(rng.randint(2, 9)))
                     for _ in range(100))[:500]
    start = time.time()
    r = client.post("/chat", headers=DEV, json={"plan_id": KNEE, "text": words})
    assert r.status_code == 200 and time.time() - start < 5


# 3.58: spacing typed by accident, junk around a real question, and questions that only look like code.
SPACING = [("sesak  nafas", {"red_flag"}), ("selamat  pagi", {"greeting"}), ("terima...kasih", {"thanks"}),
           ("saya...lupa...kata...laluan", {"forgot_password"}), ("I     f e e l     d i z z y", {"red_flag"}),
           ("n a k     t u k a r     p l a n", {"plan_and_reminders"}), ("h e l p", {"bot_identity"}),
           ("/$( my knee is not painful anymore, can I stop the plan?", {"plan_and_reminders"}),
           ("{{_ take me to profile", {"profile_help"}), ("video upload very slow(``_", {"recording_help"}),
           ("how do i select an exercise from my plan", {"plan_exercises"}),
           ("my knee hurts; touch it and it's warm", {"pain_or_discomfort", "pain_swelling"}),
           ("SELECT * FROM account", {None}), ("() { _; } >_[$($())] { touch /tmp/x.fail; }", {None}),
           (" ".join(["carpet", "banana", "river", "sunday", "cloud", "pencil", "dance", "laptop"] * 4), {None})]


def test_spacing_junk_and_code_like_questions():
    wrong = [(t, g) for t, want in SPACING if (g := _got(KNEE, t)) not in want]
    assert not wrong, wrong


# 3.61: other domains' questions that share a word with this chatbot (account, plan, score, table, pay,
# pressure), weighed as a whole; and everyday questions of this chatbot with the same words keep their topic.
# Known miss: "how can i raise my credit score" is still the posture score ("raise" is an exercise word).
OTHER_DOMAIN = ["can you help me move money between my accounts",
                "book a table for two at 7pm tonight", "what is the tire pressure for my car",
                "i want to switch to a new insurance plan", "when is my next pay day",
                "how long will it take to get a replacement credit card"]
OWN_DOMAIN = [("how many times a week", {"how_often"}), ("my score dropped from 90 to 60", {"posture_result"}),
              ("how do i change my password", {"change_password", "account_help"}),
              ("can i change my plan", {"plan_and_reminders", "change_plan"}),
              ("remind me only on monday wednesday friday", {"reminders_help", "plan_and_reminders"}),
              ("my blood pressure is 150 over 95, can i exercise", {"condition_advice", "red_flag", "safety"})]


def test_other_domains_weighed_as_a_whole_are_not_given_a_topic():
    wrong = [(t, g) for t in OTHER_DOMAIN if (g := _got(KNEE, t)) is not None]
    assert not wrong, wrong


def test_this_chatbots_questions_with_the_same_words_keep_their_topic():
    wrong = [(t, g) for t, want in OWN_DOMAIN if (g := _got(KNEE, t)) not in want]
    assert not wrong, wrong


def test_domain_weights_match_the_rules():
    """domain_weights.json is learnt from the rules too: rebuild it (build_domain_words.py) after changing
    them. Needs the CLINC and MASSIVE files (training/data/public, not in git)."""
    import json
    from pathlib import Path

    import pytest

    from app.chat import build_domain_words as b
    if not (b.DATA.exists() and all(p.exists() for p in b.MASSIVE)):
        pytest.skip("CLINC150 / MASSIVE not downloaded here")
    saved = json.loads(Path(engine.__file__).with_name("domain_weights.json").read_text(encoding="utf-8"))
    assert saved == b.domain_weights(), "run: python app/chat/build_domain_words.py"


# 3.62: a crisis or warning-sign phrase with one unknown word one slip away; falls told with an older fall
# or "sore"; and real words that must not be bent into one.
SAFETY_TYPOS = [("better if goe", "crisis"), ("i wsant to die!", "crisis"), ("peeat hidup!", "crisis"),
                ("no point annyore!!", "crisis"), ("Blajed out!!", "red_flag"), ("paaed out...", "red_flag"),
                ("pressuee in my chet during exercise?", "red_flag"), ("i have chest pina ?", "red_flag"),
                ("she has fallen, she fell last year too", "red_flag"), ("fell over, hip sore", "red_flag"),
                ("when is the best time of year for pruning", None), ("i want to dine out tonight", None),
                ("pina colada with my knee", None)]


def test_safety_phrases_typed_with_one_slip():
    wrong = [(t, g) for t, want in SAFETY_TYPOS if (g := _got(KNEE, t)) != want and not (want is None and g not in URGENT)]
    assert not wrong, wrong
