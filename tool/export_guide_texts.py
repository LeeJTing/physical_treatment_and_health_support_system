"""Exports the AI server's posture texts for the app's exercise guide (23 Oct): for each exercise, the
camera side (ExerciseSpec.view) and every mistake with the server's own "do this" sentence
(Mistake.feedback) and the chat's one-line meaning (MISTAKE_MEANING). The guide's hand-written
coaching files (assets/guides/coaching/) quote these texts; test/guide_coaching_test.dart compares
them with this fixture, so the guide and the server cannot drift apart. Run again after changing the
posture rules or the chat's mistake meanings:

    ai_server\\.venv\\Scripts\\python tool\\export_guide_texts.py

Writes test/fixtures/server_guide_texts.json.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "ai_server"))

from app.chat.build_rules import MISTAKE_MEANING  # noqa: E402
from app.pose.exercises import EXERCISES  # noqa: E402

out = {}
for key, spec in sorted(EXERCISES.items()):
    out[key] = {
        "view": spec.view,
        "mistakes": {
            m.label: {
                "feedback": m.feedback,
                "meaning": MISTAKE_MEANING.get(m.label, (None, None))[0],
            }
            for m in spec.mistakes
        },
    }

path = ROOT / "test" / "fixtures" / "server_guide_texts.json"
path.parent.mkdir(exist_ok=True)
path.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"{len(out)} exercises -> {path.relative_to(ROOT)}")
