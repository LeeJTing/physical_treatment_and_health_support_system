"""Shared helpers for the training scripts. Run every script with the AI
server's Python so it uses the same posture code as /pose:

    ai_server\\.venv\\Scripts\\python training\\<script>.py
"""
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TRAINING = ROOT / "training"
DATA = TRAINING / "data"
CACHE = DATA / "cache"
REPORTS = TRAINING / "reports"
sys.path.insert(0, str(ROOT / "ai_server"))

from app.pose import exercises  # noqa: E402
from app.pose import landmarks  # noqa: E402

VIDEO_EXT = {".mp4", ".mov"}
NAME_RE = re.compile(
    r"^(?P<key>[a-z_]+?)__(?P<label>correct|incorrect)__(?P<mistake>[a-z_]+)__(?P<person>p\d{2})__"
    r"(?P<side>left|right|both)__(?P<take>\d{2,3})$")


@dataclass
class Clip:
    path: Path
    key: str            # exercise folder
    folder_label: str   # correct / incorrect folder
    name_ok: bool
    problems: list[str]
    label: str = ""
    mistake: str = ""
    person: str = ""
    side: str = ""

    @property
    def is_correct(self) -> bool:
        return (self.label or self.folder_label) == "correct"

    @property
    def cache_path(self) -> Path:
        return CACHE / self.key / f"{self.path.stem}.npz"


def parse(path: Path) -> Clip:
    key, folder_label = path.parent.parent.name, path.parent.name
    clip = Clip(path=path, key=key, folder_label=folder_label, name_ok=False, problems=[])
    m = NAME_RE.match(path.stem.lower())
    if not m:
        clip.problems.append("file name does not follow exercise__correct|incorrect__mistake|ok__pNN__side__NN")
        return clip
    g = m.groupdict()
    clip.name_ok = True
    clip.label, clip.mistake, clip.person, clip.side = g["label"], g["mistake"], g["person"], g["side"]
    if g["key"] != key:
        clip.problems.append(f"name says '{g['key']}' but the clip is in the '{key}' folder")
    if g["label"] != folder_label:
        clip.problems.append(f"name says '{g['label']}' but the clip is in the '{folder_label}' folder")
    spec = exercises.EXERCISES.get(key)
    if spec is None:
        clip.problems.append(f"'{key}' is not a known exercise")
    elif g["label"] == "correct" and g["mistake"] != "ok":
        clip.problems.append("a correct clip must use 'ok' as the mistake part")
    elif g["label"] == "incorrect" and g["mistake"] not in {m.label for m in spec.mistakes}:
        valid = ", ".join(m.label for m in spec.mistakes)
        clip.problems.append(f"unknown mistake '{g['mistake']}' (use one of: {valid})")
    return clip


def own_clips(keys: list[str] | None = None) -> list[Clip]:
    out = []
    for key in sorted(keys or exercises.EXERCISES):
        for label in ("correct", "incorrect"):
            folder = DATA / key / label
            if folder.exists():
                out += [parse(p) for p in sorted(folder.iterdir()) if p.suffix.lower() in VIDEO_EXT]
    return out


def cached_sequence(clip: Clip, refresh: bool = False) -> "landmarks.PoseSequence":
    """Landmarks are the slow step (about 1 s per 3 s of video), so they are cached per clip."""
    cp = clip.cache_path
    if cp.exists() and not refresh and cp.stat().st_mtime >= clip.path.stat().st_mtime:
        return landmarks.load(cp)
    seq = landmarks.extract(clip.path)
    cp.parent.mkdir(parents=True, exist_ok=True)
    landmarks.save(seq, cp)
    return seq
