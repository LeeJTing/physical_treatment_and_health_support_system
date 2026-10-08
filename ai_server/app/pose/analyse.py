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
from .landmarks import L_ANKLE, L_HIP, L_SHOULDER, NOSE, R_ANKLE, R_HIP, R_SHOULDER, PoseSequence
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


# Sit-to-stand filmed at an angle (sit2stand.ai home videos, 8 Oct): from 45 degrees a seated knee
# looks 115-130 degrees, never below the 112 "seated" level, so five stands merged into one (97 of
# 377 videos). When the clip's own seated level stays above it, the levels come from the clip.
ADAPTIVE_REST = {"sit_to_stand"}


def rep_levels(spec: ExerciseSpec, sig: np.ndarray) -> tuple[float, float]:
    rest, active = spec.rest, spec.active
    if spec.key in ADAPTIVE_REST:
        s = sig[~np.isnan(sig)]
        if len(s) > 10:
            lo, hi = np.percentile(s, [5, 95])
            if lo > rest - 5 and hi - lo > 25:
                rest = float(lo + 0.25 * (hi - lo))
                active = max(active, float(lo + 0.5 * (hi - lo)))
    return rest, active


def detect_reps(spec: ExerciseSpec, f: Features) -> list[Rep]:
    if spec.side_signals is not None:
        sig = spec.side_signals(f)
        return merge_sides(*(find_reps(s, f.t, spec.rest, spec.active, side=k) for k, s in sig.items()))
    sig = spec.signal(f)
    return find_reps(sig, f.t, *rep_levels(spec, sig))


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
FALL_MESSAGE = ("Stop and rest: it looks like you may have lost your balance or fallen. If you are hurt, "
                "dizzy or cannot get up, call for help or 999. Do not try this exercise again today. Next "
                "time keep a sturdy chair or counter within reach.")
# Balance (front-view standing exercises): side-to-side hip travel (3rd to 97th percentile) in torso
# lengths. Correct clips reached at most 0.33; stepping out of tandem stance 0.57, leaning hip
# abductions about 0.8. A tip, not a mistake: it does not lower the score.
BALANCE_SWAY = 0.5
BALANCE_MESSAGE = ("You swayed from side to side. Hold on to a sturdy chair or counter, and rest if you feel "
                   "unsteady.")
# Recording quality (8 Oct, rules_robustness_camera.json): dark footage and a small, far-away
# figure made the rules less reliable (knee extension detection 100 -> 67 %, sit-to-stand false
# alarms 2 -> 17 %), while MediaPipe's own confidence stayed at 99 %. Elwin's videos: mean
# brightness 105-152 (0-255), body 53-81 % of the frame height; dark copies 50-75, MobiPhysio's
# low-light videos 83 (median), far-camera copies 42 % (p5).
DARK_BRIGHTNESS = 80.0
SMALL_BODY = 0.45
DARK_MESSAGE = ("Your video is quite dark, so this result may be less accurate. Next time record with a "
                "light on in front of you.")
SMALL_MESSAGE = ("You look small in the video, so this result may be less accurate. Move the phone a little "
                 "closer, keeping your whole body from head to feet in the picture.")
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


FALL_WARMUP_SEC = 1.0          # the tracker is still finding the person


def reliable_frames(f: Features) -> np.ndarray:
    """Frames whose skeleton is plausible enough to call a fall on. On strangers' home videos
    (sit2stand.ai, 8 Oct) MediaPipe fitted a shrunken or twisted skeleton for the first second on
    seated people, and the fall check fired at 0.6 s on 3 healthy people. A fall is not called in
    the first second, when the torso is under 0.6 or over 1.6 times its usual length (4 of 41,538
    frames in Elwin's clips), or on an upside-down skeleton (nose below the hips with the ankles
    above them)."""
    xy = f.seq.xy
    torso = np.linalg.norm((xy[:, L_SHOULDER] + xy[:, R_SHOULDER]) / 2 - (xy[:, L_HIP] + xy[:, R_HIP]) / 2, axis=1)
    ratio = torso / (np.nanmedian(torso) or 1.0)
    y = xy[..., 1]
    hip_y = (y[:, L_HIP] + y[:, R_HIP]) / 2
    upside_down = (y[:, NOSE] > hip_y) & ((y[:, L_ANKLE] + y[:, R_ANKLE]) / 2 < hip_y)
    # Shoulders well below the hips (trunk over 120 degrees from upright): a real fall leaves the
    # trunk about level, near 90 (2 more healthy sit2stand.ai videos).
    upside_down |= np.nan_to_num(90.0 - f["trunk_from_horizontal"], nan=0.0) > 120.0
    return (np.nan_to_num(ratio, nan=0.0) >= 0.6) & (np.nan_to_num(ratio, nan=9.0) <= 1.6) & ~upside_down \
        & (f.t >= f.t[0] + FALL_WARMUP_SEC)


def possible_fall(spec: ExerciseSpec, f: Features) -> float | None:
    """Time (s) of a possible fall in a standing or seated exercise, or None."""
    if spec.key in LYING_EXERCISES or len(f.t) < 3:
        return None
    lean = 90.0 - f["trunk_from_horizontal"]                  # trunk angle from upright
    hip = f["hip_rise"]                                        # + up, torso lengths from the clip median
    ok = reliable_frames(f)
    for mask in (lean > FALL_LEAN_DEG, hip < -FALL_LOW_TORSO):
        i = _held(np.nan_to_num(mask, nan=False) & ok, f.t, FALL_HOLD_SEC)
        if i is not None:
            return float(f.t[i])
    v = np.gradient(np.nan_to_num(hip), f.t)
    for i in np.where((-v > FALL_DROP_SPEED) & ok)[0]:
        stop = max(int(np.searchsorted(f.t, f.t[i] + 1.5)), i + 1)
        if np.mean(ok[i:stop]) < 0.7:
            continue                                   # the drop is mostly on a misfitted skeleton
        if np.nanmin(np.where(ok[i:stop], hip[i:stop], np.nan)) < -FALL_DROP_DEPTH:
            return float(f.t[i])
    return None


def _fall_only(pose_key: str, at: float, visible_ratio: float) -> dict:
    """Result when a fall was seen but the exercise itself could not be analysed."""
    return {"exercise_key": pose_key, "accuracy": 0.0, "repetitions": 0, "hold_seconds": None,
            "feedback": [FALL_MESSAGE], "mistakes": {}, "full_body_visible": visible_ratio >= MIN_VISIBLE,
            "visible_ratio": round(visible_ratio, 3), "rep_details": [], "model_version": RULES_VERSION,
            "safety_alert": {"type": "possible_fall", "at_sec": round(at, 1), "message": FALL_MESSAGE}}


# Camera position for side-view exercises (8 Oct: camera-angle test on Elwin's clips, sit2stand.ai):
# shoulder width / torso length in the image is 0.04-0.16 (p10-p90) side-on, 0.37 with the phone 30
# degrees round towards the front, 0.52 at 45 degrees; the sit2stand.ai home videos (about 45
# degrees) have a median of 0.50. Front-view exercises are not checked: other people filmed from the
# front ranged down to 0.36 (MobiPhysio p5) with an arm raised, too close to a turned camera.
SIDE_VIEW_TIP = 0.30           # about 25 degrees off: tell the patient
SIDE_VIEW_WRONG = 0.42         # about 35 degrees off: the checks below are no longer reliable
SIDE_VIEW_MESSAGE = ("Your phone seems to be more in front of you than at your side, so this result may be "
                     "less accurate. For this exercise, place the phone at your side.")
# Checks that fired on most of Elwin's correct clips with the phone 45 degrees round; they are not
# counted when the camera is clearly not at the side (the trained model is not used then either).
VIEW_SENSITIVE = {"sit_to_stand": {"hands_used", "feet_forward", "no_forward_lean"},
                  "shoulder_flexion": {"back_arch", "swinging"},
                  "knee_extension": {"incomplete_extension", "thigh_lift"},
                  "wall_push_up": {"hips_sag"},
                  "bird_dog": {"arm_leg_low"}}


def side_view_ratio(seq: PoseSequence) -> float:
    xy = seq.xy
    width = np.linalg.norm(xy[:, L_SHOULDER] - xy[:, R_SHOULDER], axis=1)
    torso = np.linalg.norm((xy[:, L_SHOULDER] + xy[:, R_SHOULDER]) / 2 - (xy[:, L_HIP] + xy[:, R_HIP]) / 2, axis=1)
    with np.errstate(invalid="ignore", divide="ignore"):
        r = width / torso
    r = r[np.isfinite(r)]
    return float(np.median(r)) if len(r) else 0.0


def body_height_share(seq: PoseSequence) -> float:
    """Median share of the frame height the body covers (1st to 99th percentile of the points)."""
    y = seq.xy[..., 1]
    ok = ~np.all(np.isnan(y), axis=1)
    if not ok.any():
        return 0.0
    ext = np.nanpercentile(y[ok], 99, axis=1) - np.nanpercentile(y[ok], 1, axis=1)
    return float(np.median(ext) / (seq.info.height or 1))


def analyse(pose_key: str, seq: PoseSequence, use_model: bool = True, rom_scale: float = 1.0,
            brightness: float | None = None) -> dict:
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

    view_ratio = side_view_ratio(seq) if spec.view == "side" else 0.0
    camera_wrong = view_ratio > SIDE_VIEW_WRONG
    ignore = VIEW_SENSITIVE.get(spec.key, set()) if camera_wrong else set()

    rep_details, all_mistakes = [], Counter()
    hold = None
    method = RULES_VERSION
    partial = False

    if spec.kind == "hold":
        whole = Rep(start=0, peak=len(f.t) // 2, end=len(f.t) - 1)
        mistakes = [m for m in check_rep(spec, f, whole, rom_scale) if m not in ignore]
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
        model = (classifier.predict(pose_key, f, reps)
                 if use_model and rom_scale >= 1.0 and not partial and not camera_wrong else None)
        if model:
            method = f"{RULES_VERSION}+{model['version']}"
        for i, rep in enumerate(reps):
            mistakes = [m for m in check_rep(spec, f, rep, rom_scale) if m not in ignore]
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
    tips = []
    if view_ratio > SIDE_VIEW_TIP:
        tips.append(SIDE_VIEW_MESSAGE)
        extra["camera_not_at_side"] = round(view_ratio, 2)
    if brightness is not None and brightness < DARK_BRIGHTNESS:
        tips.append(DARK_MESSAGE)
    if spec.key not in LYING_EXERCISES and body_height_share(seq) < SMALL_BODY:
        tips.append(SMALL_MESSAGE)
    if tips:
        feedback = feedback + tips
        extra["quality_tips"] = tips
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
