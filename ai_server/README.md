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

MediaPipe models (git-ignored, Apache 2.0) go in `models/weights/`:

```powershell
curl -L -o models/weights/pose_landmarker_full.task https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task
curl -L -o models/weights/hand_landmarker.task https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task
```

The hand model is only used for the wrist and hand exercises (`wrist_extension`, `hand_open_close`).

The Flutter app on the emulator reaches it at `http://10.0.2.2:8000` (default `AI_BASE_URL`).
A real phone: `flutter run --dart-define=AI_BASE_URL=https://xxxx.trycloudflare.com`.
