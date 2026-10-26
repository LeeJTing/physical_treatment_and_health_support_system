"""Outside test on the sit2stand.ai videos (Boswell et al., npj Digital Medicine 2023; Stanford,
github.com/stanfordnmbl/sit2stand-analysis): 405 adults filmed the five-times sit-to-stand test at
home on their own phones (camera at about 45 degrees), de-identified videos shared for follow-up
studies. No licence file is given, so the videos stay in training/data (git-ignored), are used only
to test the app and are not shared.

There are no correct / incorrect labels. What this checks on strangers' home videos:
  * the person is tracked and the 5 repetitions are counted (their OpenPose pipeline found 5 in 373 of 405);
  * the possible-fall alert stays silent (nobody fell while recording);
  * how often each sit-to-stand mistake fires, by age group (18-49, 50-64, 65+) and for people who
    fell in the past year: rules that fire on most healthy people are too strict;
  * the elderly settings (rom_scale from age) and the dark / small-body tips.

    ai_server\\.venv\\Scripts\\python training\\evaluate_sit2stand.py [--workers 3] [--extract-only] [--cached-only]

Landmarks are cached in training/data/cache/sit2stand. Writes training/reports/sit2stand_eval.json.
"""
import argparse
import csv
import json
from collections import Counter, defaultdict
from concurrent.futures import ProcessPoolExecutor, as_completed

import numpy as np

from common import CACHE, DATA, REPORTS
from app.pose import exercises, landmarks
from app.pose.analyse import PoseError, analyse

ROOT = DATA / "public" / "sit2stand"
OUT = CACHE / "sit2stand"


def people() -> dict[str, dict]:
    """{video name: {age, fell, oa, time, their_reps}} for the 405 videos the study kept."""
    mv = list(csv.reader((ROOT / "dataMovement.csv").open(encoding="utf-8", errors="replace")))
    h = mv[0]
    by_x = {r[h.index("X")]: r[h.index("subjectid")] for r in mv[1:]}
    cl = list(csv.reader((ROOT / "dataClean.csv").open(encoding="utf-8", errors="replace")))
    h = cl[0]
    col = {c: h.index(c) for c in ("X", "Age", "Fall_YN", "OA_check", "time", "n_sit2stand")}
    out = {}
    for r in cl[1:]:
        name = by_x.get(r[col["X"]])
        if not name:
            continue

        def num(c):
            try:
                return float(r[col[c]])
            except ValueError:
                return None
        out[name] = {"age": num("Age"), "fell": r[col["Fall_YN"]] == "1", "oa": r[col["OA_check"]] == "1",
                     "time": num("time"), "their_reps": num("n_sit2stand")}
    return out


def brightness(path, samples=5):
    import cv2
    cap = cv2.VideoCapture(str(path))
    try:
        n = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        vals = []
        for i in range(samples):
            cap.set(cv2.CAP_PROP_POS_FRAMES, int(n * (i + 0.5) / samples))
            ok, frame = cap.read()
            if ok:
                vals.append(float(cv2.cvtColor(cv2.resize(frame, (160, 160)), cv2.COLOR_BGR2GRAY).mean()))
        return sum(vals) / len(vals) if vals else None
    finally:
        cap.release()


def extract_one(path_str: str) -> tuple[str, float]:
    from pathlib import Path
    path = Path(path_str)
    cp = OUT / f"{path.stem}.npz"
    if not cp.exists():
        seq = landmarks.extract(path)
        cp.parent.mkdir(parents=True, exist_ok=True)
        landmarks.save(seq, cp)
        return path.stem, seq.detected_ratio
    return path.stem, landmarks.load(cp).detected_ratio


def group(age):
    if age is None:
        return "unknown"
    return "65+" if age >= 65 else "50-64" if age >= 50 else "18-49"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--extract-only", action="store_true")
    ap.add_argument("--cached-only", action="store_true")
    a = ap.parse_args()
    meta = people()
    videos = sorted(p for p in (ROOT / "videos").glob("*.mp4") if p.stem in meta and p.stat().st_size > 10000)
    if not a.cached_only:
        todo = [v for v in videos if not (OUT / f"{v.stem}.npz").exists()]
        print(f"{len(videos)} videos of kept participants, {len(todo)} to extract", flush=True)
        with ProcessPoolExecutor(a.workers) as pool:
            futs = [pool.submit(extract_one, str(v)) for v in todo]
            for i, fut in enumerate(as_completed(futs), 1):
                try:
                    stem, ratio = fut.result()
                    print(f"[{i}/{len(todo)}] {stem}: person found in {ratio:.0%}", flush=True)
                except Exception as e:                      # a broken file must not stop the run
                    print(f"[{i}/{len(todo)}] failed: {e}", flush=True)
    if a.extract_only:
        return
    videos = [v for v in videos if (OUT / f"{v.stem}.npz").exists()]
    spec = exercises.EXERCISES["sit_to_stand"]
    labels = [m.label for m in spec.mistakes]
    rows = []
    for v in videos:
        p = meta[v.stem]
        seq = landmarks.load(OUT / f"{v.stem}.npz")
        scale = exercises.rom_scale_for(None, int(p["age"]) if p["age"] else None)
        row = {"video": v.stem, **p, "group": group(p["age"]), "found": round(seq.detected_ratio, 3),
               "rom_scale": scale}
        for mode, kw in (("full", {"rom_scale": 1.0}), ("own", {"rom_scale": scale})):
            try:
                res = analyse("sit_to_stand", seq, use_model=False, brightness=brightness(v), **kw)
            except PoseError as e:
                row[mode] = {"error": e.code if hasattr(e, "code") else str(e)}
                continue
            mistakes = res.get("mistakes", {})
            row[mode] = {"reps": res["repetitions"], "accuracy": res["accuracy"],
                         "fall": "safety_alert" in res, "partial": bool(res.get("partial_repetitions")),
                         "tips": len(res.get("quality_tips", [])) if isinstance(res.get("quality_tips"), list) else 0,
                         "mistake_reps": {k: mistakes.get(k, 0) for k in labels}}
        rows.append(row)

    report = {"videos": len(rows), "by_group": {}, "notes": __doc__.split("\n\n")[0]}
    for mode in ("full", "own"):
        for g in ("all", "18-49", "50-64", "65+", "fell in past year"):
            sel = [r for r in rows if mode in r and "error" not in r[mode] and
                   (g == "all" or r["group"] == g or (g == "fell in past year" and r["fell"]))]
            if not sel:
                continue
            reps = np.array([r[mode]["reps"] for r in sel])
            total = int(reps.sum())
            fired = {k: round(sum(r[mode]["mistake_reps"][k] for r in sel) / max(total, 1), 3) for k in labels}
            report["by_group"].setdefault(mode, {})[g] = {
                "videos": len(sel),
                "exact_5": round(float(np.mean(reps == 5)), 3),
                "within_1": round(float(np.mean(np.abs(reps - 5) <= 1)), 3),
                "reps_median": float(np.median(reps)),
                "false_fall_alerts": int(sum(r[mode]["fall"] for r in sel)),
                "partial": int(sum(r[mode]["partial"] for r in sel)),
                "accuracy_median": float(np.median([r[mode]["accuracy"] for r in sel])),
                "mistake_share_of_reps": fired,
            }
    errors = Counter(r[m]["error"] for r in rows for m in ("full", "own") if m in r and "error" in r[m])
    report["errors"] = dict(errors)
    for mode, groups in report["by_group"].items():
        print(f"== {mode} targets")
        for g, s in groups.items():
            print(f"  {g:18s} {s['videos']:3d} videos  5 reps {s['exact_5']:.0%}  within 1 {s['within_1']:.0%}  "
                  f"falls {s['false_fall_alerts']}  partial {s['partial']}  accuracy {s['accuracy_median']:.0f}")
            print("     mistakes per rep:", {k: v for k, v in s["mistake_share_of_reps"].items() if v})
    print("errors:", dict(errors))
    report["rows"] = rows
    (REPORTS / "sit2stand_eval.json").write_text(json.dumps(report, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
