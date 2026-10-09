"""Does a smaller upload change the posture result? (9 Oct, NFR_07: result within 10 s)

The upload through the tunnel is most of the waiting time (25 s clip: ~4 s on the server, ~11 s in
all). The app records 720p with Android's default bitrate. Each sampled own clip (1080p, 20 Mbps
originals) is re-encoded to 720p H.264 without sound at 5, 2.5 and 1.5 Mbps, then run through the /pose
path: landmarks.extract_parallel (2 threads, as the server) + analyse(). The 5 Mbps version is the
reference. Reports, per bitrate: pass / fail agreement, accuracy difference, repetition difference,
errors, and the file size (upload time at 10 Mbit/s up).

Caveat: x264 here, the phone's hardware encoder there; at the same bitrate a phone's encoder is usually a
little worse, so the lowest bitrate that agrees here is not the one to use: take one step above it.

    ai_server\\.venv\\Scripts\\python training\\experiment_bitrate.py --ffmpeg <ffmpeg.exe> [--per-label 6]

Writes training/reports/bitrate_eval.json.
"""
import argparse
import json
import subprocess
import tempfile
import time
from collections import defaultdict
from pathlib import Path

from common import REPORTS, own_clips
from app.pose.analyse import PoseError, analyse
from app.pose.landmarks import extract_parallel

PASS = 80.0
KEYS = ["sit_to_stand", "shoulder_abduction", "shoulder_flexion", "hip_abduction", "knee_extension"]
RATES = [5000, 2500, 1500]  # kbit/s
SCALE = "scale='if(gt(iw,ih),-2,720)':'if(gt(iw,ih),720,-2)'"  # 720p, portrait or landscape


def encode(ffmpeg: str, src: Path, dst: Path, kbps: int) -> float:
    t = time.perf_counter()
    subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-i", str(src), "-vf", SCALE, "-an",
                    "-c:v", "libx264", "-preset", "veryfast", "-threads", "3",
                    "-b:v", f"{kbps}k", "-maxrate", f"{kbps}k", "-bufsize", f"{2 * kbps}k",
                    "-movflags", "+faststart", str(dst)], check=True)
    return time.perf_counter() - t


def score(key: str, path: Path) -> dict:
    t = time.perf_counter()
    try:
        seq, brightness = extract_parallel(path, workers=2)
        r = analyse(key, seq, use_model=True, brightness=brightness)
        out = {"acc": r["accuracy"], "reps": r["repetitions"], "mistakes": sorted(r["mistakes"])}
    except PoseError as e:
        out = {"error": e.code}
    out["sec"] = round(time.perf_counter() - t, 2)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ffmpeg", required=True)
    ap.add_argument("--per-label", type=int, default=6, help="clips per exercise and label")
    a = ap.parse_args()

    clips = []
    for key in KEYS:
        mine = [c for c in own_clips([key]) if c.name_ok]
        for label in (True, False):
            clips += [c for c in mine if c.is_correct == label][: a.per_label]
    rows = []
    with tempfile.TemporaryDirectory() as tmp:
        for i, c in enumerate(clips, 1):
            row = {"clip": c.path.name, "key": c.key, "correct": c.is_correct, "by_rate": {}}
            for kbps in RATES:
                dst = Path(tmp) / f"{kbps}.mp4"
                enc = encode(a.ffmpeg, c.path, dst, kbps)
                res = score(c.key, dst)
                res["mb"] = round(dst.stat().st_size / 1e6, 2)
                res["encode_sec"] = round(enc, 1)
                row["by_rate"][kbps] = res
            rows.append(row)
            short = {k: (v.get("acc"), v.get("reps"), v.get("error"), v["mb"]) for k, v in row["by_rate"].items()}
            print(f"[{i}/{len(clips)}] {c.path.name}: {short}", flush=True)

    ref = RATES[0]
    summary = {}
    for kbps in RATES:
        agree = acc_diff = rep_diff = errors = n = 0
        mb = []
        per_key = defaultdict(lambda: [0, 0])
        for r in rows:
            x, y = r["by_rate"][ref], r["by_rate"][kbps]
            mb.append(y["mb"])
            if "error" in y:
                errors += 1
            if "error" in x or "error" in y:
                same = x.get("error") == y.get("error")
            else:
                same = (x["acc"] >= PASS) == (y["acc"] >= PASS)
                acc_diff += abs(x["acc"] - y["acc"])
                rep_diff += abs(x["reps"] - y["reps"])
                n += 1
            agree += same
            per_key[r["key"]][0] += same
            per_key[r["key"]][1] += 1
        summary[f"{kbps} kbit/s"] = {
            "verdict_agrees_with_5000": f"{agree}/{len(rows)}",
            "mean_abs_accuracy_diff": round(acc_diff / max(n, 1), 2),
            "mean_abs_rep_diff": round(rep_diff / max(n, 1), 2),
            "errors": errors,
            "mean_mb": round(sum(mb) / len(mb), 2),
            "upload_sec_at_10_mbit": round(sum(mb) / len(mb) * 8 / 10, 1),
            "per_exercise": {k: f"{v[0]}/{v[1]}" for k, v in per_key.items()},
        }
    print(json.dumps(summary, indent=2))
    REPORTS.mkdir(parents=True, exist_ok=True)
    (REPORTS / "bitrate_eval.json").write_text(json.dumps({"summary": summary, "rows": rows}, indent=1))


if __name__ == "__main__":
    main()
