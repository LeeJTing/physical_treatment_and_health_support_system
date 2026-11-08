"""Symptoms by their kind (tests/chat_symptoms_set.py, chat-rules-3.78) as a guard: 500 messages of seed 3
(not used while building 3.78) keep today's level; a stroke sign told as tingling stays urgent. Before 3.78
the set scored 11.80% (a cramp was the general pain answer, "a stitch in my side" the surgical-wound advice)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_symptoms_set import build  # noqa: E402

from app.chat import engine  # noqa: E402

PLAN = "88c1e725-4b64-5689-a70d-47d37b2fcd7e"


def _got(text):
    x = engine.reply(PLAN, None, text)
    return x["category"] if x["is_matched"] else None


def test_symptoms_keep_their_level():
    cases = build(3, 500)
    bad = [(c["text"], c["want"], g) for c in cases if str(g := _got(c["text"])) not in c["want"]]
    assert len(bad) / len(cases) <= 0.03, bad[:20]


def test_tingling_that_is_a_stroke_sign_is_urgent():
    for text in ["sudden tingling in my face and arm", "my face is tingling",
                 "suddenly i feel pins and needles in my left arm"]:
        assert _got(text) == "red_flag", text
    for text in ["tingling in my fingers", "pins and needles in my feet after sitting"]:
        assert _got(text) == "pins_needles", text


def test_malay_chest_tightness_is_urgent():
    # 3.82: "senak dada" (chest tightness), "senak nafas" (a slip of "sesak nafas") are warning signs.
    for text in ["senak dada", "dada senak", "senak nafas", "rasa senak nafas lepas senam"]:
        assert _got(text) == "red_flag", text
    assert _got("senak bila jalan") == "stitch"
    # 3.83: Malay texting around warning signs ("lah" stuck on, "lha"/"lsh" for "lah", "dr" for diri)
    for text, want in [("sya rasa nak bunuh drlah", "crisis"), ("saya nk matlah", "crisis"),
                       ("janutng ljlah...", "red_flag"), ("nak ptmah", "red_flag"), ("pitamlha!!", "red_flag"),
                       ("skt ddlsh?", "red_flag"), ("mk sneget", "red_flag"), ("suddenly xbokeh bernafas", "red_flag")]:
        assert _got(text) == want, text
    # 3.84: two slips beside a chest word; "lah" on a slipped Malay word
    for text, want in [("erm chest very tijt la ah", "red_flag"), ("i feel chest piian??", "red_flag"),
                       ("ok darah banyak kelluarlah??", "red_flag"), ("hmm want give up life", "crisis")]:
        assert _got(text) == want, text
    # 3.85: two slips in one word of a warning-sign or crisis phrase whose other words are there as typed
    for text, want in [("Bledig a lot lah??", "red_flag"), ("mother has herrat pounding", "red_flag"),
                       ("penat hduup", "crisis"), ("sucde thoughts", "crisis"), ("suddenly soet of breath", "red_flag"),
                       ("felll and cannot get up", "red_flag"), ("peeat hidup!", "crisis"),
                       ("She fell last month, but it happened again today ah??", "red_flag")]:
        assert _got(text) == want, text
    # 3.90: a doubled last letter is not read away when a warning-sign word is as near ("feell" is fell)
    for text in ["help feell and cannotget up??", "feell today!!", "She feell agaun?", "i feell in the paast hour"]:
        assert _got(text) == "red_flag", text
    for text in ["my chest stretch feels good", "head tilt", "sekolah anak saya"]:
        assert _got(text) not in ("crisis", "red_flag"), text
    # 3.92: particles "alh", "lh", "kah"; a texted short form or doubled letter after them; a pair mended late
    for text, want in [("sya rs drh bnyk klrlsh!", "red_flag"), ("ayh sya jthhlah...", "red_flag"),
                       ("suddenly mk swngetlah...", "red_flag"), ("tkt jthalh", "fear_of_falling"),
                       ("trm khslah?", "thanks"), ("saya lp kata llnlsh??", "forgot_password"),
                       ("mcm mn nak tkr kt llnkah?", "change_password")]:
        assert _got(text) == want, text
    for text in ["langkah demi langkah", "sekolah", "rumah saya"]:
        assert _got(text) not in ("crisis", "red_flag"), text
    for text in ["nak mat yoga", "dr said rest", "rumah saya jauh"]:
        assert _got(text) not in ("crisis", "red_flag"), text
    # sudden weakness told in Malay word order ("my leg weak suddenly")
    for text in ["kaki saya lemah tiba tiba", "kaki lemah tiba-tiba", "tangan lemah tiba tiba"]:
        assert _got(text) == "red_flag", text


def test_the_same_words_meaning_something_else():
    assert _got("my stitches are oozing") != "stitch"                 # a surgical wound
    assert _got("the screen gets stuck") == "app_problem"
    assert _got("i fell asleep during the exercise") != "pins_needles"
