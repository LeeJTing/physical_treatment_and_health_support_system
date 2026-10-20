"""Writes other_domain_words.json: words people use for things a rehabilitation chatbot does not cover
(banking, travel, cars, music, shopping, work, news, sport, pets, smart lights...), learnt from

  CLINC150   the TRAINING questions (clinc/oos-eval data_full.json, CC BY 3.0; Larson et al., 2019);
  MASSIVE    English questions to a voice assistant in 18 everyday domains (amazon-science/massive 1.1,
             en-US, CC BY 4.0; FitzGerald et al., 2022), for words CLINC has not rated (3.59: "what do
             geese eat", "what's the best crypto to buy"). Its Malay (ms-MY) is not used: read by hand, it
             holds words this chatbot needs ("ulangan", "kerusi", "rehat", "kanan", "patutkah").

leaving out the intents of both that overlap with this chatbot (reminders, calories, language,
greetings, jokes, "are you a bot", definitions, ...).

The chatbot (engine.match, 3.57) does not guess a topic for a message that has one of these words and no
word specific to rehabilitation: "how long do wire transfers take" is not "how often". The rules' own
words are never another domain's (engine._domain_words). CLINC's validation and test questions are kept
for measuring it (evaluate_chat_noise.py); MASSIVE is not used there.

It also writes domain_weights.json (3.61): per word stem, how much likelier it is in a question of those
other domains than in this chatbot's own rules (keywords, example questions, exercise names and
instructions, warning-sign phrases): log((n_other(w)+1)/(N_other+2)) - log((n_rules(w)+1)/(N_rules+2)).
A message whose words add up to more than engine.OFF_DOMAIN_SCORE, with no word that is clearly about
rehabilitation, is not guessed a topic either: "can you help me move money between accounts" is not
"account and login", "how can I raise my credit score" not "your posture score". Rebuild it after
changing the rules.

    .venv\\Scripts\\python app\\chat\\build_domain_words.py [out.json]
"""
import json
import math
import re
import sys
from collections import Counter
from pathlib import Path

PUBLIC = Path(__file__).resolve().parents[3] / "training" / "data" / "public"
DATA = PUBLIC / "input_tests" / "clinc_data_full.json"
MASSIVE = [PUBLIC / "massive" / "data" / "en-US.jsonl"]
OUT = Path(__file__).with_name("other_domain_words.json")
WEIGHTS = Path(__file__).with_name("domain_weights.json")

# CLINC intents this chatbot answers too, or small talk: their words are not "another domain".
OVERLAP = {"alarm", "reminder", "reminder_update", "calories", "nutrition_info", "meal_suggestion", "change_language",
           "translate", "change_user_name", "user_name", "greeting", "goodbye", "thank_you", "yes", "no", "maybe",
           "repeat", "are_you_a_bot", "what_can_i_ask_you", "who_made_you", "what_is_your_name", "sync_device",
           "definition", "cancel", "how_old_are_you", "where_are_you_from", "who_do_you_work_for",
           "what_are_your_hobbies", "do_you_have_pets", "tell_joke", "fun_fact", "meaning_of_life", "time", "date",
           "timer", "change_speed", "change_volume", "spelling", "change_accent", "whisper_mode", "change_ai_name"}
# The same for MASSIVE (alarms and calendar are reminders here; general_* is small talk).
MASSIVE_OVERLAP = {"alarm_query", "alarm_remove", "alarm_set", "calendar_query", "calendar_remove", "calendar_set",
                   "datetime_convert", "datetime_query", "general_greet", "general_joke", "general_quirky",
                   "audio_volume_down", "audio_volume_mute", "audio_volume_other", "audio_volume_up", "qa_definition"}
# MASSIVE words read by hand (20 Oct) that a patient may use about exercising, the body, feelings, the
# weather or place they exercise in, what they wear, sport, or this app: never another domain's.
KEEP_OUT = set("""accidents alive anxiety attention bench boots charger chill colder complain complaint crazy desk
enjoy experience fresh glove gloves hallway horrible terrible jacket load measurements mile negative overhead circle
perfect porch preferences quality race rainy raining raincoat reply replied replies respond responded response rude
runner rush sandals selfie shape shut sucks summer sunblock sunscreen sweater taste teeth vegetables vegetarian
warned windy upwards disturbed screwed enable disable activate launch notes contacts photos pictures selected
selection television value worker shoot dust cleaner hat coat golf basketball chess girlfriend guys women's
upwards bright brighter brightness darker darken dim lamp""".split())
MIN_COUNT = 3          # in at least 3 questions of other domains
MASSIVE_SPREAD = 2     # a MASSIVE word: in at most 2 of its 18 domains (scenarios)


def _ai_server_words() -> set:
    """Grammar and everyday Malay words (engine.STOP, COMMON_MALAY, MALAY_GRAMMAR) and every word in the
    rules' own text (answers and examples too): never another domain's."""
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from app.chat.engine import COMMON_MALAY, MALAY_GRAMMAR, STOP, RULES_PATH
    rules_words = set(re.findall(r"[a-z][a-z']+", RULES_PATH.read_text(encoding="utf-8").lower()))
    return STOP | COMMON_MALAY | MALAY_GRAMMAR | rules_words | KEEP_OUT


def clinc_words() -> dict:
    """{word: [how many of the other domains (intents) use it, in how many questions]}"""
    d = json.loads(DATA.read_text(encoding="utf-8"))
    count, spread = Counter(), {}
    for text, intent in d["train"] + d["oos_train"]:
        if intent in OVERLAP:
            continue
        for w in set(re.findall(r"[a-z][a-z']+", text.lower())):
            count[w] += 1
            spread.setdefault(w, set()).add(intent)
    return {w: [len(spread[w]), n] for w, n in sorted(count.items()) if n >= MIN_COUNT}


def massive_words(known: dict) -> dict:
    """{word: [how many MASSIVE domains use it, in how many questions]} for words of at most MASSIVE_SPREAD
    domains that CLINC has not rated and that are not grammar or everyday Malay."""
    common = _ai_server_words()
    count, spread = Counter(), {}
    for path in MASSIVE:
        if not path.exists():
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            d = json.loads(line)
            if d["intent"] in MASSIVE_OVERLAP:
                continue
            for w in set(re.findall(r"[a-z][a-z']+", d["utt"].lower())):
                count[w] += 1
                spread.setdefault(w, set()).add(d["scenario"])
    return {w: [len(spread[w]), n] for w, n in sorted(count.items())
            if n >= MIN_COUNT and len(spread[w]) <= MASSIVE_SPREAD and w not in known and w not in common
            and len(w) >= 3}


def domain_weights() -> dict:
    """{stem: log-likelihood ratio, other domains over this chatbot's rules} (3.61)."""
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from app.chat import engine

    def stems(text: str) -> set:
        return {engine.stem(w) for w in re.findall(r"[a-z][a-z']+", engine.clean(text)) if w not in engine.STOP}

    r = json.loads(engine.RULES_PATH.read_text(encoding="utf-8"))
    ours = [t for i in r["intents"] for t in i["keywords"] + i["examples"]]
    ours += [t for e in r["exercises"].values() for t in [e["name"], e["instruction"]] + e["aliases"]]
    ours += list(r.get("glossary", {})) + r["red_flags"]
    d = json.loads(DATA.read_text(encoding="utf-8"))
    theirs = [t for t, intent in d["train"] + d["oos_train"] if intent not in OVERLAP]
    for path in MASSIVE:
        for line in path.read_text(encoding="utf-8").splitlines():
            x = json.loads(line)
            if x["intent"] not in MASSIVE_OVERLAP:
                theirs.append(x["utt"])
    n_ours, n_theirs = Counter(), Counter()
    for t in ours:
        n_ours.update(stems(t))
    for t in theirs:
        n_theirs.update(stems(t))
    return {w: round(math.log((n_theirs[w] + 1) / (len(theirs) + 2)) - math.log((n_ours[w] + 1) / (len(ours) + 2)), 2)
            for w in sorted(set(n_ours) | set(n_theirs))}


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else OUT
    words = clinc_words()
    extra = massive_words(words)
    words.update(extra)
    out.write_text(json.dumps(dict(sorted(words.items())), separators=(",", ":")), encoding="utf-8")
    print(f"{len(words)} words ({len(extra)} from MASSIVE) -> {out}")
    weights = domain_weights()
    WEIGHTS.write_text(json.dumps(weights, separators=(",", ":")), encoding="utf-8")
    print(f"{len(weights)} word weights -> {WEIGHTS}")


if __name__ == "__main__":
    main()
