# AI Server (FastAPI)

> **Also in its own repo:** `Lvin331/fyp-fastapi` (private) is a copy of this folder with the trained models,
> made by `python tool/sync_fastapi_repo.py ../fyp-fastapi --push`. Change the server here, then run that.

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

MediaPipe models (git-ignored, Apache 2.0) go in `models/weights/`:

```powershell
curl -L -o models/weights/pose_landmarker_full.task https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task
curl -L -o models/weights/hand_landmarker.task https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task
```

The hand model is only used for the wrist and hand exercises (`wrist_extension`, `hand_open_close`).

The Flutter app on the emulator reaches it at `http://10.0.2.2:8000` (default `AI_BASE_URL`).
A real phone: `flutter run --dart-define=AI_BASE_URL=https://xxxx.trycloudflare.com`.

## Posture check viewer (development only)

See what the posture check did, step by step: the body points MediaPipe found on each frame, the measured
signal and repetitions, the right-exercise check, every rule on every repetition, the model's verdicts and the
result.

```powershell
powershell -ExecutionPolicy Bypass -File ai_server\run_server.ps1 -DevTools   # keep the phone's /pose requests
powershell -ExecutionPolicy Bypass -File ai_server\run_devtools.ps1           # then open http://127.0.0.1:8001
```

The viewer listens on this PC only and refuses requests that came through the Cloudflare tunnel. Without
`-DevTools` the AI server keeps nothing (stateless); with it, the newest 20 requests (video, landmarks, trace)
are kept in `ai_server/dev_runs/` (git-ignored). Never use `-DevTools` with real patients' videos.
