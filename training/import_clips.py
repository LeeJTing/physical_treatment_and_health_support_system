"""Copies recorded clips from folders named by label into training/data with the guide's names.

Source layout (as recorded):  <src>/<pose_key>/<correct | mistake label>/*.mp4
Result:  training/data/<pose_key>/<correct|incorrect>/<pose_key>__<correct|incorrect>__<ok|mistake>__<person>__<side>__NN.mp4
Originals are copied, never moved. A manifest (training/data/import_manifest.csv) records
which original became which file. Re-running skips clips already imported.

    ai_server\\.venv\\Scripts\\python training\\import_clips.py "C:\\Users\\KOH Family\\Desktop" --person p01
"""
import argparse
import csv
import shutil
from pathlib import Path

from common import DATA, VIDEO_EXT
from app.pose.exercises import EXERCISES

# Folder names that differ from the rule labels.
ALIASES = {"uneven_arm": "uneven_arms", "hand_used": "hands_used", "ok": "correct"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("--person", default="p01")
    ap.add_argument("--side", default="both")
    ap.add_argument("--skip", nargs="*", default=[],
                    help="<pose_key>/<label> folders to leave out, e.g. hip_abduction/trunk_lean (to be re-recorded)")
    a = ap.parse_args()
    src = Path(a.src)
    manifest = DATA / "import_manifest.csv"
    done = {}
    if manifest.exists():
        done = {r["original"]: r["imported"] for r in csv.DictReader(manifest.open(encoding="utf-8"))}
    rows = [{"original": k, "imported": v} for k, v in done.items()]
    counts = {}
    def key_of(name: str) -> str:  # "step-up", "Step Up" -> "step_up"
        return name.strip().lower().replace("-", "_").replace(" ", "_")

    for ex_dir in sorted(p for p in src.iterdir() if p.is_dir() and key_of(p.name) in EXERCISES):
        key = key_of(ex_dir.name)
        labels = {m.label for m in EXERCISES[key].mistakes}
        for lab_dir in sorted(p for p in ex_dir.iterdir() if p.is_dir()):
            label = ALIASES.get(lab_dir.name, lab_dir.name)
            if f"{key}/{lab_dir.name}" in a.skip or f"{key}/{label}" in a.skip:
                print(f"  {key}/{lab_dir.name}: skipped (--skip)")
                continue
            if label != "correct" and label not in labels:
                print(f"  WARNING {key}/{lab_dir.name}: not a rule label for {key} ({', '.join(sorted(labels))}); skipped")
                continue
            kind = "correct" if label == "correct" else "incorrect"
            mistake = "ok" if kind == "correct" else label
            out_dir = DATA / key / kind
            out_dir.mkdir(parents=True, exist_ok=True)
            for clip in sorted(p for p in lab_dir.iterdir() if p.suffix.lower() in VIDEO_EXT):
                if str(clip) in done:
                    continue
                stem = f"{key}__{kind}__{mistake}__{a.person}__{a.side}__"
                n = 1 + len(list(out_dir.glob(stem + "*")))
                dst = out_dir / f"{stem}{n:02d}{clip.suffix.lower()}"
                shutil.copy2(clip, dst)
                rows.append({"original": str(clip), "imported": str(dst)})
                counts[(key, mistake)] = counts.get((key, mistake), 0) + 1
    with manifest.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["original", "imported"])
        w.writeheader()
        w.writerows(rows)
    for (key, mistake), n in sorted(counts.items()):
        print(f"  {key:20s} {mistake:20s} {n:3d} imported")
    print(f"{sum(counts.values())} new clips; manifest {manifest}")


if __name__ == "__main__":
    main()
