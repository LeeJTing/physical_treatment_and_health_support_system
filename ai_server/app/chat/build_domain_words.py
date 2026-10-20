"""Writes other_domain_words.json: words people use for things a rehabilitation chatbot does not cover
(banking, travel, cars, music, shopping, work, news, sport...), learnt from the TRAINING questions of
CLINC150 (clinc/oos-eval data_full.json, CC BY 3.0; Larson et al., 2019), leaving out its intents that
overlap with this chatbot (reminders, calories, language, greetings, "are you a bot", ...).

The chatbot (engine.match, 3.57) does not guess a topic for a message that has one of these words and no
word specific to rehabilitation: "how long do wire transfers take" is not "how often". CLINC's
validation and test questions are kept for measuring it (evaluate_chat_noise.py).

    .venv\\Scripts\\python app\\chat\\build_domain_words.py
"""
import json
import re
from collections import Counter
from pathlib import Path

DATA = Path(__file__).resolve().parents[3] / "training" / "data" / "public" / "input_tests" / "clinc_data_full.json"
OUT = Path(__file__).with_name("other_domain_words.json")

# CLINC intents this chatbot answers too, or small talk: their words are not "another domain".
OVERLAP = {"alarm", "reminder", "reminder_update", "calories", "nutrition_info", "meal_suggestion", "change_language",
           "translate", "change_user_name", "user_name", "greeting", "goodbye", "thank_you", "yes", "no", "maybe",
           "repeat", "are_you_a_bot", "what_can_i_ask_you", "who_made_you", "what_is_your_name", "sync_device",
           "definition", "cancel", "how_old_are_you", "where_are_you_from", "who_do_you_work_for",
           "what_are_your_hobbies", "do_you_have_pets", "tell_joke", "fun_fact", "meaning_of_life", "time", "date",
           "timer", "change_speed", "change_volume", "spelling", "change_accent", "whisper_mode", "change_ai_name"}
MIN_COUNT = 3          # in at least 3 training questions of other domains


def main():
    """{word: [how many of the other domains (intents) use it, in how many questions]}"""
    d = json.loads(DATA.read_text(encoding="utf-8"))
    count, spread = Counter(), {}
    for text, intent in d["train"] + d["oos_train"]:
        if intent in OVERLAP:
            continue
        for w in set(re.findall(r"[a-z][a-z']+", text.lower())):
            count[w] += 1
            spread.setdefault(w, set()).add(intent)
    words = {w: [len(spread[w]), n] for w, n in sorted(count.items()) if n >= MIN_COUNT}
    OUT.write_text(json.dumps(words, separators=(",", ":")), encoding="utf-8")
    print(f"{len(words)} words -> {OUT}")


if __name__ == "__main__":
    main()
