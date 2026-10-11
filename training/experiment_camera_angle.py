"""Camera-angle robustness test on Elwin's labelled clips (8 Oct, after the sit2stand.ai outside test
showed that a phone at 45 degrees merged sit-to-stand repetitions).

MediaPipe also estimates a 3D skeleton per frame (world landmarks, metres, centred on the hips). Each
clip's real movement is turned in 3D and seen again from virtual cameras:
  * yaw  +-15, +-30, +-45, +-60 degrees around the person (the phone moved round from where it was);
  * pitch +-15 degrees (the phone placed higher or lower).
The hip-centred skeleton has no whole-body movement (rising from a chair, stepping up), so the hip
centre's path is put back from the 2D image, scaled from pixels to metres by the torso length. Depth is
estimated from a single camera, so large turns are rough; the yaw 0 rendering is compared with the
normal 2D pipeline first, to show how far the method itself changes the result.

This is a robustness test of the rules, not an accuracy figure: the movements are Elwin's (and p02's).

    ai_server\\.venv\\Scripts\\python training\\experiment_camera_angle.py [pose_key ...] [--workers 3]

World landmarks are cached in training/data/cache/world. Writes training/reports/camera_angle_eval.json.
"""
import argparse
import json
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor, as_completed

import numpy as np

from common import CACHE, REPORTS, cached_sequence, own_clips
from app.pose import exercises
from app.pose.analyse import PoseError, analyse
from app.pose.landmarks import (L_HIP, L_SHOULDER, R_HIP, R_SHOULDER, PoseSequence, VideoInfo,
                                _make_landmarker, _pad_square, read_video_info, DEFAULT_MODEL)

OUT = CACHE / "world"
YAWS = [0, 15, -15, 30, -30, 45, -45, 60, -60]
PITCHES = [15, -15]
W, H, FOCAL, DIST = 1920, 1080, 1000.0, 2.6     # virtual camera: landscape, ~65 % body height


def extract_world(path_str: str, key: str) -> str:
    """2D and 3D landmarks at 10 fps, the same sampling and square padding as landmarks.extract."""
    import cv2
    import mediapipe as mp
    from pathlib import Path
    path = Path(path_str)
    cp = OUT / key / f"{path.stem}.npz"
    if cp.exists():
        return path.stem
    info = read_video_info(path)
    src_fps = info.fps if info.fps > 0 else 30.0
    step = max(1, round(src_fps / 10.0))
    cap = cv2.VideoCapture(str(path))
    lmk = _make_landmarker(DEFAULT_MODEL)
    world, xy, vis, ts = [], [], [], []
    idx = 0
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            if idx % step == 0:
                h, w = frame.shape[:2]
                rgb = np.ascontiguousarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
                if h != w:
                    rgb = _pad_square(rgb)
                s = max(h, w)
                res = lmk.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb),
                                           int(round(idx * 1000.0 / src_fps)))
                if res.pose_landmarks and res.pose_world_landmarks:
                    xy.append([[p.x * s, p.y * s] for p in res.pose_landmarks[0]])
                    vis.append([float(getattr(p, "visibility", 1.0) or 0.0) for p in res.pose_landmarks[0]])
                    world.append([[p.x, p.y, p.z] for p in res.pose_world_landmarks[0]])
                else:
                    xy.append(np.full((33, 2), np.nan).tolist())
                    vis.append([0.0] * 33)
                    world.append(np.full((33, 3), np.nan).tolist())
                ts.append(idx / src_fps)
            idx += 1
    finally:
        lmk.close()
        cap.release()
    cp.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(cp, world=np.asarray(world, np.float32), xy=np.asarray(xy, np.float32),
                        vis=np.asarray(vis, np.float32), t=np.asarray(ts, np.float32),
                        info=np.array([info.fps, info.frame_count, info.width, info.height], np.float64))
    return path.stem


def render(d, yaw: float, pitch: float) -> PoseSequence:
    world, xy = d["world"].astype(np.float64), d["xy"].astype(np.float64)
    sh_w = (world[:, L_SHOULDER] + world[:, R_SHOULDER]) / 2
    hip_w = (world[:, L_HIP] + world[:, R_HIP]) / 2
    sh_p = (xy[:, L_SHOULDER] + xy[:, R_SHOULDER]) / 2
    hip_p = (xy[:, L_HIP] + xy[:, R_HIP]) / 2
    px_per_m = np.nanmedian(np.linalg.norm(sh_p - hip_p, axis=1)) / np.nanmedian(np.linalg.norm(sh_w - hip_w, axis=1))
    move = (hip_p - np.nanmedian(hip_p, axis=0)) / px_per_m              # whole-body movement in the image plane
    pts = world + np.concatenate([move, np.zeros((len(move), 1))], axis=1)[:, None, :]
    a, b = np.radians(yaw), np.radians(pitch)
    ry = np.array([[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]])
    rx = np.array([[1, 0, 0], [0, np.cos(b), -np.sin(b)], [0, np.sin(b), np.cos(b)]])
    p = pts @ (rx @ ry).T
    z = p[..., 2] + DIST
    uv = np.stack([FOCAL * p[..., 0] / z + W / 2, FOCAL * p[..., 1] / z + H / 2], axis=-1)
    fps, frames = float(d["info"][0]), int(d["info"][1])
    return PoseSequence(xy=uv.astype(np.float32), vis=d["vis"], t=d["t"], info=VideoInfo(fps, frames, W, H))


def verdict(key: str, seq: PoseSequence):
    """(called correct, repetitions, mistakes found) with the app's rules, or None when it gives up."""
    try:
        res = analyse(key, seq, use_model=False)
    except PoseError:
        return None
    reps = res["rep_details"]
    clean = sum(1 for r in reps if not r["mistakes"])
    return clean >= len(reps) / 2, res["repetitions"], set(res["mistakes"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("keys", nargs="*")
    ap.add_argument("--workers", type=int, default=3)
    a = ap.parse_args()
    clips = [c for c in own_clips(a.keys or None) if c.name_ok and not c.problems]
    todo = [c for c in clips if not (OUT / c.key / f"{c.path.stem}.npz").exists()]
    print(f"{len(clips)} clips, {len(todo)} to extract", flush=True)
    if todo:
        with ProcessPoolExecutor(a.workers) as pool:
            futs = {pool.submit(extract_world, str(c.path), c.key): c for c in todo}
            for i, fut in enumerate(as_completed(futs), 1):
                try:
                    fut.result()
                except Exception as e:
                    print(f"  failed {futs[fut].path.name}: {e}", flush=True)
                if i % 25 == 0:
                    print(f"  extracted {i}/{len(todo)}", flush=True)

    views = [("2D pipeline", None, None)] + [(f"yaw {y:+d}", y, 0) for y in YAWS] + [(f"pitch {p:+d}", 0, p) for p in PITCHES]
    report = {}
    for key in sorted({c.key for c in clips}):
        spec = exercises.EXERCISES[key]
        rows = defaultdict(lambda: {"right": 0, "n": 0, "gave_up": 0, "same_reps": 0, "false": defaultdict(int),
                                    "caught": defaultdict(int), "n_correct": 0, "n_mistake": defaultdict(int)})
        for c in [c for c in clips if c.key == key]:
            cp = OUT / key / f"{c.path.stem}.npz"
            if not cp.exists():
                continue
            d = dict(np.load(cp))
            base = verdict(key, cached_sequence(c))
            for name, yaw, pitch in views:
                v = base if yaw is None else verdict(key, render(d, yaw, pitch))
                r = rows[name]
                r["n"] += 1
                if c.is_correct:
                    r["n_correct"] += 1
                else:
                    r["n_mistake"][c.mistake] += 1
                if v is None:
                    r["gave_up"] += 1
                    continue
                ok, reps, found = v
                r["right"] += int(ok == c.is_correct)
                r["same_reps"] += int(base is not None and reps == base[1])
                if c.is_correct:
                    for m in found:
                        r["false"][m] += 1
                elif c.mistake in found:
                    r["caught"][c.mistake] += 1
        report[key] = {"view": spec.view, "conditions": {}}
        print(f"\n== {key} ({spec.view} view), {rows['2D pipeline']['n']} clips")
        for name, _, _ in views:
            r = rows[name]
            if not r["n"]:
                continue
            out = {"accuracy": round(r["right"] / r["n"], 3), "gave_up": r["gave_up"],
                   "same_reps_as_2d": round(r["same_reps"] / r["n"], 3),
                   "false_alarms_on_correct": {m: f"{k}/{r['n_correct']}" for m, k in r["false"].items()},
                   "caught": {m: f"{r['caught'][m]}/{n}" for m, n in r["n_mistake"].items()}}
            report[key]["conditions"][name] = out
            fa = ", ".join(f"{m} {v}" for m, v in out["false_alarms_on_correct"].items()) or "-"
            missed = ", ".join(f"{m} {v}" for m, v in out["caught"].items() if v.split("/")[0] != v.split("/")[1]) or "-"
            print(f"   {name:12s} right {out['accuracy']:.0%}  gave up {r['gave_up']:2d}  same reps {out['same_reps_as_2d']:.0%}"
                  f"  | false alarms: {fa}  | not caught: {missed}")
    REPORTS.mkdir(exist_ok=True)
    (REPORTS / "camera_angle_eval.json").write_text(json.dumps(report, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
