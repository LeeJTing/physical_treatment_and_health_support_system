"""Outside test of the possible-fall alert on real (acted) falls: UR Fall Detection Dataset (Kwolek &
Kepski 2014, University of Rzeszow; CC BY-NC-SA 4.0, non-commercial academic use, cite the paper).
30 falls and 40 everyday activities (sitting down, picking things up, lying down...) filmed by a Kinect
RGB camera parallel to the floor (cam0), like a phone on a stand. The falls are PNG sequences at 30
fps and are turned into MP4 first.

Before this the fall check had only synthetic tests. Here: how many real falls it catches, and how
often it fires on everyday movements. The check runs as in the app for a standing exercise (march in
place: side view, not a lying exercise).

    ai_server\\.venv\\Scripts\\python training\\evaluate_urfall.py [--workers 3]

Landmarks are cached in training/data/cache/urfall. Writes training/reports/urfall_eval.json.
"""
import argparse
import json
import zipfile
from concurrent.futures import ProcessPoolExecutor, as_completed

import numpy as np

from common import CACHE, DATA, REPORTS
from app.pose import exercises, landmarks
from app.pose.analyse import possible_fall
from app.pose.geometry import Features

ROOT = DATA / "public" / "urfall"
OUT = CACHE / "urfall"


def to_mp4(zip_path) -> str:
    import cv2
    mp4 = zip_path.with_name(zip_path.name.replace("-cam0-rgb.zip", "-cam0.mp4"))
    if mp4.exists():
        return str(mp4)
    with zipfile.ZipFile(zip_path) as z:
        names = sorted(n for n in z.namelist() if n.endswith(".png"))
        writer = None
        for n in names:
            img = cv2.imdecode(np.frombuffer(z.read(n), np.uint8), cv2.IMREAD_COLOR)
            if writer is None:
                h, w = img.shape[:2]
                writer = cv2.VideoWriter(str(mp4), cv2.VideoWriter_fourcc(*"mp4v"), 30.0, (w, h))
            writer.write(img)
        writer.release()
    return str(mp4)


def extract_one(path_str: str) -> str:
    from pathlib import Path
    path = Path(path_str)
    cp = OUT / f"{path.stem}.npz"
    if not cp.exists():
        seq = landmarks.extract(path)
        cp.parent.mkdir(parents=True, exist_ok=True)
        landmarks.save(seq, cp)
    return path.stem


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=3)
    a = ap.parse_args()
    falls = [to_mp4(z) for z in sorted(ROOT.glob("fall-*-cam0-rgb.zip"))]
    adls = [str(p) for p in sorted(ROOT.glob("adl-*-cam0.mp4"))]
    todo = [p for p in falls + adls if not (OUT / f"{p.rsplit(chr(92), 1)[-1].rsplit('/', 1)[-1][:-4]}.npz").exists()]
    print(f"{len(falls)} falls, {len(adls)} everyday activities, {len(todo)} to extract", flush=True)
    with ProcessPoolExecutor(a.workers) as pool:
        for fut in as_completed([pool.submit(extract_one, p) for p in todo]):
            fut.result()
    spec = exercises.EXERCISES["march_in_place"]
    rows = []
    for kind, paths in (("fall", falls), ("adl", adls)):
        for p in paths:
            stem = p.replace("\\", "/").rsplit("/", 1)[-1][:-4]
            seq = landmarks.load(OUT / f"{stem}.npz")
            at = possible_fall(spec, Features(seq)) if seq.detected_ratio > 0 and len(seq.t) > 3 else None
            rows.append({"clip": stem, "kind": kind, "seconds": round(float(seq.t[-1]), 1) if len(seq.t) else 0,
                         "person_found": round(seq.detected_ratio, 2), "alert_at": at})
    falls_hit = [r for r in rows if r["kind"] == "fall" and r["alert_at"] is not None]
    adl_hit = [r for r in rows if r["kind"] == "adl" and r["alert_at"] is not None]
    n_f = sum(r["kind"] == "fall" for r in rows)
    n_a = sum(r["kind"] == "adl" for r in rows)
    report = {"falls_caught": f"{len(falls_hit)}/{n_f}", "false_alerts_on_everyday_activities": f"{len(adl_hit)}/{n_a}",
              "missed_falls": [r["clip"] for r in rows if r["kind"] == "fall" and r["alert_at"] is None],
              "false_alerts": [r["clip"] for r in adl_hit], "rows": rows}
    print(f"falls caught {len(falls_hit)}/{n_f}; false alerts on everyday activities {len(adl_hit)}/{n_a}")
    print("missed:", report["missed_falls"])
    print("false alerts:", report["false_alerts"])
    (REPORTS / "urfall_eval.json").write_text(json.dumps(report, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
