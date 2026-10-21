"""Everyday random inputs (tests/chat_everyday_set.py, chat-rules-3.67) as a guard: 500 messages of seed 3
(not used while building 3.67) keep today's level, and none of chit-chat, feelings, a body part, an app
feature, emoji, food or yes / no is answered as an emergency. Before 3.67 the set scored 58.75%."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_everyday_set import build  # noqa: E402

from app.chat import engine  # noqa: E402

PLAN = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"
URGENT = {"red_flag", "crisis", "overdose", "poisoning"}
CALM = {"chit_chat", "body_part", "app_feature", "emoji", "food", "yes_no", "time_alone", "activity"}
RESULTS = [(c, (lambda x: x["category"] if x["is_matched"] else None)(
    engine.reply(PLAN, None, c["text"], previous_category=c["previous_category"]))) for c in build(3, 500)]


def test_everyday_inputs_keep_their_level():
    good = sum(str(g) in c["want"] for c, g in RESULTS)
    assert good / len(RESULTS) >= 0.95, [(c["text"], c["want"], g) for c, g in RESULTS if str(g) not in c["want"]][:20]


def test_everyday_inputs_are_not_emergencies():
    assert not [(c["text"], g) for c, g in RESULTS if c["kind"] in CALM and g in URGENT]


def test_things_the_chatbot_cannot_do_say_so():
    for text in ["call my doctor", "book an appointment", "play music", "whatsapp my daughter"]:
        assert engine.reply(PLAN, None, text)["category"] == "cannot_do", text
    assert engine.reply(PLAN, None, "call ambulance for me")["category"] == "red_flag"


def test_a_body_part_alone_is_asked_about():
    x = engine.reply(PLAN, None, "knee")
    assert x["category"] == "clarify" and "your knee" in x["answer"]


def test_app_questions_in_other_topics_words():
    # 3.79: "tablet" is also a pill, "support" also something to hold on to.
    for text, want in [("can i use it on tablet", "app_facts"), ("how to contact support", "app_facts"),
                       ("share my progress with my doctor", "history_help"), ("i take 2 tablets a day", "medication"),
                       ("hold on to a support while standing", "safety")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text


def test_exercises_described_in_everyday_words():
    # 3.80: the exercise meant, from how people describe it.
    for text, want in [("walking on the spot", "march_in_place"), ("the one where i kneel on all fours", "bird_dog"),
                       ("push against the wall", "wall_push_up"), ("small knee bend", "mini_squat"),
                       ("lift knees while sitting", "seated_marching"), ("straighten leg while sitting",
                       "knee_extension"), ("up on my toes exercise", "heel_raise"), ("angkat tumit", "heel_raise"),
                       ("the sitting down standing up one", "sit_to_stand"), ("step onto a stair", "step_up"),
                       ("which muscle does the bridge work", "glute_bridge")]:
        assert engine.reply(PLAN, None, text)["category"] == f"exercise:{want}", text
    for text in ["my hands and knees hurt", "pain on my toes"]:
        assert engine.reply(PLAN, None, text)["category"] in ("pain_or_discomfort", "pain_mild"), text


def test_what_a_word_means():
    # 3.72: "what does flexion mean" was the leaning mistake, "range of motion means?" not recognised.
    for text, word in [("what does flexion mean", "Flexion"), ("range of motion means?", "Range of motion"),
                       ("apa maksud bmi", "BMI"), ("reps meaning", "repetition"), ("what is abduction", "Abduction")]:
        x = engine.reply(PLAN, None, text)
        assert x["category"] == "word_meaning" and word in x["answer"], text
    for text, want in [("what is tandem stance", "exercise:tandem_stance"), ("what is my risk level", "risk_level")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text
    # 3.81: in Malay too; "senam" (exercise) is not "senak" (a stitch)
    for text, want in [("apa maksud fleksi", "word_meaning"), ("apa itu fisioterapi", "word_meaning"),
                       ("ayah saya ada gaut boleh senam?", "condition_advice"), ("senak bila jalan", "stitch")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text
    assert engine.reply(PLAN, None, "boleh senam?")["category"] != "stitch"
