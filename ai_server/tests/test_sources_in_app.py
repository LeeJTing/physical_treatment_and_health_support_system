"""Every source key the recommender can send is one the app can show (audit, 24 Oct).

The app turns keys into references with lib/core/constants/evidence_sources.dart and silently
leaves out a key it does not know, so a reason would lose its source without any error."""
import re
from pathlib import Path

from app.recommend import conditions as C
from app.recommend import explain

APP = Path(__file__).resolve().parents[2] / "lib" / "core" / "constants" / "evidence_sources.dart"


def app_keys() -> set[str]:
    return set(re.findall(r"^\s+'([a-z0-9_]+)': EvidenceSource\(", APP.read_text(encoding="utf-8"), re.M))


def server_keys() -> set[str]:
    keys = set(C.CONDITION_SOURCES.values()) | set(explain.AGE_SOURCES)
    text = Path(explain.__file__).read_text(encoding="utf-8")
    for block in re.findall(r"sources=\[([^\]]*)\]", text):
        keys |= set(re.findall(r'"([a-z0-9_]+)"', block))
    return keys


def test_every_server_source_is_known_to_the_app():
    assert app_keys(), "no keys read from the app file"
    missing = server_keys() - app_keys()
    assert not missing, f"sources the app cannot show: {sorted(missing)}"
