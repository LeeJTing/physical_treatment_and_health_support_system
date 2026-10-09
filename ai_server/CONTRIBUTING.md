# Working on the AI server

For Elwin and Jun Ting. The report's AI server has seven endpoints (Table 4.2.4); three are built
(`/recommend`, `/chat`, `/pose`) and four are Jun Ting's to add (`/forecast`, `/analyse`,
`/recognise`, `/plan`). The contract of every endpoint: [`docs/API.md`](docs/API.md) and
[`docs/openapi.json`](docs/openapi.json).

## Set up and check

```
cd ai_server
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt
copy .env.example .env
.venv\Scripts\python -m pytest -q          (all must pass before a push)
.venv\Scripts\python -m uvicorn app.main:app --port 8000      then http://localhost:8000/docs
```

## Adding an endpoint (e.g. `/forecast`)

1. **The engine** in its own package, `app/<name>/` (as `app/recommend/`, `app/chat/`, `app/pose/`):
   plain functions that take Python values and return Python values, no FastAPI in them, so they
   are easy to test.
2. **The router** `app/routers/<name>.py`, registered in `app/main.py` with `app.include_router`:
   ```python
   from fastapi import APIRouter, Depends
   from pydantic import BaseModel
   from ..auth import current_account_id

   router = APIRouter(tags=["M400 analysis"])

   class ForecastIn(BaseModel):
       readings: list[float]

   @router.post("/forecast")
   def forecast(body: ForecastIn, account_id: str = Depends(current_account_id)):
       ...
   ```
   Every endpoint except `/health` takes `Depends(current_account_id)`. Request and response are
   pydantic models; enum-like fields use `Literal[...]` with the same values the app and the database
   use (e.g. `"LOW" | "MODERATE" | "HIGH"`).
3. **Errors** the app has to tell apart: HTTP 422 with `{"error": {"code": "...", "message": "..."}}`
   (as `/pose` does); the app maps each code to the report's message. Never return a stack trace.
4. **Model files** go in `models/weights/` with a version in the name (`<name>_v<N>.<ext>`), loaded
   once and cached (see `app/pose/classifier.py`). Write down where each model's training data came
   from and its licence in the README.
5. **Tests** in `tests/test_<name>.py` with FastAPI's `TestClient` and the token `dev-token`
   (see `tests/test_recommend.py`): the happy path, a bad request, and each error code.
6. **Contract**: run `.venv\Scripts\python export_openapi.py` and commit `docs/openapi.json`
   (`tests/test_api_docs.py` fails until you do); add the endpoint to `docs/API.md`.
7. New packages go in `requirements.txt`.

## Rules that keep the system as the report describes it

- **Stateless:** the server never reads or writes Supabase and keeps nothing between requests. The
  app sends what is needed (e.g. past readings for `/forecast`) and stores what comes back.
- **No patient data in git:** no videos, photos, health readings or chat questions. `dev_runs/`
  (development viewer) and `backlog*.csv` (exported chat questions) are git-ignored; keep it so.
- **Secrets only in `.env`** (git-ignored). `DEV_AUTH_BYPASS` must be `false` wherever the server can
  be reached from outside with real accounts.
- This repo is **private**: some training data is licensed for non-commercial use only.

## How changes travel

The server also lives in the team repo (`ai_server/` on branch `Elwin`), and
`tool/sync_fastapi_repo.py` there copies it into `Lvin331/fyp-fastapi`. That script will not run
when `fyp-fastapi` has commits it did not make, so it never overwrites anyone's work. Until Elwin
and Jun Ting decide which repo is the main home of the server, work on a branch
(e.g. `junting/forecast`) and open a pull request.
