"""Copies the FastAPI server into its own repo, Lvin331/fyp-fastapi (private), so it can be run or
deployed on its own. This team repo stays the main copy: change the server here, then run

    python tool/sync_fastapi_repo.py ../fyp-fastapi [--push]

What goes in, in the same layout as here so no code path changes:
  ai_server/                   every file git tracks here (never .env, dev_runs or exported chats)
  assets/seed/catalogue.json   the plan catalogue the chatbot rules and the tests read
  ai_server/models/weights/    the files the server loads, git-ignored here: MediaPipe's pose and
                               hand models and the newest trained model of each exercise
The copy's ai_server/.gitignore lets those weights in. Some models were trained on CC BY-NC data
(REHAB24-6, REHAB26): the repo must stay private.
"""
import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REMOTE = "https://github.com/Lvin331/fyp-fastapi.git"
MEDIAPIPE = ["pose_landmarker_full.task", "hand_landmarker.task"]


def git(args, cwd, check=True):
    return subprocess.run(["git", *args], cwd=cwd, check=check, capture_output=True, text=True)


def newest_models(weights: Path) -> list[Path]:
    newest: dict[str, tuple[int, Path]] = {}
    for p in weights.glob("*_v*.pt"):
        key, ver = p.stem.rsplit("_v", 1)
        if ver.isdigit() and int(ver) > newest.get(key, (-1, p))[0]:
            newest[key] = (int(ver), p)
    return [p for _, p in sorted(newest.values(), key=lambda x: x[1].name)]


def readme(commit: str, subject: str, models: list[Path]) -> str:
    names = "\n".join(f"- `{p.name}`" for p in models)
    return f"""# fyp-fastapi

FastAPI AI server of the FYP *AI-Assisted Physical Treatment and Health Support System*
(Elwin Koh Soon Yit, Lee Jun Ting). Stateless: it never touches Supabase.

| Endpoint | What it does |
|---|---|
| `GET /health` | up check |
| `POST /recommend` | ranks treatment plans for the questionnaire (hybrid recommender) |
| `GET /chat/categories`, `POST /chat` | rule-based rehabilitation chatbot |
| `POST /pose` | posture check of an exercise video (MediaPipe + angle rules + trained models) |

**This is a copy.** The main copy is `ai_server/` in the team repo
(LeeJTing/physical_treatment_and_health_support_system, branch `Elwin`), copied here by
`tool/sync_fastapi_repo.py`. Change the server there, not here.

Copied from team repo commit `{commit}`: {subject}

## Run

```
cd ai_server
python -m venv .venv
.venv\\Scripts\\python -m pip install -r requirements.txt
copy .env.example .env        (then fill it in; never commit .env)
.venv\\Scripts\\python -m pytest -q
.venv\\Scripts\\python -m uvicorn app.main:app --port 8000
```

Every request needs `Authorization: Bearer <Supabase access token>`; `.env` sets how tokens are
checked (`SUPABASE_JWKS_URL`). `DEV_AUTH_BYPASS` must be false anywhere reachable from outside.

## Models (`ai_server/models/weights/`)

- `pose_landmarker_full.task`, `hand_landmarker.task`: Google MediaPipe (Apache 2.0)
{names}: trained for this project (training scripts in the team repo, `training/`)

Some training data is CC BY-NC 4.0 (REHAB24-6, REHAB26-ViewAngles): keep this repo private and
non-commercial.
"""


def main() -> int:
    ap = argparse.ArgumentParser(description="Copy ai_server/ into the fyp-fastapi repo.")
    ap.add_argument("target", type=Path, help="folder of the fyp-fastapi clone (created if missing)")
    ap.add_argument("--push", action="store_true", help="push to GitHub after committing")
    a = ap.parse_args()
    target = a.target.resolve()
    if target == ROOT or ROOT in target.parents:
        sys.exit("The target must be outside this repo.")

    if git(["status", "--porcelain", "--", "ai_server", "assets/seed/catalogue.json"], ROOT).stdout.strip():
        sys.exit("ai_server/ has uncommitted changes here: commit them first, so the copy matches a commit.")
    commit = git(["rev-parse", "--short", "HEAD"], ROOT).stdout.strip()
    subject = git(["log", "-1", "--format=%s"], ROOT).stdout.strip()

    target.mkdir(parents=True, exist_ok=True)
    if not (target / ".git").exists():
        git(["init", "-b", "main"], target)
        git(["remote", "add", "origin", REMOTE], target)

    # A clean copy: files removed here disappear there too. Only these two folders are replaced.
    for sub in ("ai_server", "assets"):
        if (target / sub).exists():
            shutil.rmtree(target / sub)
    files = git(["ls-files", "ai_server"], ROOT).stdout.splitlines() + ["assets/seed/catalogue.json"]
    for rel in files:
        dst = target / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, dst)

    weights = ROOT / "ai_server" / "models" / "weights"
    models = newest_models(weights)
    for p in [weights / n for n in MEDIAPIPE] + models:
        if not p.exists():
            sys.exit(f"Missing model file: {p}")
        shutil.copy2(p, target / "ai_server" / "models" / "weights" / p.name)

    gi = target / "ai_server" / ".gitignore"
    gi.write_text(re.sub(r"(?m)^(models/weights/\*|!models/weights/\.gitkeep)\n", "",
                         gi.read_text(encoding="utf-8")), encoding="utf-8")
    (target / "README.md").write_text(readme(commit, subject, models), encoding="utf-8")

    for secret in (".env",):
        if list(target.rglob(secret)):
            sys.exit(f"Refusing: a {secret} file is in the copy.")

    git(["add", "-A"], target)
    if not git(["status", "--porcelain"], target).stdout.strip():
        print("Nothing changed.")
    else:
        git(["commit", "-q", "-m", f"Server from team repo {commit}: {subject}"], target)
        print(git(["log", "--oneline", "-1"], target).stdout.strip())
    if a.push:
        r = git(["push", "-u", "origin", "main"], target, check=False)
        print(r.stdout + r.stderr)
        return r.returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())
