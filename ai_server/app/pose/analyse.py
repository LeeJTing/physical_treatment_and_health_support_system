"""Posture analysis for one clip (FR300_07 to FR300_10, FR300_17, FR300_19).

landmarks -> visibility check -> joint angles -> repetitions -> rule checks
(+ the trained classifier when its weights exist) -> accuracy and feedback.
"""
from collections import Counter
from dataclasses import replace

import numpy as np

from . import classifier
from .exercises import ExerciseSpec, get
from .geometry import Features
from .landmarks import PoseSequence
from .reps import Rep, find_reps, merge_sides

RULES_VERSION = "rules-1.0"
MISTAKE_PENALTY = 30          # points off a repetition per mistake found
MIN_DETECTED = 0.5            # share of frames with a person found
MIN_VISIBLE = 0.8             # share of frames with every required body part in the picture
GOOD_FORM = "Good form. Keep it up!"


class PoseError(Exception):
    """code: pose_not_detected | full_body_not_visible | no_repetitions"""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def detect_reps(spec: ExerciseSpec, f: Features) -> list[Rep]:
    if spec.side_signals is not None:
        sig = spec.side_signals(f)
        return merge_sides(*(find_reps(s, f.t, spec.rest, spec.active, side=k) for k, s in sig.items()))
    return find_reps(spec.signal(f), f.t, spec.rest, spec.active)


def check_rep(spec: ExerciseSpec, f: Features, rep: Rep, rom_scale: float = 1.0) -> list[str]:
    found = []
    for m in spec.mistakes:
        try:
            if m.check(f, rep, rom_scale):
                found.append(m.label)
        except (KeyError, IndexError, ValueError):
            continue
    return found


def longest_true_seconds(mask: np.ndarray, t: np.ndarray) -> float:
    if len(t) < 2:
        return 0.0
    dt = float(np.median(np.diff(t)))
    best = cur = 0.0
    for flag in mask:
        cur = cur + dt if flag else 0.0
        best = max(best, cur)
    return best


# ---- possible fall (8 Oct) ----------------------------------------------------------------
# Calibrated on all 330 of Elwin's clips, none of which contains a fall: normal exercise reached at
# most 68 deg of trunk lean held for 0.7 s (sit-to-stand), a hip drop of 1.8 torso lengths per
# second (sitting down fast) and hips 0.67 torso lengths below their usual height (deep squat).
LYING_EXERCISES = {"glute_bridge", "bird_dog"}
FALL_LEAN_DEG = 80.0           # trunk nearly horizontal ...
FALL_HOLD_SEC = 0.7            # ... for this long
FALL_LOW_TORSO = 1.2           # or hips this far below their usual height for as long
FALL_DROP_SPEED = 2.5          # or a drop this fast (torso lengths / s) ...
FALL_DROP_DEPTH = 0.8          # ... that ends this far down
FALL_MESSAGE = ("It looks like you may have lost your balance or fallen. Stop the exercise. If you are hurt, "
                "dizzy or cannot get up, call for help or 999. Next time keep a sturdy chair or counter "
                "within reach.")
# Balance (front-view standing exercises): side-to-side hip travel (3rd to 97th percentile) in torso
# lengths. Correct clips reached at most 0.33; stepping out of tandem stance 0.57, leaning hip
# abductions about 0.8. A tip, not a mistake: it does not lower the score.
BALANCE_SWAY = 0.5
BALANCE_MESSAGE = "You swayed quite a lot. Hold on to a sturdy chair or counter to keep your balance."
PARTIAL_MESSAGE = ("We saw small movements but not full repetitions. That is a good start: move a little "
                   "further each time, as far as is comfortable.")


def _held(mask: np.ndarray, t: np.ndarray, sec: float) -> int | None:
    """Index where `mask` has been true for `sec` seconds in a row, or None."""
    if len(t) < 2:
        return None
    dt = float(np.median(np.diff(t)))
    need, run = max(1, int(round(sec / dt))), 0
    for i, flag in enumerate(mask):
        run = run + 1 if flag else 0
        if run >= need:
            return i
    return None


def possible_fall(spec: ExerciseSpec, f: Features) -> float | None:
    """Time (s) of a possible fall in a standing or seated exercise, or None."""
    if spec.key in LYING_EXERCISES or len(f.t) < 3:
        return None
    lean = 90.0 - f["trunk_from_horizontal"]                  # trunk angle from upright
    hip = f["hip_rise"]                                        # + up, torso lengths from the clip median
    for mask in (lean > FALL_LEAN_DEG, hip < -FALL_LOW_TORSO):
        i = _held(np.nan_to_num(mask, nan=False), f.t, FALL_HOLD_SEC)
        if i is not None:
            return float(f.t[i])
    v = np.gradient(np.nan_to_num(hip), f.t)
    for i in np.where(-v > FALL_DROP_SPEED)[0]:
        stop = int(np.searchsorted(f.t, f.t[i] + 1.5))
        if np.nanmin(hip[i:max(stop, i + 1)]) < -FALL_DROP_DEPTH:
            return float(f.t[i])
    return None


def _fall_only(pose_key: str, at: float, visible_ratio: float) -> dict:
    """Result when a fall was seen but the exercise itself could not be analysed."""
    return {"exercise_key": pose_key, "accuracy": 0.0, "repetitions": 0, "hold_seconds": None,
            "feedback": [FALL_MESSAGE], "mistakes": {}, "full_body_visible": visible_ratio >= MIN_VISIBLE,
            "visible_ratio": round(visible_ratio, 3), "rep_details": [], "model_version": RULES_VERSION,
            "safety_alert": {"type": "possible_fall", "at_sec": round(at, 1), "message": FALL_MESSAGE}}


def analyse(pose_key: str, seq: PoseSequence, use_model: bool = True, rom_scale: float = 1.0) -> dict:
    """rom_scale < 1 (from rom_scale_for: older / high-risk patients) lowers the range-of-motion
    targets only. A possible fall is reported in "safety_alert" even when nothing else can be scored."""
    spec = get(pose_key)
    if seq.detected_ratio < MIN_DETECTED:
        raise PoseError("pose_not_detected", "No body posture was detected in the video.")
    f = Features(seq)
    fall_at = possible_fall(spec, f)
    visible = f.visible(spec.required, either_side=spec.view == "side")
    visible_ratio = float(np.mean(visible)) if len(visible) else 0.0
    if visible_ratio < MIN_VISIBLE:
        if fall_at is not None:
            return _fall_only(pose_key, fall_at, visible_ratio)
        raise PoseError("full_body_not_visible", "The whole body was not visible for most of the video.")

    rep_details, all_mistakes = [], Counter()
    hold = None
    method = RULES_VERSION
    partial = False

    if spec.kind == "hold":
        whole = Rep(start=0, peak=len(f.t) // 2, end=len(f.t) - 1)
        mistakes = check_rep(spec, f, whole, rom_scale)
        hold = longest_true_seconds((f["feet_gap"] < 0.6) & visible, f.t)
        target = spec.hold_target_sec * min(rom_scale, 1.0)        # shorter hold for frail patients
        score = max(0.0, min(1.0, hold / target) * 100 - MISTAKE_PENALTY * len(mistakes))
        all_mistakes.update(mistakes)
        rep_details.append({"start_sec": float(f.t[0]), "end_sec": float(f.t[-1]), "score": round(score, 1),
                            "mistakes": mistakes})
        reps: list[Rep] = []
    else:
        reps = detect_reps(spec, f)
        if not reps:
            # Weak muscles (disuse, age) or a first, hesitant try: count movements that got half way
            # to the usual start-of-rep level as partial repetitions, with encouragement, instead
            # of failing with "no repetition found".
            reps = detect_reps(replace(spec, active=spec.rest + (spec.active - spec.rest) * 0.5), f)
            partial = bool(reps)
        if fall_at is not None:
            # Movement during or after a fall is not exercise.
            reps = [r for r in reps if f.t[r.start] < fall_at - 1.0]
        if not reps:
            if fall_at is not None:
                return _fall_only(pose_key, fall_at, visible_ratio)
            raise PoseError("no_repetitions", "No complete repetition was found in the video.")
        # The trained model learned full-range movement: it would mark every shortened rep wrong, so
        # it is not used for adjusted targets or partial repetitions; the rules judge those.
        model = classifier.predict(pose_key, f, reps) if use_model and rom_scale >= 1.0 and not partial else None
        if model:
            method = f"{RULES_VERSION}+{model['version']}"
        for i, rep in enumerate(reps):
            mistakes = check_rep(spec, f, rep, rom_scale)
            score = max(0.0, 100.0 - MISTAKE_PENALTY * len(mistakes))
            detail = {"start_sec": round(float(f.t[rep.start]), 2), "end_sec": round(float(f.t[rep.end]), 2),
                      "side": rep.side or None, "rule_score": score, "mistakes": mistakes}
            if partial:
                detail["partial"] = True
            if model:
                p = float(model["p_correct"][i])
                detail["p_correct"] = round(p, 3)
                if p < 0.5 and not mistakes and model["likely_mistake"][i]:
                    mistakes = [model["likely_mistake"][i]]
                    detail["mistakes"] = mistakes
                score = 0.5 * score + 0.5 * 100 * p
            detail["score"] = round(score, 1)
            all_mistakes.update(mistakes)
            rep_details.append(detail)

    accuracy = round(float(np.mean([d["score"] for d in rep_details])), 1)
    texts = {m.label: m.feedback for m in spec.mistakes}
    feedback = [texts[label] for label, _ in all_mistakes.most_common() if label in texts] or [GOOD_FORM]
    if partial:
        feedback = [PARTIAL_MESSAGE] + [x for x in feedback if x != GOOD_FORM]
    if fall_at is not None:
        feedback = [FALL_MESSAGE] + [x for x in feedback if x != GOOD_FORM]
    extra = {}
    if fall_at is None and spec.view == "front" and spec.key not in LYING_EXERCISES:
        sway = f["hip_sway"]
        if float(np.nanpercentile(sway, 97) - np.nanpercentile(sway, 3)) > BALANCE_SWAY:
            feedback = feedback + [BALANCE_MESSAGE]
            extra["balance_tip"] = True
    if fall_at is not None:
        extra["safety_alert"] = {"type": "possible_fall", "at_sec": round(fall_at, 1), "message": FALL_MESSAGE}
    if partial:
        extra["partial_repetitions"] = True
    if rom_scale < 1.0:
        extra["rom_scale"] = rom_scale
    return {
        "exercise_key": pose_key,
        "accuracy": accuracy,
        "repetitions": len(reps),
        "hold_seconds": round(hold, 1) if hold is not None else None,
        "feedback": feedback,
        "mistakes": dict(all_mistakes),
        "full_body_visible": True,
        "visible_ratio": round(visible_ratio, 3),
        "rep_details": rep_details,
        "model_version": method,
        **extra,
    }
