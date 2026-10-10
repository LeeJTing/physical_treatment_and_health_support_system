"""Builds the exercise guide animations the app plays (11 Oct, Elwin agreed): one looping repetition
per exercise, made from our own correct recordings, not drawn by hand.

For each exercise: the clean repetitions of its correct clips (the app's own repetition detection, and
no mistake found by its rules) are resampled to the same length, and the frame-by-frame median of the
clip with the most clean repetitions is kept (one person, one camera, so no scaling between clips).
The loop is closed (last frame = first frame) and lightly smoothed. Side views are turned to face
right. Coordinates are scaled into a unit box with the props (floor, chair, wall, step, table).

    ai_server\\.venv\\Scripts\\python training\\build_guide_animations.py

Writes assets/guides/<pose_key>.json (about 5-10 KB each; read by the app's ExerciseAnimation) and a
preview strip per exercise in training/reports/guides/<pose_key>.png.
"""
import json
import sys
from pathlib import Path

import cv2
import numpy as np

from common import CACHE, DATA, REPORTS, own_clips
from app.pose import analyse as A
from app.pose import exercises as X
from app.pose import landmarks as L
from app.pose.geometry import Features

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "guides"
PREVIEW = REPORTS / "guides"
N = 40                       # frames per loop

# Body points drawn by the app (MediaPipe pose indices) and the lines between them.
BODY = {"nose": 0, "l_ear": 7, "r_ear": 8, "l_shoulder": 11, "r_shoulder": 12, "l_elbow": 13, "r_elbow": 14,
        "l_wrist": 15, "r_wrist": 16, "l_hip": 23, "r_hip": 24, "l_knee": 25, "r_knee": 26, "l_ankle": 27,
        "r_ankle": 28, "l_heel": 29, "r_heel": 30, "l_toe": 31, "r_toe": 32}
BODY_EDGES = [("l_shoulder", "r_shoulder"), ("l_hip", "r_hip"), ("l_shoulder", "l_hip"), ("r_shoulder", "r_hip"),
              ("l_shoulder", "l_elbow"), ("l_elbow", "l_wrist"), ("r_shoulder", "r_elbow"), ("r_elbow", "r_wrist"),
              ("l_hip", "l_knee"), ("l_knee", "l_ankle"), ("r_hip", "r_knee"), ("r_knee", "r_ankle"),
              ("l_ankle", "l_heel"), ("l_heel", "l_toe"), ("l_ankle", "l_toe"),
              ("r_ankle", "r_heel"), ("r_heel", "r_toe"), ("r_ankle", "r_toe")]
HAND = ["wrist", "thumb_cmc", "thumb_mcp", "thumb_ip", "thumb_tip", "index_mcp", "index_pip", "index_dip",
        "index_tip", "middle_mcp", "middle_pip", "middle_dip", "middle_tip", "ring_mcp", "ring_pip", "ring_dip",
        "ring_tip", "pinky_mcp", "pinky_pip", "pinky_dip", "pinky_tip"]
PALM = [0, 1, 5, 9, 13, 17]
HAND_EDGES = [(0, 1), (1, 2), (2, 3), (3, 4), (0, 5), (5, 6), (6, 7), (7, 8), (5, 9), (9, 10), (10, 11), (11, 12),
              (9, 13), (13, 14), (14, 15), (15, 16), (13, 17), (0, 17), (17, 18), (18, 19), (19, 20)]

SEATED = {"knee_extension", "seated_marching"}
CHAIR = SEATED | {"sit_to_stand"}
FLOOR_ONLY = {"glute_bridge", "bird_dog"}
STROKE = DATA / "public" / "stroke_upper_limb" / "Exercise"
HAND_SETS = {"wrist_extension": "3_Lifting the Wrist", "hand_open_close": "4_Opening the Hand"}


def fill_nan(a: np.ndarray) -> np.ndarray | None:
    """Linear interpolation over time for each coordinate; None when a point is missing too often."""
    a = a.copy()
    t = np.arange(len(a))
    flat = a.reshape(len(a), -1)
    for j in range(flat.shape[1]):
        ok = np.isfinite(flat[:, j])
        if ok.mean() < 0.6:
            return None
        flat[:, j] = np.interp(t, t[ok], flat[ok, j])
    return flat.reshape(a.shape)


def resample(a: np.ndarray, n: int = N) -> np.ndarray:
    src = np.linspace(0, 1, len(a))
    dst = np.linspace(0, 1, n)
    flat = a.reshape(len(a), -1)
    return np.stack([np.interp(dst, src, flat[:, j]) for j in range(flat.shape[1])], axis=1).reshape(
        (n,) + a.shape[1:])


def close_loop(a: np.ndarray) -> np.ndarray:
    """Spread the gap between the last and first frame over the loop, then smooth (wrapping round)."""
    gap = a[-1] - a[0]
    w = np.linspace(0, 1, len(a)).reshape((-1,) + (1,) * (a.ndim - 1))
    core = (a - gap * w)[:-1]                     # the last frame is the first again
    for _ in range(2):
        core = (np.roll(core, 1, axis=0) + 2 * core + np.roll(core, -1, axis=0)) / 4
    return np.concatenate([core, core[:1]])


def floor_to_floor(seq) -> list[tuple[int, int]]:
    """Step-Up: from standing on the floor to standing on the floor again (hips lowest), so the loop
    shows the walk onto the step and back; the app's repetition window starts on the step."""
    hip = np.nanmean(seq.xy[:, [23, 24], 1], axis=1)
    ok = np.isfinite(hip)
    if ok.sum() < 10:
        return []
    lo, hi = np.nanpercentile(hip, [10, 90])
    down = np.where(ok, hip > lo + 0.75 * (hi - lo), False)          # y grows downwards: on the floor
    centres, k = [], 0
    while k < len(down):
        if down[k]:
            j = k
            while j < len(down) and down[j]:
                j += 1
            centres.append((k + j - 1) // 2)
            k = j
        else:
            k += 1
    return [(a, b) for a, b in zip(centres, centres[1:]) if b - a >= 6]


def cycles(spec, f: Features) -> list[tuple[int, int]]:
    """Windows of clean repetitions; an alternating exercise's cycle is one lift of each side."""
    reps = [r for r in A.detect_reps(spec, f) if not r.unfinished]
    clean = [r for r in reps if not A.check_rep(spec, f, r)]
    if spec.side_signals is not None:
        # One lift of each side; when the far leg is not seen (side view), one side's lift to its next.
        out = []
        both = len({r.side for r in clean}) > 1
        for a, b in zip(clean, clean[1:]):
            length = a.end - a.start
            if both and a.side != b.side and b.start - a.end <= 2 * length:
                out.append((a.start, b.end))
            elif not both and b.start - a.start <= 5 * length:
                out.append((a.start, b.start))
        return out
    return [(r.start, r.end) for r in clean]


def body_animation(key: str):
    spec = X.EXERCISES[key]
    best = None
    for clip in own_clips([key]):
        if not clip.is_correct or not clip.cache_path.exists():
            continue
        seq = L.load(clip.cache_path)
        idx = list(BODY.values())
        if spec.kind == "hold":
            mid = seq.xy[len(seq.xy) // 4: 3 * len(seq.xy) // 4][:, idx]
            filled = fill_nan(mid)
            if filled is None:
                continue
            loops = [np.repeat(np.median(filled, axis=0)[None], N, axis=0)]
            durs = [4.0]
        else:
            f = Features(seq)
            loops, durs = [], []
            for s, e in (floor_to_floor(seq) if key == "step_up" else cycles(spec, f)):
                s, e = max(0, s - 1), min(len(seq.xy) - 1, e + 1)
                part = fill_nan(seq.xy[s:e + 1][:, idx])
                if part is None or len(part) < 4:
                    continue
                loops.append(resample(part))
                durs.append(float(seq.t[e] - seq.t[s]))
        if loops and (best is None or len(loops) > len(best[1])):
            best = (clip, loops, durs, seq)
    if best is None:
        return None
    clip, loops, durs, seq = best
    a = np.median(np.stack(loops), axis=0)
    a = close_loop(a) if spec.kind != "hold" else a
    names = list(BODY)
    i = {n: k for k, n in enumerate(names)}
    # Side views face right: the nose ahead of the ears.
    if spec.view == "side":
        ears = (a[0, i["l_ear"], 0] + a[0, i["r_ear"], 0]) / 2
        if a[0, i["nose"], 0] < ears:
            a[..., 0] = -a[..., 0]
    vis = seq.vis
    near = "left" if np.nanmean(vis[:, [11, 23, 25, 27]]) >= np.nanmean(vis[:, [12, 24, 26, 28]]) else "right"
    props = body_props(key, a, i)
    return {"names": names, "edges": [[i[p], i[q]] for p, q in BODY_EDGES], "frames": a, "props": props,
            "near": near if spec.view == "side" else None, "duration": float(np.median(durs)),
            "source": f"{len(loops)} clean repetitions of {clip.path.stem}"}


def body_props(key: str, a: np.ndarray, i: dict) -> list[np.ndarray]:
    """Lines drawn in grey behind the person, in the same coordinates."""
    feet = a[:, [i["l_heel"], i["r_heel"], i["l_toe"], i["r_toe"]]]
    floor = float(np.max(feet[..., 1]))
    xs = a[..., 0]
    lo, hi = float(xs.min()), float(xs.max())
    torso = float(np.median(np.linalg.norm(
        (a[:, i["l_shoulder"]] + a[:, i["r_shoulder"]]) / 2 - (a[:, i["l_hip"]] + a[:, i["r_hip"]]) / 2, axis=-1)))
    pad = 0.35 * torso
    props = [np.array([[lo - pad, floor], [hi + pad, floor]])]
    hip = (a[:, i["l_hip"]] + a[:, i["r_hip"]]) / 2
    if key in CHAIR:
        k = int(np.argmax(hip[:, 1]))                  # lowest hips = seated
        hx, hy = hip[k]
        knee = (a[k, i["l_knee"]] + a[k, i["r_knee"]]) / 2
        front = 1.0 if knee[0] > hx else -1.0
        seat_y = hy + 0.12 * torso
        back_x = hx - front * 0.45 * torso
        front_x = hx + front * 0.45 * torso
        props += [np.array([[back_x, seat_y], [front_x, seat_y]]),
                  np.array([[front_x, seat_y], [front_x, floor]]),
                  np.array([[back_x, floor], [back_x, seat_y], [back_x - front * 0.08 * torso, seat_y - 0.9 * torso]])]
    if key == "wall_push_up":
        wrists = a[:, [i["l_wrist"], i["r_wrist"]]]
        wx = float(np.max(wrists[..., 0])) + 0.05 * torso
        top = float(np.min(a[..., 1])) - 0.3 * torso
        props.append(np.array([[wx, top], [wx, floor]]))
    if key == "step_up":
        # The step is under the feet when the hips are highest (both feet on it).
        feet_i = [i["l_toe"], i["r_toe"], i["l_heel"], i["r_heel"]]
        k = int(np.argmin(hip[:, 1]))
        on = a[k, feet_i]
        step_y = float(np.median(on[:, 1]))      # heels and toes of both feet, robust to one lagging
        if floor - step_y > 0.08 * torso:
            x0, x1 = float(on[:, 0].min()) - 0.15 * torso, float(on[:, 0].max()) + 0.15 * torso
            props.append(np.array([[x0, floor], [x0, step_y], [x1, step_y], [x1, floor]]))
        print(f"  step_up: step height {floor - step_y:.1f} px, torso {torso:.1f} px")
    return props


def hand_animation(key: str):
    """The stroke dataset's complete cycles (seated at a table, close-up), the hand that moves."""
    spec = X.EXERCISES[key]
    best = None
    for p in sorted((STROKE / HAND_SETS[key] / "Complete").rglob("*.mp4")):
        cp = CACHE / "stroke" / ("wrist" if key == "wrist_extension" else "hand") / f"{p.parent.name}_{p.stem}.npz"
        if not cp.exists():
            continue
        seq = L.load(cp)
        if seq.hands is None:
            continue
        f = Features(seq)
        slot = X._moving_slot(f, "hand_lift" if key == "wrist_extension" else "hand_open")
        if slot is None:
            continue
        # The hand only: the body's elbow jumps in these close-ups (tried 11 Oct).
        filled = fill_nan(seq.hands[:, 0 if slot == "A" else 1])          # (T, 21, 2)
        if filled is None:
            continue
        # Every video is one cycle: the whole clip, from rest to rest.
        sig = spec.signal(f)
        ok = np.isfinite(sig)
        if ok.sum() < 6 or np.nanmax(sig) < spec.target:
            continue
        loop = resample(filled)
        score = float(np.nanmax(sig))
        if best is None or score > best[0]:
            best = (score, loop, float(seq.t[-1] - seq.t[0]), p)
    if best is None:
        return None
    _, a, dur, p = best
    a = close_loop(a)
    # Fingers up: the wrist below the middle knuckle.
    if np.median(a[:, 0, 1] - a[:, 9, 1]) < 0:
        a[..., 1] = -a[..., 1]
    if key == "wrist_extension" and np.median(a[:, 9, 0] - a[:, 0, 0]) < 0:
        a[..., 0] = -a[..., 0]                                           # hand to the right of the wrist
    props = []
    if key == "wrist_extension":
        y = float(np.max(a[:, 0, 1])) + 0.15 * float(np.median(np.linalg.norm(a[:, 9] - a[:, 0], axis=-1)))
        xs = a[..., 0]
        props.append(np.array([[float(xs.min()) - 0.6, y], [float(a[:, 0, 0].mean()) + 0.05, y]]))
    return {"names": HAND, "edges": [list(e) for e in HAND_EDGES], "frames": a,
            "props": props, "near": None, "fills": [PALM],
            "duration": min(max(dur, 2.0), 6.0), "source": f"complete cycle {p.parent.name}/{p.stem} (Upper Limb "
                                                         "Stroke Rehabilitation Exercise Video Dataset, CC BY 4.0)"}


def normalise(anim: dict) -> dict:
    """Scale into a unit box (longest side 1) with a small margin; y down, as on screen."""
    pts = [anim["frames"].reshape(-1, 2)] + [p for p in anim["props"]]
    allp = np.concatenate(pts)
    lo = allp.min(axis=0)
    span = allp.max(axis=0) - lo
    s = float(span.max()) * 1.08
    off = lo - (s - span) / 2
    anim["frames"] = (anim["frames"] - off) / s
    anim["props"] = [(p - off) / s for p in anim["props"]]
    return anim


def preview(key: str, anim: dict) -> None:
    PREVIEW.mkdir(parents=True, exist_ok=True)
    size, cols = 200, 8
    img = np.full((size, size * cols, 3), 255, np.uint8)
    for c, k in enumerate(np.linspace(0, N - 1, cols).round().astype(int)):
        ox = c * size
        for p in anim["props"]:
            q = (p * size).astype(int) + [ox, 0]
            cv2.polylines(img, [q.reshape(-1, 1, 2)], False, (180, 180, 180), 2)
        f = anim["frames"][k]
        for poly in anim.get("fills", []):
            q = np.array([[int(f[j][0] * size) + ox, int(f[j][1] * size)] for j in poly])
            cv2.fillPoly(img, [q], (120, 150, 60))
        for a_, b_ in anim["edges"]:
            pa = (int(f[a_][0] * size) + ox, int(f[a_][1] * size))
            pb = (int(f[b_][0] * size) + ox, int(f[b_][1] * size))
            cv2.line(img, pa, pb, (74, 103, 12), 3)
        if anim["names"][0] == "nose":
            cv2.circle(img, (int(f[0][0] * size) + ox, int(f[0][1] * size)), 9, (74, 103, 12), -1)
        cv2.putText(img, str(k), (ox + 6, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (90, 90, 90), 1)
    cv2.imwrite(str(PREVIEW / f"{key}.png"), img)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # Wrist Extension from the stroke dataset's side view is not readable (fingers on top of each other):
    # it waits for our own close-up clips (Recording_Guide_Fingers.pdf, part 6).
    keys = sys.argv[1:] or [k for k in X.EXERCISES if k != "wrist_extension"]
    for key in keys:
        spec = X.EXERCISES[key]
        anim = hand_animation(key) if key in A.HAND_EXERCISES else body_animation(key)
        if anim is None:
            print(f"{key:20} no clean correct repetitions found")
            continue
        anim = normalise(anim)
        data = {
            "key": key, "name": spec.name, "view": spec.view, "kind": "hand" if key in A.HAND_EXERCISES else "body",
            "hold": spec.kind == "hold", "near": anim["near"], "duration_sec": round(anim["duration"], 2),
            "names": anim["names"], "edges": anim["edges"], "fills": anim.get("fills", []),
            "frames": [[round(float(v), 3) for v in fr.ravel()] for fr in anim["frames"]],
            "props": [[round(float(v), 3) for v in p.ravel()] for p in anim["props"]],
            "source": anim["source"],
        }
        path = OUT / f"{key}.json"
        path.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
        preview(key, anim)
        print(f"{key:20} {path.stat().st_size / 1024:5.1f} KB  {data['duration_sec']:4.1f} s  {anim['source']}")


if __name__ == "__main__":
    main()
