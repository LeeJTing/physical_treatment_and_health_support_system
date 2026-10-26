"""Wrist extension and hand open/close (9 Oct, Elwin chose to add them) on the Upper Limb Stroke
Rehabilitation Exercise Video Dataset (Mendeley Data 49h9dcwx5v v1, CC BY 4.0): 10 volunteers seated at
a table, "3_Lifting the Wrist" (forearm resting on a book, hand over the edge, filmed side-on) and
"4_Opening the Hand" (fist to open fingers, filmed from the front); every video is one exercise cycle,
marked Complete or Incomplete (difficulty or early stop).

    ai_server\\.venv\\Scripts\\python training\\evaluate_wrist_hand.py [--workers 3] [--extract-only]

Landmarks (body + both hands) are cached in training/data/cache/stroke. Prints the signals of complete
and incomplete cycles, from which the levels in exercises.py are set, then (once the exercises exist)
how the app's analysis does on them. Writes training/reports/wrist_hand_eval.json.
"""
import argparse
import json
from concurrent.futures import ProcessPoolExecutor, as_completed

import numpy as np

from common import CACHE, DATA, REPORTS
from app.pose import landmarks

ROOT = DATA / "public" / "stroke_upper_limb" / "Exercise"
OUT = CACHE / "stroke"
SETS = {"wrist": "3_Lifting the Wrist", "hand": "4_Opening the Hand"}


def videos():
    for kind, folder in SETS.items():
        for label in ("Complete", "Incomplete"):
            for p in sorted((ROOT / folder / label).rglob("*.mp4")):
                yield kind, label, p


def extract_one(path_str: str, kind: str) -> str:
    from pathlib import Path
    path = Path(path_str)
    cp = OUT / kind / f"{path.parent.name}_{path.stem}.npz"
    if not cp.exists():
        seq = landmarks.extract_with_hands(path)
        cp.parent.mkdir(parents=True, exist_ok=True)
        landmarks.save(seq, cp)
    return path.stem


def cache_of(kind, p):
    return OUT / kind / f"{p.parent.name}_{p.stem}.npz"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--extract-only", action="store_true")
    a = ap.parse_args()
    todo = [(k, p) for k, _, p in videos() if not cache_of(k, p).exists()]
    print(f"{len(todo)} videos to extract", flush=True)
    if todo:
        with ProcessPoolExecutor(a.workers) as pool:
            futs = [pool.submit(extract_one, str(p), k) for k, p in todo]
            for i, fut in enumerate(as_completed(futs), 1):
                try:
                    fut.result()
                except Exception as e:
                    print("failed:", e, flush=True)
                if i % 20 == 0:
                    print(f"  {i}/{len(todo)}", flush=True)
    if a.extract_only:
        return
    from app.pose.analyse import PoseError, analyse
    report = {}
    for kind, key in (("wrist", "wrist_extension"), ("hand", "hand_open_close")):
        rows = []
        for k, label, p in videos():
            if k != kind:
                continue
            seq = landmarks.load(cache_of(kind, p))
            try:
                res = analyse(key, seq, use_model=False)
                rows.append({"video": p.stem, "label": label, "reps": res["repetitions"], "accuracy": res["accuracy"],
                             "mistakes": res["mistakes"], "partial": bool(res.get("partial_repetitions"))})
            except PoseError as e:
                rows.append({"video": p.stem, "label": label, "error": e.code})
        for label in ("Complete", "Incomplete"):
            sel = [r for r in rows if r["label"] == label]
            ok = [r for r in sel if "error" not in r]
            print(f"{key:16s} {label:10s} {len(sel):3d} videos | evidence (>=1 rep) {sum(r['reps'] >= 1 for r in ok)} "
                  f"| full reps {sum(not r['partial'] for r in ok)} | passed (>=80) {sum(r['accuracy'] >= 80 for r in ok)} "
                  f"| errors {dict((e, sum(1 for r in sel if r.get('error') == e)) for e in {r.get('error') for r in sel} if e)}")
        report[key] = rows
    (REPORTS / "wrist_hand_eval.json").write_text(json.dumps(report, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
