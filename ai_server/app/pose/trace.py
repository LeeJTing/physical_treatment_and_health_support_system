"""Step-by-step record of one posture check, for the development viewer only (9 Oct, Elwin: "a platform
where I can see the process when I want to, only in the development stage").

trace() reruns the same steps analyse() takes and keeps what each one saw: the frames MediaPipe found a
body in, the measured signal and the repetition levels, the repetitions, the right-exercise check (each
signature value against its limit), every posture rule on every repetition (value against limit) and
the trained model's verdicts. analyse() itself gives the result, so the trace never differs from what
the app was told. save_run() / load_run() keep a run on disk (DEV_TOOLS only, see config.py).
"""
import json
import shutil
import time
from dataclasses import replace
from datetime import datetime
from pathlib import Path

import numpy as np

from . import classifier, identity
from .analyse import (HAND_EXERCISES, PoseError, analyse, check_rep, detect_reps, possible_fall, rep_levels,
                      side_view_ratio)
from .exercises import EXERCISES
from .geometry import Features
from .landmarks import PoseSequence, load, save


def _num(x) -> float | None:
    x = float(x)
    return round(x, 3) if np.isfinite(x) else None


# The measured series the repetitions are counted on, in words.
SIGNAL_NAMES = {"knees": "knee angle (deg)", "arm_elev": "arm raise (deg)", "arm_elev_max": "arm raise (deg)",
                "leg_raise": "leg out to the side (deg)", "knee_ext": "knee straightening (deg)",
                "elbow_flex": "elbow bend (deg)", "heel_lift": "heel lift (shin lengths)",
                "squat_depth": "knee bend (deg)", "bridge": "hip lift", "hip_rise": "hip rise (torso lengths)",
                "hand_lift": "hand lift (deg)", "hand_open": "hand openness (palm lengths)"}


def _signal(spec, f: Features):
    if spec.signal is not None:
        return spec.signal(f), SIGNAL_NAMES.get(spec.signal.__name__, spec.signal.__name__)
    if spec.side_signals is not None:
        sides = spec.side_signals(f)
        return np.nanmax(np.stack(list(sides.values())), axis=0), "higher side of " + "/".join(sides)
    return None, None


def trace(key: str, seq: PoseSequence, rom_scale: float = 1.0, brightness: float | None = None,
          timings: dict | None = None) -> dict:
    spec = EXERCISES[key]
    t0 = time.perf_counter()
    try:
        result, error = analyse(key, seq, rom_scale=rom_scale, brightness=brightness), None
    except PoseError as e:
        result, error = None, {"code": e.code, "message": e.message}
    t_analyse = time.perf_counter() - t0

    f = Features(seq)
    found = np.isfinite(seq.xy[:, 0, 0])
    sig, sig_name = _signal(spec, f)
    levels = (rep_levels(spec, sig) if spec.signal is not None and sig is not None
              else (spec.rest, spec.active))
    reps, partial = [], False
    if spec.kind != "hold":
        reps = detect_reps(spec, f)
        if not reps:                                   # as analyse(): half-way movements as partial reps
            reps = detect_reps(replace(spec, active=spec.rest + (spec.active - spec.rest) * 0.5), f)
            partial = bool(reps)

    sig_vals = identity.signature(f) if key not in HAND_EXERCISES else {}
    why, small = identity.check_detail(key, sig_vals) if sig_vals else (None, False)
    rules = []
    for name, op, limit, reason in identity.RULES.get(key, []):
        v = sig_vals.get(name, float("nan"))
        ok = None if not np.isfinite(v) else (v >= limit if op == ">=" else v < limit)
        rules.append({"signature": name, "op": op, "limit": limit, "value": _num(v), "passed": ok,
                      "reason_if_failed": reason})

    judged = [r for r in reps if not r.unfinished]
    rep_rows = []
    for i, r in enumerate(reps):
        checks = []
        if not r.unfinished:
            for m in spec.mistakes:
                v, lim = m.value(f, r), m.limit_for(rom_scale)
                fired = m.check(f, r, rom_scale)
                checks.append({"label": m.label, "value": _num(v), "limit": round(lim, 3), "above": m.above,
                               "unit": m.unit, "fired": bool(fired), "range_rule": m.rom_base is not None,
                               "frail_ok": m.frail_ok})
        rep_rows.append({"n": i + 1, "start_sec": _num(f.t[r.start]), "peak_sec": _num(f.t[r.peak]),
                         "end_sec": _num(f.t[r.end]), "side": r.side or None, "unfinished": r.unfinished,
                         "peak_value": _num(sig[r.peak]) if sig is not None else None,
                         "mistakes_found_by_rules": check_rep(spec, f, r, rom_scale) if not r.unfinished else [],
                         "rules": checks})

    model = None
    path = classifier.latest_weights(key)
    if path is not None and judged:
        pred = classifier.predict(key, f, judged)
        _, ckpt = classifier._load(str(path))
        model = {"version": path.stem, "duration_range_sec": ckpt.get("duration_range"),
                 "used_in_result": bool(result and "+" in result.get("model_version", "")),
                 "reps": [{"n": reps.index(r) + 1, "p_correct": None if p is None else round(p, 3),
                           "likely_mistake": lm, "left_to_rules": p is None}
                          for r, p, lm in zip(judged, pred["p_correct"], pred["likely_mistake"])]}

    out = {
        "exercise_key": key, "exercise_name": spec.name, "view": spec.view, "rom_scale": rom_scale,
        "video": {"width": seq.info.width, "height": seq.info.height, "fps": _num(seq.info.fps),
                  "duration_sec": _num(seq.info.duration_sec), "frames_analysed": int(len(seq.t)),
                  "body_found_frames": int(found.sum()), "brightness": _num(brightness) if brightness else None},
        "camera": {"shoulder_width_to_torso": _num(side_view_ratio(seq))},
        "fall_at_sec": possible_fall(spec, f),
        "signal": {"name": sig_name, "values": [_num(v) for v in sig] if sig is not None else None,
                   "start_level": _num(levels[0]), "count_level": _num(levels[1])},
        "repetitions": rep_rows, "partial_repetitions": partial,
        "identity": {"signature": {k: _num(v) for k, v in sig_vals.items()}, "rules": rules,
                     "refused_because": why, "only_too_small": small},
        "model": model,
        "result": result, "error": error,
        "timings_sec": {**(timings or {}), "analysis": round(t_analyse, 3)},
    }
    return out


def save_run(root: Path, video: Path | None, seq: PoseSequence, tr: dict, source: str, keep: int = 20) -> str:
    """Keeps one run in root/<id>/ (video, landmarks, trace) and only the newest `keep` runs."""
    run_id = datetime.now().strftime("%Y%m%d-%H%M%S-%f")[:-3] + "_" + tr["exercise_key"]
    d = Path(root) / run_id
    d.mkdir(parents=True, exist_ok=True)
    if video is not None:
        shutil.copyfile(video, d / ("video" + Path(video).suffix.lower()))
    save(seq, d / "landmarks.npz")
    tr = {**tr, "id": run_id, "source": source, "saved_at": datetime.now().isoformat(timespec="seconds")}
    (d / "trace.json").write_text(json.dumps(tr), encoding="utf-8")
    runs = sorted(p for p in Path(root).iterdir() if p.is_dir())
    for old in runs[:-keep]:
        shutil.rmtree(old, ignore_errors=True)
    return run_id


def load_run(root: Path, run_id: str) -> tuple[dict, PoseSequence, Path | None]:
    d = Path(root) / run_id
    tr = json.loads((d / "trace.json").read_text(encoding="utf-8"))
    video = next((p for p in d.iterdir() if p.stem == "video"), None)
    return tr, load(d / "landmarks.npz"), video
