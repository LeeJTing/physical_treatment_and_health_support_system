"""Is a floor push-up refused as a Wall Push-Up? (20 Oct, laptop emulator test: a fitness7 floor push-up
filmed diagonally passed the wrong-exercise check for wall_push_up; its body was measured at 40 degrees
from horizontal, the limit for "upright" being 35.)

Measures the body angle (identity signature trunk_upright) of
  * every floor push-up of the fitness7 dataset (25 people x good/bad x front/side/diagonal), and
  * Elwin's wall push-up clips,
and how many of each the wall_push_up check lets through, with the current rules and with a limit of its
own for wall push-ups. Landmarks are cached in training/data/cache/fitness7 (same files as
evaluate_fitness7.py). Writes training/reports/wall_pushup_identity.json.

    ai_server\\.venv\\Scripts\\python training\\check_wall_pushup_identity.py [--workers 3]
"""
import argparse
import json
from concurrent.futures import ProcessPoolExecutor, as_completed

import numpy as np

from common import CACHE, DATA, REPORTS, cached_sequence, own_clips
from app.pose import landmarks
from app.pose.geometry import Features
from app.pose.identity import check, signature

ROOT = DATA / "public" / "fitness7" / "Dataset Exercise Quality-wise" / "push_up"
OUT = CACHE / "fitness7"


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
    ap.add_argument("--limit", type=float, default=55.0, help="the body-angle limit to try for wall push-ups")
    a = ap.parse_args()
    paths = sorted(ROOT.rglob("*.mp4"))
    with ProcessPoolExecutor(a.workers) as pool:
        for i, f in enumerate(as_completed([pool.submit(extract_one, str(p)) for p in paths]), 1):
            f.result()
            if i % 20 == 0:
                print(f"  extracted {i}/{len(paths)}", flush=True)
    floor = []
    for p in paths:
        view = p.parent.name                              # front / side / diagonal
        sig = signature(Features(landmarks.load(OUT / f"{p.stem}.npz")))
        floor.append({"clip": p.stem, "view": view, "trunk_upright": sig["trunk_upright"],
                      "passes_now": check("wall_push_up", sig) is None})
    wall = []
    for c in own_clips():
        if c.key == "wall_push_up" and c.name_ok and not c.problems and c.cache_path.exists():
            sig = signature(Features(cached_sequence(c)))
            wall.append({"clip": c.path.stem, "trunk_upright": sig["trunk_upright"],
                         "passes_now": check("wall_push_up", sig) is None})
    report = {"limit_tried": a.limit, "floor_push_ups": len(floor), "wall_push_ups": len(wall), "by_view": {}}
    for view in sorted({x["view"] for x in floor}):
        t = np.array([x["trunk_upright"] for x in floor if x["view"] == view and np.isfinite(x["trunk_upright"])])
        report["by_view"][view] = {
            "clips": int(sum(x["view"] == view for x in floor)),
            "trunk_upright_p50_p95_max": [round(float(v), 1) for v in np.percentile(t, [50, 95, 100])],
            "pass_now": int(sum(x["passes_now"] for x in floor if x["view"] == view)),
            "pass_with_limit": int(sum(x["passes_now"] and x["trunk_upright"] >= a.limit
                                       for x in floor if x["view"] == view)),
        }
    t = [x["trunk_upright"] for x in wall]
    report["wall_trunk_upright_min_max"] = [round(min(t), 1), round(max(t), 1)] if t else None
    report["wall_pass_now"] = sum(x["passes_now"] for x in wall)
    report["wall_pass_with_limit"] = sum(x["passes_now"] and x["trunk_upright"] >= a.limit for x in wall)
    REPORTS.mkdir(exist_ok=True)
    (REPORTS / "wall_pushup_identity.json").write_text(json.dumps(report, indent=1), encoding="utf-8")
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
