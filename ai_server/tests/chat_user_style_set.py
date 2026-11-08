"""Messages like the 21 Elwin reported with "Report this answer" (11 Oct, Supabase chat_report), generated
at random in the same patterns (21 Oct): a lone vague word ("what", "going", "I dont"), a question about
the chatbot itself ("what question can i ask"), an emergency number ("999"), thanks or "excuse me" typed
badly ("Yahnks", "exxuse me?"), random typing ("kdjsb"), a health word on its own ("allergy", "med"),
"report", a playful remark to the bot ("i m ur father"), and "Really?" after an answer. Each is typed with
random slips, capitals, punctuation and Malaysian particles. evaluate_chat_user_style.py runs it.

The 21 reports themselves are REPORTED below (question, what Elwin expected) and must all be answered as
he expected (tests/test_chat_user_style.py).
"""
import random
import string
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chat_random_set import typo  # noqa: E402

# (question, the topics Elwin's expected answer belongs to; None = "not recognised" with the message
# echoed back). From chat_report, 11 Oct.
REPORTED = [
    ("what", {"clarify"}), ("what question", {"bot_identity"}), ("999", {"red_flag"}),
    ("what question can", {"bot_identity"}), ("what question can i ask", {"bot_identity"}),
    ("allergy", {"allergy"}), ("I dont", {None}), ("Yahnks", {"thanks"}), ("yanks", {"thanks"}),
    ("exxuse me?", {"pardon"}), ("Excuse me?", {"pardon"}), ("ij", {None}), ("how", {"clarify"}),
    ("med", {"med_help"}), ("going", {None}), ("How to do Shoulder Abduction", {"exercise:shoulder_abduction"}),
    ("How to do Shoulder Flexion", {"exercise:shoulder_flexion"}), ("kdjsb", {None}), ("report", {"report_answer"}),
    ("i m ur father", {"bot_identity"}),
]

PATTERNS = {
    # A lone word or fragment with no topic: ask what they mean (echoing it), never guess a topic.
    "vague": ([("what", {"clarify"}), ("how", {"clarify"}), ("why", {"clarify"}), ("what?", {"clarify"}),
               ("going", {None}), ("i dont", {None, "clarify"}), ("i don't", {None, "clarify"}),
               ("so", {None, "clarify"}),
               ("but", {None, "clarify"}), ("is it", {None, "clarify"}), ("then", {None, "clarify"}),
               ("you", {None, "clarify"}), ("this one", {None, "clarify"}), ("can", {None, "clarify"}),
               ("wait", {None, "clarify"}), ("um what", {"clarify"}), ("and", {None, "clarify"})], 0.16),
    # About the chatbot itself.
    "about_bot": ([("what question", {"bot_identity"}), ("what question can i ask", {"bot_identity"}),
                   ("what questions can i ask", {"bot_identity"}), ("what can i ask you", {"bot_identity"}),
                   ("what should i ask", {"bot_identity"}), ("which question", {"bot_identity"}),
                   ("what can you answer", {"bot_identity"}), ("what to ask", {"bot_identity"}),
                   ("what question can", {"bot_identity"}), ("what do you know", {"bot_identity"})], 0.12),
    # An emergency number or call: the urgent answer.
    "emergency": ([("999", {"red_flag"}), ("call 999", {"red_flag"}), ("999!!", {"red_flag"}),
                   ("911", {"red_flag"}), ("112", {"red_flag"}), ("ambulance", {"red_flag"}),
                   ("call ambulance", {"red_flag"}), ("emergency", {"red_flag"}), ("dial 999", {"red_flag"})], 0.1),
    # Small talk typed badly.
    "small_talk": ([("thanks", {"thanks"}), ("thank you", {"thanks"}), ("thx", {"thanks"}), ("yahnks", {"thanks"}),
                    ("yanks", {"thanks"}), ("thnks", {"thanks"}), ("tahnks", {"thanks"}), ("thank yuo", {"thanks"}),
                    ("excuse me", {"pardon"}), ("excuse me?", {"pardon"}), ("pardon", {"pardon"}),
                    ("pardon me", {"pardon"}), ("sorry?", {"pardon"}), ("come again?", {"pardon"}),
                    ("say again", {"pardon"})], 0.16),
    # Random typing: not recognised, never a topic or an emergency.
    "gibberish": ([], 0.1),
    # A health word on its own.
    "health_word": ([("allergy", {"allergy"}), ("allergies", {"allergy"}), ("allergic", {"allergy"}),
                     ("med", {"med_help"}), ("medic", {"med_help"}), ("meds", {"medication"}),
                     ("medicine", {"medication"}), ("diabetes", {"condition_advice"}),
                     ("asthma", {"condition_advice"}), ("knee pain", {"pain_or_discomfort"})], 0.12),
    # Reporting.
    "report": ([("report", {"report_answer"}), ("report this", {"report_answer"}),
                ("how to report", {"report_answer"}), ("i want to report", {"report_answer"}),
                ("report wrong answer", {"report_answer"})], 0.08),
    # Remarks to the bot.
    "to_bot": ([("i m ur father", {"bot_identity"}), ("i am your father", {"bot_identity"}),
                ("are you my friend", {"bot_identity"}), ("i love you", {"bot_identity"}),
                ("are you single", {"bot_identity"}), ("you are stupid", {"report_answer"}),
                ("stupid bot", {"report_answer"}), ("you are useless", {"report_answer"})], 0.08),
    # "Really?" after an answer continues it (want = the previous topic).
    "after_answer": ([("really?", "previous"), ("are you sure", "previous"), ("why", "previous"),
                      ("how", "previous"), ("then?", "previous"), ("what?", "previous")], 0.08),
}
PREVIOUS = ["how_often", "pain_or_discomfort", "exercise:shoulder_abduction", "safety", "posture_result"]
PARTICLES = ["", "", "", " lah", " ah", " leh", " pls", " huh"]
MARKS = ["", "", "?", "??", "!", "...", " ?"]


def gibberish(rng: random.Random) -> str:
    return "".join(rng.choice(string.ascii_lowercase) for _ in range(rng.randint(2, 7)))


def messy(text: str, rng: random.Random) -> str:
    """[text] typed the way people type: a slip, stretched letters, capitals, a particle, punctuation."""
    words = text.split()
    if rng.random() < 0.3:
        cand = [k for k, w in enumerate(words) if len(w) >= 4 and w.isalpha()]
        if cand:
            from app.chat import engine
            k = rng.choice(cand)
            for _ in range(5):                           # not a slip that makes another real word
                slip = typo(words[k], rng)
                if slip not in engine._respell_vocab() and slip not in engine.dictionary():
                    words[k] = slip
                    break
    if rng.random() < 0.1 and words[-1].isalpha():
        words[-1] = words[-1] + words[-1][-1] * rng.randint(1, 3)          # "whattt", "thanksss"
    s = " ".join(words).rstrip("?!.")
    s += rng.choice(PARTICLES) + rng.choice(MARKS)
    r = rng.random()
    return s.upper() if r < 0.1 else (s[:1].upper() + s[1:] if r < 0.4 else s)


def build(seed: int, n: int = 2000) -> list[dict]:
    rng = random.Random(seed)
    kinds = list(PATTERNS)
    weights = [PATTERNS[k][1] for k in kinds]
    cases = []
    for _ in range(n):
        kind = rng.choices(kinds, weights)[0]
        previous = None
        if kind == "gibberish":
            text, want, base = gibberish(rng), {None}, "(random letters)"
        else:
            base, want = rng.choice(PATTERNS[kind][0])
            text = messy(base, rng) if kind not in ("emergency",) or rng.random() < 0.5 else base
            if want == "previous":
                previous = rng.choice(PREVIOUS)
                want = {previous}
        cases.append({"kind": kind, "text": text, "base": base, "previous_category": previous,
                      "want": sorted(map(str, want))})
    return cases
