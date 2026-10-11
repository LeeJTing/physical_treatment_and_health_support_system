"""Development viewer for the posture check (9 Oct, Elwin: "a platform where I can see the process when
I want to, only in the development stage"). Shows, for each run, the video frames with the body points
MediaPipe found, the measured signal and repetitions, the right-exercise check, every posture rule on
every repetition, the trained model's verdicts, the result and the time each step took.

Runs come from two places:
  * the phone: the AI server keeps every /pose request when started with DEV_TOOLS on
    (run_server.ps1 -DevTools); nothing is kept otherwise;
  * this page: upload any video and choose the exercise.

    powershell -ExecutionPolicy Bypass -File ai_server\\run_devtools.ps1      ->  http://127.0.0.1:8001

Listens on this PC only (127.0.0.1) and refuses anything that came through the Cloudflare tunnel. It is a
separate app from the AI server; it never runs in production.
"""
import tempfile
import time
from collections import OrderedDict
from pathlib import Path

import cv2
import numpy as np
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import HTMLResponse, JSONResponse, Response

from app.config import get_settings
from app.pose import exercises
from app.pose.analyse import HAND_EXERCISES
from app.pose.landmarks import extract_parallel, read_video_info
from app.pose.trace import load_run, save_run, trace

ROOT = Path(__file__).resolve().parents[1]
RUNS = (ROOT / get_settings().dev_runs_dir).resolve()
PAGE = Path(__file__).with_name("viewer.html")
FRAME_SIDE = 720                      # longest side of the frames sent to the page

app = FastAPI(title="APTHS posture viewer (development only)")
_frames: "OrderedDict[str, list[bytes | None]]" = OrderedDict()


@app.middleware("http")
async def this_pc_only(request: Request, call_next):
    tunnelled = any(h in request.headers for h in ("cf-connecting-ip", "cf-ray", "x-forwarded-for"))
    host = request.client.host if request.client else ""
    if tunnelled or host not in ("127.0.0.1", "::1", "localhost", "testclient"):
        return JSONResponse(status_code=403, content={"error": "development viewer: this PC only"})
    return await call_next(request)


@app.get("/", response_class=HTMLResponse)
def page():
    return PAGE.read_text(encoding="utf-8")


@app.get("/api/exercises")
def exercise_list():
    return [{"key": k, "name": s.name, "view": s.view} for k, s in exercises.EXERCISES.items()]


@app.get("/api/runs")
def runs():
    out = []
    if RUNS.exists():
        for d in sorted((p for p in RUNS.iterdir() if (p / "trace.json").exists()), reverse=True):
            tr, _, _ = load_run(RUNS, d.name)
            res = tr.get("result") or {}
            out.append({"id": d.name, "exercise": tr["exercise_name"], "source": tr.get("source"),
                        "saved_at": tr.get("saved_at"), "accuracy": res.get("accuracy"),
                        "repetitions": res.get("repetitions"),
                        "error": (tr.get("error") or {}).get("code")})
    return out


@app.get("/api/runs/{run_id}")
def run(run_id: str):
    tr, seq, video = _load(run_id)
    tr["frames"] = {
        "t": [round(float(x), 3) for x in seq.t],
        "xy": np.round(np.nan_to_num(seq.xy, nan=-1.0), 1).tolist(),
        "vis": np.round(seq.vis, 2).tolist(),
        "hands": None if seq.hands is None else np.round(np.nan_to_num(seq.hands, nan=-1.0), 1).tolist(),
        "width": seq.info.width, "height": seq.info.height, "has_video": video is not None,
    }
    return tr


@app.get("/api/runs/{run_id}/frames/{k}.jpg")
def frame(run_id: str, k: int):
    frames = _frames_of(run_id)
    if not 0 <= k < len(frames) or frames[k] is None:
        raise HTTPException(404, "no frame")
    return Response(frames[k], media_type="image/jpeg")


@app.post("/api/analyse")
def analyse_upload(file: UploadFile = File(...), exercise_key: str = Form(...), risk_level: str | None = Form(None),
                   age: int | None = Form(None)):
    if exercise_key not in exercises.EXERCISES:
        raise HTTPException(422, "unknown exercise")
    suffix = Path(file.filename or "video.mp4").suffix.lower() or ".mp4"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(file.file.read())
        path = Path(tmp.name)
    try:
        read_video_info(path)
        t0 = time.perf_counter()
        seq, brightness = extract_parallel(path, hands=exercise_key in HAND_EXERCISES)
        t_extract = time.perf_counter() - t0
        tr = trace(exercise_key, seq, exercises.rom_scale_for(risk_level or None, age), brightness,
                   {"mediapipe": round(t_extract, 3)})
        run_id = save_run(RUNS, path, seq, tr, f"upload: {file.filename}", get_settings().dev_runs_keep)
    except ValueError as e:
        raise HTTPException(422, str(e))
    finally:
        path.unlink(missing_ok=True)
    return {"id": run_id}


def _load(run_id: str):
    if not (RUNS / run_id / "trace.json").exists() or "/" in run_id or "\\" in run_id or ".." in run_id:
        raise HTTPException(404, "no such run")
    return load_run(RUNS, run_id)


def _frames_of(run_id: str) -> list:
    """JPEG frames at the analysed times, decoded once per run (the newest 3 runs are kept in memory)."""
    if run_id in _frames:
        _frames.move_to_end(run_id)
        return _frames[run_id]
    _, seq, video = _load(run_id)
    out: list = [None] * len(seq.t)
    if video is not None:
        fps = read_video_info(video).fps or 30.0
        want = {int(round(float(t) * fps)): k for k, t in enumerate(seq.t)}
        cap = cv2.VideoCapture(str(video))
        idx, last = 0, max(want) if want else -1
        while idx <= last:
            if idx in want:
                ok, img = cap.read()
                if not ok:
                    break
                s = FRAME_SIDE / max(img.shape[:2])
                if s < 1:
                    img = cv2.resize(img, (int(img.shape[1] * s), int(img.shape[0] * s)))
                out[want[idx]] = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 80])[1].tobytes()
            elif not cap.grab():
                break
            idx += 1
        cap.release()
    _frames[run_id] = out
    while len(_frames) > 3:
        _frames.popitem(last=False)
    return out
