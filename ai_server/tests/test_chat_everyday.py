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


def test_random_typing_misses_of_fresh_seeds():
    # 3.86: the commonest misses of random typing seeds 2 and 3
    for text, want in [("sorry ok", "acknowledge"), ("sorry?", "pardon"), ("SKIAT YA...", "pain_or_discomfort"),
                       ("ok my son can hlp", "family_help"), ("HW HIGH HEELS GO HUH", "exercise:heel_raise"),
                       ("Hve fever tdy exercise!!", "tired"), ("When arms strogner!", "plan_progress")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text


def test_everyday_local_words_for_aches():
    # 3.87: Malay, Malaysian Chinese and Tamil words people mix in
    for text, want in [("lenguh badan", ("pain_mild", "pain_or_discomfort")), ("sengal sengal", ("pain_or_discomfort",)),
                       ("tak larat dah", ("tired",)), ("urat tegang", ("stiffness",)), ("my leg very suan",
                       ("pain_or_discomfort", "pain_mild")), ("so sien today", ("motivation",)),
                       ("my knee romba vali", ("pain_or_discomfort",)), ("mutti vali after exercise",
                       ("pain_or_discomfort", "pain_mild")), ("lau sai today", ("tired",)),
                       ("i very kan cheong about falling", ("fear_of_falling",))]:
        assert engine.reply(PLAN, None, text)["category"] in want, text


def test_stretched_words_and_sound_alikes():
    # 3.90: "youuu" is you, "kneeeee" knee, "sadd" sad; voice: "a different plant", "my need goes", "he'll races"
    for text, want in [("how are youuu lah??", "how_are_you"), ("nice to meet youuuu lah", "greeting"),
                       ("I'M SADD AH", "low_mood"), ("i want to change to a different plant", "plan_and_reminders"),
                       ("how to straighten my need in the exercise", "exercise:knee_extension"),
                       ("okay how many times should i do he'll races", "exercise:heel_raise")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text


def test_everyday_wellness_questions():
    # 3.91
    for text, want in [("i can't sleep at night", "sleep"), ("i have insomnia", "sleep"),
                       ("can exercise help my mood", "low_mood"), ("how to lose belly fat", "calories"),
                       ("how much protein should i eat", "diet"), ("can i do more than my plan", "difficulty"),
                       ("i didn't sleep well last night", "tired"), ("is this app free", "app_facts"),
                       # 3.95
                       ("how can i get help for my mental health", "low_mood"),
                       ("i need tips on how to overcome insomnia", "sleep")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text


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
    # 3.93: the newer answers' words
    for text, word in [("what is spo2", "SpO2"), ("what does api mean", "Air Pollutant Index"), ("what is dvt", "DVT"),
                       ("what is sahur", "Sahur"), ("what does hypo mean", "low blood sugar"), ("what is doms", "DOMS"),
                       ("what is a stitch", "two things"), ("what is cpap", "CPAP")]:
        x = engine.reply(PLAN, None, text)
        assert x["category"] == "word_meaning" and word in x["answer"], text


def test_everyday_questions_probed_by_hand():
    # 3.98: questions a patient asks that were not recognised or got another topic
    for text, want in [("should i use ice or heat", "ice_heat"), ("can i put an ice pack on my knee", "ice_heat"),
                       ("can this app replace my physiotherapist", "physio_role"),
                       ("can i talk to a real physiotherapist", "physio_role"),
                       ("my feet are always cold", "cold_hands_feet"),
                       ("can i use knee brace during exercise", "brace_support"),
                       ("should i wear knee guard", "brace_support"),
                       ("can old people exercise", "safety"), ("is walking enough", "other_activity"),
                       ("i wake up many times at night", "sleep"), ("i keep tripping", "fear_of_falling"),
                       ("i miss my wife", "low_mood"), ("it says i did 0 reps", "posture_result"),
                       ("is this app approved by doctors", "app_facts"),
                       ("my hands are numb every night", "pins_needles"),
                       ("macam mana nak tukar bahasa", "language"), ("siapa buat apps ni", "bot_identity"),
                       ("kenapa markah saya rendah", "posture_result"), ("kamera tak nampak saya", "recording_help"),
                       ("senaman ni sesuai untuk saya ke", "safety"),
                       ("boleh ke orang tua buat senaman ni", "safety")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text
    # unchanged: a missed session, a cold, sudden numbness
    assert engine.reply(PLAN, None, "i missed my session yesterday")["category"] == "missed_session"
    assert engine.reply(PLAN, None, "should i exercise when i have a cold")["category"] == "tired"
    assert engine.reply(PLAN, None, "my arm suddenly numb every night")["category"] == "red_flag"


def test_a_call_for_help_to_get_up_and_a_carer_helping_someone_move():
    # 3.98: "help me get up" was "what can you do"; how a carer helps someone stand up or walk was not answered
    for text in ["help me get up", "help i cannot get up", "tolong bangunkan saya"]:
        assert engine.reply(PLAN, None, text)["category"] == "red_flag", text
    for text in ["how to help my mother stand up", "how do i help my mother get out of a chair",
                 "how to help my father walk"]:
        assert engine.reply(PLAN, None, text)["category"] == "helping_someone_move", text
    assert engine.reply(PLAN, None, "how to help my mother exercise")["category"] == "family_help"


def test_surgery_sciatica_plan_choice_and_pace():
    # 3.98 (third probe) and the replay of the random typing test
    for text, want in [("i had knee surgery 6 weeks ago", "surgery"), ("i have sciatica", "condition_advice"),
                       ("why did the app give me this plan", "plan_reasons"),
                       ("how does the app choose my plan", "plan_reasons"),
                       ("can i pause my plan", "plan_and_reminders"), ("how slow should i go", "how_to"),
                       ("how fast should i do each rep", "how_to"), ("doktor say no senaman", "doctor_said"),
                       ("how to raise my arms to the side properly leh??", "exercise:shoulder_abduction"),
                       ("excuse me i dontwant to live aymore?", "crisis"),
                       ("ok suddenly heartraccing pls...", "red_flag"),
                       ("sorry she fell. laats year, now fine??", "fear_of_falling")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text


def test_exercises_for_a_body_part_and_names_near_other_words():
    # 3.98 (exercise probe): "exercise for shoulder" was the hot-weather answer; the plan's own area lists the plan
    # (PLAN is Early Knee Recovery); "how high to lift my knees when marching" was "toe raise" (the heel raise)
    for text, want in [("exercise for shoulder", "body_map"), ("i want a plan for my shoulder", "body_map"),
                       ("what exercise for knee", "plan_exercises"), ("exercise for my knee", "plan_exercises"),
                       ("can i use armrest", "equipment"),
                       ("how high to lift my knees when marching", "exercise:seated_marching"),
                       ("how to do wall pus-up", "exercise:wall_push_up"),
                       ("how often should i exercise after my knee surgery", "surgery")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text


def test_wanting_to_end_it_and_wanting_to_exercise():
    # 3.99: "want end", "i want to end" alone and "i wanna end it" are thoughts of ending one's life; "i want to
    # exercise" is how to start (was the body map), "i don't want to exercise today" motivation (the plan's list)
    for text in ["want end", "Wabt end huh...", "i want to end", "i wanna end it", "wanna kill myself"]:
        assert engine.reply(PLAN, None, text)["category"] == "crisis", text
    for text, want in [("i want to end the session", "session_expired"), ("want to end my plan", "plan_and_reminders"),
                       ("i want to exercise", "getting_started"), ("i wanna exercise", "getting_started"),
                       ("i want to exercise my hand", "body_map"), ("i don't want to exercise today", "motivation")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text


def test_feelings_reminders_and_account_in_everyday_malay():
    # 3.99 (sixth probe)
    for text, want in [("saya rasa sunyi", "low_mood"), ("saya takut tak boleh jalan lagi", "low_mood"),
                       ("saya dah buat semua senaman", "session_done"), ("i am proud of myself", "session_done"),
                       ("peringatan tak keluar", "reminder_late_or_off"), ("apps ni susah guna", "app_help"),
                       ("the app is hard to use", "app_help"), ("saya tak faham", "pardon"),
                       ("selamat malam", "goodbye"), ("selamat pagi", "greeting"), ("i got a new phone", "account_help")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text
    # "selamat ke?" still asks whether the last answer's activity is safe
    assert engine.reply(PLAN, None, "selamat ke", previous_category="other_activity")["category"] == "other_activity"


def test_the_posture_check_and_recording():
    # 4.00 (seventh probe)
    for text, want in [("should i wear tight clothes for recording", "video_quality"),
                       ("there are other people in the room", "video_quality"),
                       ("my cat walked in front of the camera", "video_quality"),
                       ("the picture is blurry", "video_quality"), ("can someone else hold the phone", "recording_help"),
                       ("the analysis takes very long", "app_problem"), ("my phone gets hot", "app_problem"),
                       ("my score changed when i redid it", "posture_result"),
                       ("the app counted 8 but i did 10", "posture_result"), ("my knee is warm", "pain_swelling")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text
    for text in ["my vision is blurry", "everything is blurry"]:
        assert engine.reply(PLAN, None, text)["category"] == "red_flag", text


def test_short_forms_and_manglish_of_the_random_test():
    # 4.01: the random typing test's commonest misses
    for text, want in [("can family hep!", "family_help"), ("hi safe or not?", "safety"),
                       ("What today lah", "plan_exercises"), ("hello what happens after finish plan", "plan_progress"),
                       ("why olby 20 min ?", "safety_limits"), ("walk safe or not", "other_activity"),
                       ("is it ok to walk", "other_activity")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text
    assert engine.reply(PLAN, None, "my hep hurts")["category"] != "family_help"


def test_long_polite_messages():
    # 4.03 (eighth probe)
    for text, want in [("Hello, my name is Ahmad, I am 58 years old, I had a stroke last year, can I use this app?",
                        "condition_advice"), ("i have diabetes can i use this app", "condition_advice"),
                       ("I feel much better now, can I stop the exercises?", "plan_progress"),
                       ("Anak saya yang pasang aplikasi ini, saya tak tahu macam mana nak guna.", "app_help"),
                       ("how to use app, i have diabetes", "app_help")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text


def test_every_exercise_by_its_malay_name():
    # 4.04 (ninth probe): 10 of 17 were not recognised
    for text, key in [("cara buat tekan dinding", "wall_push_up"), ("cara angkat tangan ke sisi", "shoulder_abduction"),
                      ("cara angkat kaki ke sisi", "hip_abduction"), ("cara bengkokkan siku", "elbow_flexion"),
                      ("cara buat separuh cangkung", "mini_squat"), ("cara buat jambatan", "glute_bridge"),
                      ("cara berdiri tumit ke jari", "tandem_stance"), ("cara buat anjing burung", "bird_dog"),
                      ("cara berkawad di tempat", "march_in_place"), ("cara kawad sambil duduk", "seated_marching"),
                      ("cara angkat pergelangan tangan", "wrist_extension")]:
        assert engine.reply(PLAN, None, text)["category"] == "exercise:" + key, text


def test_posture_tips_described_in_malay():
    # 4.05 (tenth probe): the tips as a patient describes them in Malay, with "saya" after the noun
    for text, want in [("dia kata lutut saya tak lurus", "mistake:knee_not_straight"),
                       ("belakang saya bengkok masa senaman", "mistake:slouching"),
                       ("dia kata saya condong ke depan", "mistake:leaning_forward"),
                       ("saya guna tangan masa bangun", "mistake:hands_used"),
                       ("tangan saya tak sama tinggi", "mistake:uneven_arms"),
                       ("punggung saya jatuh masa jambatan", "mistake:hips_sag"),
                       ("kenapa dia kata salah senaman", "wrong_exercise"),
                       ("saya terlupa senaman semalam", "missed_session")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text
    # a fall stays a fall
    for text in ["saya jatuh semalam", "punggung saya sakit sebab jatuh", "ayah saya jatuh"]:
        assert engine.reply(PLAN, None, text)["category"] == "red_flag", text


def test_the_app_and_account_in_everyday_malay():
    # 4.06 (eleventh probe)
    for text, want in [("saya tak boleh log masuk", "forgot_password"), ("macam mana nak daftar akaun", "account_help"),
                       ("macam mana nak tengok keputusan lama", "history_help"),
                       ("macam mana nak tukar berat badan", "profile_help"),
                       ("apa maksud risiko sederhana", "risk_level"), ("macam mana nak set peringatan", "reminders_help"),
                       ("aplikasi tergantung", "app_problem"), ("skrin hitam", "app_problem"),
                       ("saya bosan", "motivation"), ("saya risau", "low_mood")]:
        assert engine.reply(PLAN, None, text)["category"] == want, text
