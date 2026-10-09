"""Shows what the posture check saw (9 Oct, Elwin: "I want to see the evidence that MediaPipe detected
the landmarks from the video and came up with the result"). Runs the same steps as /pose on a video
(landmarks.extract_parallel, then analyse with the trained model) and writes:

  <name>_annotated.mp4  every analysed frame (10 per second) with the 33 body points MediaPipe found
                       (green = confident, orange = unsure, missing = not found), the hands for the
                       hand exercises, the measured signal, a repetition counter, each repetition's
                       verdict as it ends, and the final result;
  <name>_summary.png   the frame at the top of each repetition with its skeleton, the signal over
                       time with the start / count levels and each repetition shaded green (no
                       mistake) or red (mistake), and the result the app shows.

    ai_server\\.venv\\Scripts\\python training\\visualize_pose.py <video> <exercise_key>
        [--risk HIGH] [--age 78] [--out training/reports/visual]
"""
import argparse
import json
from pathlib import Path

import cv2
import numpy as np

from common import REPORTS
from app.pose import exercises
from app.pose.analyse import PoseError, analyse, rep_levels
from app.pose.exercises import EXERCISES
from app.pose.geometry import Features
from app.pose.landmarks import extract_parallel, read_video_info

# MediaPipe's 33-point body skeleton.
BODY = [(0, 1), (1, 2), (2, 3), (3, 7), (0, 4), (4, 5), (5, 6), (6, 8), (9, 10), (11, 12), (11, 13), (13, 15),
        (15, 17), (15, 19), (15, 21), (17, 19), (12, 14), (14, 16), (16, 18), (16, 20), (16, 22), (18, 20),
        (11, 23), (12, 24), (23, 24), (23, 25), (24, 26), (25, 27), (26, 28), (27, 29), (28, 30), (29, 31),
        (30, 32), (27, 31), (28, 32)]
HAND = [(0, 1), (1, 2), (2, 3), (3, 4), (0, 5), (5, 6), (6, 7), (7, 8), (5, 9), (9, 10), (10, 11), (11, 12),
        (9, 13), (13, 14), (14, 15), (15, 16), (13, 17), (0, 17), (17, 18), (18, 19), (19, 20)]
GREEN, ORANGE, RED, WHITE, DARK = (80, 200, 80), (0, 165, 255), (60, 60, 230), (255, 255, 255), (30, 30, 30)
SIGNAL_NAMES = {"knees": "knee angle (deg)", "arm_elev": "arm raise (deg)", "arm_elev_max": "arm raise (deg)",
                "leg_raise": "leg out to the side (deg)", "knee_ext": "knee straightening (deg)",
                "elbow_flex": "elbow bend (deg)", "heel_lift": "heel lift (shin lengths)",
                "squat_depth": "knee bend (deg)", "bridge": "hip lift", "hip_rise": "hip rise",
                "hand_lift": "hand lift (deg)", "hand_open": "hand openness"}


def signal_of(spec, f):
    """The series the repetitions are counted on, and its name."""
    if spec.signal is not None:
        return spec.signal(f), SIGNAL_NAMES.get(spec.signal.__name__, spec.signal.__name__)
    if spec.side_signals is not None:
        sides = spec.side_signals(f)
        return np.nanmax(np.stack(list(sides.values())), axis=0), "lift (higher side)"
    return None, None


def draw_skeleton(img, pts, vis, scale, pairs=BODY, thick=3):
    for a, b in pairs:
        if a < len(pts) and b < len(pts) and np.isfinite(pts[[a, b]]).all():
            ok = vis is None or min(vis[a], vis[b]) > 0.5
            cv2.line(img, tuple((pts[a] * scale).astype(int)), tuple((pts[b] * scale).astype(int)),
                     WHITE if ok else ORANGE, thick, cv2.LINE_AA)
    for j, p in enumerate(pts):
        if np.isfinite(p).all():
            colour = GREEN if vis is None or vis[j] > 0.5 else ORANGE
            cv2.circle(img, tuple((p * scale).astype(int)), thick + 2, colour, -1, cv2.LINE_AA)


def banner(img, lines, colour=DARK, top=True):
    h = 30 * len(lines) + 12
    y0 = 0 if top else img.shape[0] - h
    overlay = img.copy()
    cv2.rectangle(overlay, (0, y0), (img.shape[1], y0 + h), colour, -1)
    cv2.addWeighted(overlay, 0.7, img, 0.3, 0, img)
    for k, text in enumerate(lines):
        cv2.putText(img, text, (12, y0 + 30 + 30 * k), cv2.FONT_HERSHEY_SIMPLEX, 0.75, WHITE, 2, cv2.LINE_AA)


def frames_at(path, times, src_fps):
    """The video frames nearest to the analysed times, in order."""
    want = {int(round(t * src_fps)): k for k, t in enumerate(times)}
    cap = cv2.VideoCapture(str(path))
    idx, out = 0, {}
    last = max(want) if want else -1
    while idx <= last:
        if idx in want:
            ok, frame = cap.read()
            if not ok:
                break
            out[want[idx]] = frame
        elif not cap.grab():
            break
        idx += 1
    cap.release()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("exercise_key", choices=sorted(EXERCISES))
    ap.add_argument("--risk")
    ap.add_argument("--age", type=int)
    ap.add_argument("--out", default=str(REPORTS / "visual"))
    a = ap.parse_args()
    spec = EXERCISES[a.exercise_key]
    path = Path(a.video)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    name = f"{path.stem}__{a.exercise_key}"

    info = read_video_info(path)
    seq, brightness = extract_parallel(path, hands=a.exercise_key in {"wrist_extension", "hand_open_close"})
    found = int(np.isfinite(seq.xy[:, 0, 0]).sum())
    print(f"{path.name}: {info.width}x{info.height}, {info.duration_sec:.1f} s at {info.fps:.0f} fps -> "
          f"{len(seq.t)} frames analysed, a body found in {found} ({found / max(1, len(seq.t)):.0%})")
    rom = exercises.rom_scale_for(a.risk, a.age)
    try:
        result = analyse(a.exercise_key, seq, rom_scale=rom, brightness=brightness)
        error = None
    except PoseError as e:
        result, error = None, e
    f = Features(seq)
    sig, sig_name = signal_of(spec, f)
    reps = result["rep_details"] if result else []
    (out / f"{name}_result.json").write_text(json.dumps(result if result else {"error": error.code,
                                                                               "message": error.message},
                                                        indent=2), encoding="utf-8")

    # ---- annotated video -------------------------------------------------------------------------
    frames = frames_at(path, seq.t, info.fps or 30.0)
    first = next(iter(frames.values()))
    scale = 960.0 / max(first.shape[:2])
    size = (int(first.shape[1] * scale), int(first.shape[0] * scale))
    writer = cv2.VideoWriter(str(out / f"{name}_annotated.mp4"), cv2.VideoWriter_fourcc(*"mp4v"),
                             max(1.0, seq.fps), size)
    if result:
        final = [f"RESULT: accuracy {result['accuracy']:.0f}%  repetitions {result['repetitions']}"
                 f"  ({'pass' if result['accuracy'] >= 80 else 'below 80, retry'})"] + \
                [t[:70] for t in result["feedback"][:3]]
    else:
        final = [f"NOT ANALYSED: {error.code}", error.message[:70], error.message[70:140]]
    for k, t in enumerate(seq.t):
        frame = frames.get(k)
        if frame is None:
            continue
        img = cv2.resize(frame, size)
        if np.isfinite(seq.xy[k]).any():
            draw_skeleton(img, seq.xy[k], seq.vis[k], scale)
        if seq.hands is not None:
            for hand in seq.hands[k]:
                if np.isfinite(hand).any():
                    draw_skeleton(img, hand, None, scale, HAND, 2)
        done = [r for r in reps if r["end_sec"] <= t + 1e-6]
        current = next((r for r in reps if r["start_sec"] <= t <= r["end_sec"]), None)
        n_vis = int((seq.vis[k] > 0.5).sum())
        lines = [f"{spec.name}   t = {t:4.1f} s   MediaPipe: {n_vis}/33 points confident"
                 if np.isfinite(seq.xy[k]).any() else f"{spec.name}   t = {t:4.1f} s   MediaPipe: no body found"]
        if sig is not None and np.isfinite(sig[k]):
            lines.append(f"{sig_name}: {sig[k]:.1f}    repetitions counted: {len(done)}")
        colour = DARK
        if current is not None:
            colour = (40, 110, 40) if not current["mistakes"] else (40, 40, 150)
            lines.append(f"in repetition {reps.index(current) + 1}")
        recent = [r for r in done if t - r["end_sec"] < 1.5]
        if recent:
            r = recent[-1]
            lines.append(f"rep {reps.index(r) + 1}: " + ("good" if not r["mistakes"] else ", ".join(r["mistakes"]))
                         + f"  (score {r['score']:.0f})")
        banner(img, lines, colour)
        if k >= len(seq.t) - 25:                      # the last 2.5 s show the result
            banner(img, final, (60, 60, 60), top=False)
        writer.write(img)
    for _ in range(int(3 * max(1.0, seq.fps))):     # hold the result for 3 s
        writer.write(img)
    writer.release()

    # ---- summary picture ---------------------------------------------------------------------------
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    peaks = []
    for r in reps[:6]:
        idx = np.where((seq.t >= r["start_sec"]) & (seq.t <= r["end_sec"]))[0]
        if len(idx):
            k = int(idx[np.nanargmax(sig[idx])]) if sig is not None and np.isfinite(sig[idx]).any() else int(idx[len(idx) // 2])
            peaks.append((k, r))
    if not peaks:
        peaks = [(int(len(seq.t) * q), None) for q in (0.2, 0.5, 0.8)]
    fig = plt.figure(figsize=(max(12, 2.8 * len(peaks)), 9))
    grid = fig.add_gridspec(2, max(3, len(peaks)), height_ratios=[1.3, 1])
    for c, (k, r) in enumerate(peaks):
        ax = fig.add_subplot(grid[0, c])
        frame = frames.get(k)
        if frame is not None:
            img = cv2.resize(frame, size)
            if np.isfinite(seq.xy[k]).any():
                draw_skeleton(img, seq.xy[k], seq.vis[k], scale)
            if seq.hands is not None:
                for hand in seq.hands[k]:
                    if np.isfinite(hand).any():
                        draw_skeleton(img, hand, None, scale, HAND, 2)
            pts = seq.xy[k][np.isfinite(seq.xy[k]).all(axis=1)] * scale
            if seq.hands is not None and np.isfinite(seq.hands[k]).any():
                hp = seq.hands[k].reshape(-1, 2)
                pts = np.concatenate([pts, hp[np.isfinite(hp).all(axis=1)] * scale])
            if len(pts):                               # crop to the person, so the points are visible
                (x0, y0), (x1, y1) = pts.min(axis=0), pts.max(axis=0)
                pad = 0.25 * max(x1 - x0, y1 - y0)
                x0, y0 = int(max(0, x0 - pad)), int(max(0, y0 - pad))
                x1, y1 = int(min(img.shape[1], x1 + pad)), int(min(img.shape[0], y1 + pad))
                img = img[y0:y1, x0:x1]
            ax.imshow(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
        title = f"t = {seq.t[k]:.1f} s"
        if r is not None:
            ms = r["mistakes"]
            title = f"rep {reps.index(r) + 1} top, {title}\n" + ("good" if not ms else "\n".join(
                ", ".join(ms[i:i + 2]) for i in range(0, len(ms), 2)))
        ax.set_title(title, fontsize=10, color="green" if r is not None and not r["mistakes"] else "black")
        ax.axis("off")
    ax = fig.add_subplot(grid[1, :])
    if sig is not None:
        ax.plot(seq.t, sig, color="black", lw=1.5, label=sig_name)
        rest, active = rep_levels(spec, sig) if spec.signal is not None else (spec.rest, spec.active)
        ax.axhline(rest, color="grey", ls="--", lw=1, label=f"start level {rest:.1f}")
        ax.axhline(active, color="blue", ls=":", lw=1, label=f"count level {active:.1f}")
    for r in reps:
        ax.axvspan(r["start_sec"], r["end_sec"], color="green" if not r["mistakes"] else "red", alpha=0.15)
        ax.text((r["start_sec"] + r["end_sec"]) / 2, ax.get_ylim()[1], f"{reps.index(r) + 1}", ha="center",
                va="top", fontsize=11)
    found_line = np.isfinite(seq.xy[:, 0, 0])
    ax.plot(seq.t[~found_line], np.full((~found_line).sum(), ax.get_ylim()[0]), "x", color="red",
            label="no body found")
    ax.set_xlabel("time (s)")
    ax.legend(loc="upper right", fontsize=8)
    head = (f"{spec.name}: {path.name}   {len(seq.t)} frames analysed, body found in {found}   "
            f"targets x{rom:g}")
    body = ("   ".join(final[:2]) if result else f"{error.code}: {error.message}")
    ax.set_title(f"{head}\n{body}", fontsize=10, loc="left")
    fig.tight_layout()
    fig.savefig(out / f"{name}_summary.png", dpi=110)
    plt.close(fig)
    print(f"  result: {final[0]}")
    print(f"  written {out / (name + '_annotated.mp4')}, {out / (name + '_summary.png')}, {name}_result.json")


if __name__ == "__main__":
    main()
