# AI Server (FastAPI)

Stateless: never reads or writes Supabase. See `../supabase/HANDOFF.md` for what the app expects.

```powershell
cd ai_server
conda create -n apths python=3.11 -y
conda activate apths
pip install -r requirements.txt
copy .env.example .env
pytest -q
uvicorn app.main:app --reload --port 8000
```

The Flutter app on the emulator reaches it at `http://10.0.2.2:8000` (default `AI_BASE_URL`).
A real phone: `flutter run --dart-define=AI_BASE_URL=https://xxxx.trycloudflare.com`.
