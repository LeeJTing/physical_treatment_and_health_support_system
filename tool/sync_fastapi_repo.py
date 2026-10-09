"""Copies the FastAPI server into its own repo, Lvin331/fyp-fastapi (private), so it can be run or
deployed on its own. This team repo stays the main copy: change the server here, then run

    python tool/sync_fastapi_repo.py ../fyp-fastapi [--push]

What goes in, in the same layout as here so no code path changes:
  ai_server/                   every file git tracks here (never .env, dev_runs or exported chats),
                               with docs/API.md, docs/openapi.json and CONTRIBUTING.md
  ai_server/models/weights/    the files the server loads, git-ignored here: MediaPipe's pose and
                               hand models and the newest trained model of each exercise
  training/                    how the posture models were trained and evaluated (scripts and the
                               committed reports; the clips themselves are git-ignored)
  assets/seed/catalogue.json   the plan catalogue the chatbot rules and the tests read
The copy's ai_server/.gitignore lets those weights in. Some models were trained on CC BY-NC data
(REHAB24-6, REHAB26): the repo must stay private.

It never overwrites anyone's work: if fyp-fastapi's main has a commit this script did not make
(e.g. Jun Ting's), it stops and says so.
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
SYNC_PREFIX = "Server from team repo "
COPIED = ["ai_server", "training", "assets/seed/catalogue.json"]


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

The AI server of the FYP *AI-Assisted Physical Treatment and Health Support System* (APTHS;
Elwin Koh Soon Yit and Lee Jun Ting). FastAPI, Python 3.11, stateless: it never touches Supabase;
the Flutter app sends what is needed and stores what comes back.

| Endpoint | Module | What it does | Status |
|---|---|---|---|
| `POST /recommend` | M500.1 | ranks treatment plans for the questionnaire (hybrid recommender) | built |
| `GET /chat/categories`, `POST /chat` | M500.2 | rule-based rehabilitation chatbot | built |
| `GET /pose/exercises`, `POST /pose` | M300.1 | posture check of an exercise video | built |
| `POST /forecast`, `POST /analyse` | M400 | forecaster, anomaly detector and health score | to build (Jun Ting) |
| `POST /recognise`, `POST /plan` | M700 | food recognition, condition-aware diet planner | to build (Jun Ting) |

- **API contract:** [`ai_server/docs/API.md`](ai_server/docs/API.md), exact schema in
  [`ai_server/docs/openapi.json`](ai_server/docs/openapi.json) (also `/docs` on a running server)
- **Adding an endpoint, rules, how changes travel:** [`ai_server/CONTRIBUTING.md`](ai_server/CONTRIBUTING.md)
- **Server details** (posture pipeline, chatbot rounds, development viewer): [`ai_server/README.md`](ai_server/README.md)
- **How the posture models were trained and evaluated:** [`training/README.md`](training/README.md) and
  `training/reports/` (the training clips are not in git)

## Run

```
cd ai_server
python -m venv .venv
.venv\\Scripts\\python -m pip install -r requirements.txt
copy .env.example .env
.venv\\Scripts\\python -m pytest -q
.venv\\Scripts\\python -m uvicorn app.main:app --port 8000
```

`run_server.ps1` starts it the same way; `run_tunnel.ps1` gives it a public `trycloudflare.com`
address for the phone (the demo setup: the server on the PC, the app anywhere). Every request needs
`Authorization: Bearer <Supabase access token>`; with `DEV_AUTH_BYPASS=true` the token `dev-token`
also works (development only; set it false when the server is reachable with real accounts).

## Models (`ai_server/models/weights/`)

- `pose_landmarker_full.task`, `hand_landmarker.task`: Google MediaPipe (Apache 2.0)
{names}: trained for this project (`training/train.py`)

Some training data is CC BY-NC 4.0 (REHAB24-6, REHAB26-ViewAngles): this repo stays private and
non-commercial.

## Where this copy comes from

Copied by `tool/sync_fastapi_repo.py` from `ai_server/`, `training/` and the plan catalogue of the
team repo (LeeJTing/physical_treatment_and_health_support_system, branch `Elwin`), commit
`{commit}`: {subject}. The script refuses to run when this repo has commits it did not make, so
nothing pushed here is overwritten.
"""


def main() -> int:
    ap = argparse.ArgumentParser(description="Copy ai_server/ into the fyp-fastapi repo.")
    ap.add_argument("target", type=Path, help="folder of the fyp-fastapi clone (created if missing)")
    ap.add_argument("--push", action="store_true", help="push to GitHub after committing")
    a = ap.parse_args()
    target = a.target.resolve()
    if target == ROOT or ROOT in target.parents:
        sys.exit("The target must be outside this repo.")

    # Changes to tracked files only: untracked logs in training/reports are never copied anyway.
    if git(["status", "--porcelain", "--untracked-files=no", "--", *COPIED], ROOT).stdout.strip():
        sys.exit("ai_server/ or training/ has uncommitted changes here: commit them first, so the copy "
                 "matches a commit.")
    commit = git(["rev-parse", "--short", "HEAD"], ROOT).stdout.strip()
    subject = git(["log", "-1", "--format=%s"], ROOT).stdout.strip()

    target.mkdir(parents=True, exist_ok=True)
    if not (target / ".git").exists():
        git(["init", "-b", "main"], target)
        git(["remote", "add", "origin", REMOTE], target)

    # Never overwrite someone else's work: stop if GitHub's main has a commit this script did not make.
    git(["fetch", "-q", "origin"], target, check=False)
    if git(["rev-parse", "--verify", "-q", "origin/main"], target, check=False).returncode == 0:
        foreign = [s for s in git(["log", "--format=%h %an: %s", "origin/main"], target).stdout.splitlines()
                   if SYNC_PREFIX not in s]
        if foreign:
            sys.exit("fyp-fastapi has commits not made by this script, so copying would overwrite them:\n  "
                     + "\n  ".join(foreign) + "\nBring those changes into the team repo first (or decide "
                     "which repo is the main home of the server).")
        if git(["merge", "-q", "--ff-only", "origin/main"], target, check=False).returncode != 0:
            sys.exit("The local fyp-fastapi copy and GitHub have diverged; sort that out first.")
    if git(["status", "--porcelain"], target).stdout.strip():
        sys.exit(f"{target} has uncommitted changes: they would be lost.")

    # A clean copy: files removed here disappear there too. Only these two folders are replaced.
    for sub in ("ai_server", "training", "assets"):
        if (target / sub).exists():
            shutil.rmtree(target / sub)
    files = git(["ls-files", *COPIED], ROOT).stdout.splitlines()
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
        git(["commit", "-q", "-m", f"{SYNC_PREFIX}{commit}: {subject}"], target)
        print(git(["log", "--oneline", "-1"], target).stdout.strip())
    if a.push:
        r = git(["push", "-u", "origin", "main"], target, check=False)
        print(r.stdout + r.stderr)
        return r.returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())
