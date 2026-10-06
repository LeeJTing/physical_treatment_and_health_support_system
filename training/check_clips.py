"""Checks every recorded clip while recording is still going on.

For each clip: file name and folder, length, resolution and orientation,
whether the pose detector sees the whole body, how many repetitions were
found and how long each takes, and which rule mistakes fire. Problems are
listed so a clip can be re-recorded straight away.

    ai_server\\.venv\\Scripts\\python training\\check_clips.py            (all exercises)
    ai_server\\.venv\\Scripts\\python training\\check_clips.py sit_to_stand

Writes training/reports/clip_check.csv.
"""
import csv
import sys
from collections import Counter

import numpy as np

from common import REPORTS, cached_sequence, own_clips
from app.pose.analyse import PoseError, analyse, detect_reps
from app.pose.exercises import EXERCISES
from app.pose.geometry import Features


def check(clip) -> dict:
    row = {"exercise": clip.key, "file": clip.path.name, "label": clip.label or clip.folder_label,
           "mistake": clip.mistake, "person": clip.person, "side": clip.side}
    problems = list(clip.problems)
    try:
        seq = cached_sequence(clip)
    except Exception as e:  # unreadable file
        row.update(status="FAIL", problems=f"cannot read video: {e}")
        return row
    info = seq.info
    portrait = info.height >= info.width
    row.update(seconds=round(info.duration_sec, 1), resolution=f"{info.width}x{info.height}",
               fps=round(info.fps, 1), detected=round(seq.detected_ratio, 2))
    if min(info.width, info.height) < 720:
        problems.append("resolution below 720p")
    if not portrait:  # fine for training (angles do not depend on it); the guide asks for portrait
        row["note"] = "landscape video"
    if info.duration_sec < 10:
        problems.append("shorter than 10 s")
    spec = EXERCISES.get(clip.key)
    if spec is not None and seq.detected_ratio > 0:
        f = Features(seq)
        row["visible"] = round(float(np.mean(f.visible(spec.required, either_side=spec.view == "side"))), 2)
        if spec.kind == "reps":
            reps = detect_reps(spec, f)
            row["reps_found"] = len(reps)
            if reps:
                row["sec_per_rep"] = round(float(np.median([f.t[r.end] - f.t[r.start] for r in reps])), 1)
            if len(reps) < 2:
                problems.append(f"only {len(reps)} repetition(s) found; the movement may be too small, "
                                "or the camera angle is wrong for this exercise")
        try:
            res = analyse(clip.key, seq, use_model=False)
            row["accuracy"] = res["accuracy"]
            row["rule_mistakes"] = " ".join(f"{k}x{v}" for k, v in res["mistakes"].items())
            if clip.is_correct and res["mistakes"]:
                row["note"] = (row.get("note") + "; " if row.get("note") else "") + "rules flagged a correct clip (thresholds to tune, or a real mistake)"
            elif not clip.is_correct and clip.mistake and clip.mistake not in res["mistakes"]:
                row["note"] = (row.get("note") + "; " if row.get("note") else "") + f"rules did not catch '{clip.mistake}' (threshold to tune)"
        except PoseError as e:
            problems.append(e.message)
    row["status"] = "FAIL" if any(p for p in problems if "threshold" not in p) else "OK"
    row["problems"] = "; ".join(problems)
    return row


def main():
    keys = sys.argv[1:] or None
    clips = own_clips(keys)
    if not clips:
        print("No clips found under training/data/<exercise>/<correct|incorrect>/.")
        return
    rows = []
    for i, clip in enumerate(clips, 1):
        print(f"[{i}/{len(clips)}] {clip.key}/{clip.folder_label}/{clip.path.name} ...", flush=True)
        rows.append(check(clip))
    REPORTS.mkdir(exist_ok=True)
    cols = ["status", "exercise", "file", "label", "mistake", "person", "side", "seconds", "resolution", "fps",
            "detected", "visible", "reps_found", "sec_per_rep", "accuracy", "rule_mistakes", "note", "problems"]
    out = REPORTS / "clip_check.csv"
    with out.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)

    print("\n=== Summary ===")
    by_ex = Counter((r["exercise"], r["label"]) for r in rows)
    for (ex, label), n in sorted(by_ex.items()):
        print(f"  {ex:20s} {label:9s} {n:3d} clips")
    bad = [r for r in rows if r["status"] == "FAIL"]
    print(f"\n{len(rows) - len(bad)} OK, {len(bad)} with problems")
    for r in bad:
        print(f"  {r['exercise']}/{r['file']}: {r['problems']}")
    print(f"\nFull table: {out}")


if __name__ == "__main__":
    main()
