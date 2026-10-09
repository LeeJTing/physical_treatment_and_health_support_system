"""Posture analysis for one clip (FR300_07 to FR300_10, FR300_17, FR300_19).

landmarks -> visibility check -> joint angles -> repetitions -> rule checks
(+ the trained classifier when its weights exist) -> accuracy and feedback.
"""
from collections import Counter
from dataclasses import replace

import numpy as np

from . import classifier, identity
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
    """code: pose_not_detected | full_body_not_visible | hand_not_visible | no_repetitions | wrong_exercise"""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


# Sit-to-stand filmed at an angle (sit2stand.ai home videos, 8 Oct): from 45 degrees a seated knee
# looks 115-130 degrees, never below the 112 "seated" level, so five stands merged into one (97 of
# 377 videos). When the clip's own seated level stays above it, the levels come from the clip.
# Mini squat (9 Oct, REHAB26-ViewAngles): a person whose knees never read straighter than 10-13
# degrees standing (slightly bent knees, common with age) never got back under the 8 degree start level,
# so ten squats counted as two. Values: how close the clip's standing level must come to `rest` (any,
# for the squat) and the smallest movement range before the levels follow the clip, then the start and
# count levels as shares of the clip's range. The exercise's own levels stay the lowest used, and the
# squat's shares are low so that shallow squats after a deep one (tiring) still count.
ADAPTIVE_REST = {"sit_to_stand": (5.0, 25.0, 0.25, 0.5), "mini_squat": (180.0, 12.0, 0.2, 0.35)}


def rep_levels(spec: ExerciseSpec, sig: np.ndarray) -> tuple[float, float]:
    rest, active = spec.rest, spec.active
    if spec.key in ADAPTIVE_REST:
        below, min_range, rest_share, active_share = ADAPTIVE_REST[spec.key]
        s = sig[~np.isnan(sig)]
        if len(s) > 10:
            lo, hi = np.percentile(s, [5, 95])
            if lo > rest - below and hi - lo > min_range:
                rest = max(rest, float(lo + rest_share * (hi - lo)))
                active = max(active, float(lo + active_share * (hi - lo)))
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
# Seated at a table, filmed close: the hands are tracked by MediaPipe's hand model, and the fall,
# balance, body-size and camera-angle checks do not apply.
HAND_EXERCISES = {"wrist_extension", "hand_open_close"}
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
    if spec.key in LYING_EXERCISES or spec.key in HAND_EXERCISES or len(f.t) < 3:
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
    return _upright_then_down(f, lean, hip, ok)


# A fast change from standing upright to low (UR Fall Detection Dataset, 8 Oct: the checks above caught
# 12 of 30 real falls; short clips end soon after the fall, and a body on the floor often fits a
# skeleton the checks above distrust). The person was upright on a reliable skeleton a moment
# before, so what follows is trusted: falls caught 25/30, no alert on 374 sit2stand.ai videos (fast
# sitting) or Elwin's clips; everyday movements on the floor 10/40 (lying or crouching down on purpose).
FALL_UPRIGHT_LEAN = 35.0       # upright: trunk within 35 degrees of vertical, hips near standing height
FALL_FAST_DROP = 0.6           # then hips at least this many torso lengths lower ...
FALL_FAST_WINDOW = 1.0         # ... within this many seconds ...
FALL_FAST_LEAN = 60.0          # ... with the trunk past 60 degrees ...
FALL_FAST_STAY = 0.5           # ... and staying low (or out of sight) this long or to the end


def _upright_then_down(f: Features, lean: np.ndarray, hip: np.ndarray, ok: np.ndarray) -> float | None:
    lean = np.nan_to_num(lean, nan=0.0)
    t = f.t
    upright = ok & (lean < FALL_UPRIGHT_LEAN) & (np.nan_to_num(hip, nan=-9.0) > -0.4)
    for i in np.where(upright)[0]:
        last = min(int(np.searchsorted(t, t[i] + FALL_FAST_WINDOW)), len(t) - 1)
        for j in range(i + 1, last + 1):
            if np.isnan(hip[j]) or hip[i] - hip[j] < FALL_FAST_DROP or lean[j] < FALL_FAST_LEAN:
                continue
            after = hip[j:max(int(np.searchsorted(t, t[j] + FALL_FAST_STAY)), j + 1)]
            if np.all(np.where(np.isnan(after), True, after <= hip[i] - 0.75 * FALL_FAST_DROP)):
                return float(t[j])
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
# Shoulder width / torso length. REHAB26-ViewAngles (5 people, 3 cameras, 29 angles, 9 Oct) medians:
# 0.07 in profile, 0.22-0.26 at 20 degrees off, 0.34-0.39 at 30, 0.42-0.48 at 40, 0.5-0.52 at 45, 0.7 facing.
SIDE_VIEW_TIP = 0.30           # about 25 degrees off: tell the patient
SIDE_VIEW_WRONG = 0.42         # about 35-40 degrees off: the checks below are no longer reliable
# Front-view exercises filmed from the side (9 Oct condition audit): facing the phone the ratio is
# 0.65 or more in every own clip (REHAB26 p10 0.58-0.62 within 20 deg), about 0.6 at 30 deg round and
# 0.5 at 45 deg. Below 0.5 the patient is told (room for narrow shoulders); the result is still given.
FRONT_VIEW_TIP = 0.5
FRONT_VIEW_MESSAGE = ("Your phone seems to be more at your side than in front of you, so this result may be less "
                      "accurate. For this exercise, face the phone.")
CAMERA_FRONT_HINT = ("Your phone also seems to be in front of you: for this exercise, place the phone at your "
                     "side.")
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


def _same_exercise(spec: ExerciseSpec, f: Features, fall_at: float | None, camera_wrong: bool = False,
                   partial: bool = False) -> None:
    """Is the movement the selected exercise? (8 Oct: another exercise's video passed as shoulder
    abduction.) Checked only once movement was found (no movement stays "no repetition"), and never
    when a possible fall was seen: the fall is reported first, whatever the exercise."""
    if fall_at is not None:
        return
    why, small = identity.check_detail(spec.key, identity.signature(f))
    if why and small and partial:
        # Only a small movement, too small to tell which exercise it is (9 Oct condition audit: weak
        # sit-to-stands at a third of the range were told "does not look like Sit-to-Stand ... check that
        # you chose the right exercise"). Nothing is saved, as for a wrong exercise.
        raise PoseError("wrong_exercise", f"We could only see a small movement, so this did not count as "
                                          f"{spec.name} yet ({why}). That is a start: move a little further "
                                          f"each time, only as far as is comfortable, and keep your whole body "
                                          f"in the picture.")
    if why:
        # A side-view exercise filmed from the front hides the bend it is checked on (REHAB26, 9 Oct:
        # squats facing the phone read "no knee bending was seen"), so say where the phone goes.
        how = "Please check that you chose the right exercise and record it as shown in the steps."
        if camera_wrong:
            how = f"{how} {CAMERA_FRONT_HINT}"
        raise PoseError("wrong_exercise", f"This video does not look like {spec.name} ({why}). {how}")


def analyse(pose_key: str, seq: PoseSequence, use_model: bool = True, rom_scale: float = 1.0,
            brightness: float | None = None) -> dict:
    """rom_scale < 1 (from rom_scale_for: older / high-risk patients) lowers the range-of-motion
    targets only. A possible fall is reported in "safety_alert" even when nothing else can be scored."""
    spec = get(pose_key)
    hands_only = spec.key in HAND_EXERCISES
    if hands_only:
        # Close-up at a table: the hand model is what matters, the body may be half hidden.
        if seq.hands is None or not np.isfinite(seq.hands[:, :, 0, 0]).any():
            raise PoseError("hand_not_visible", "No hand was detected in the video. Keep your whole hand in the "
                                                "picture, with a light on in front of you.")
    elif seq.detected_ratio < MIN_DETECTED:
        raise PoseError("pose_not_detected", "No body posture was detected in the video.")
    f = Features(seq)
    fall_at = possible_fall(spec, f)
    if hands_only:
        visible = ~np.all(np.isnan(seq.hands[:, :, 0, 0]), axis=1)             # a hand seen in the frame
    else:
        visible = f.visible(spec.required, either_side=spec.view == "side")
    visible_ratio = float(np.mean(visible)) if len(visible) else 0.0
    if visible_ratio < MIN_VISIBLE:
        if fall_at is not None:
            return _fall_only(pose_key, fall_at, visible_ratio)
        if hands_only:
            raise PoseError("hand_not_visible", "Your hand was not visible for most of the video. Keep your whole "
                                                "hand in the picture.")
        raise PoseError("full_body_not_visible", "The whole body was not visible for most of the video.")

    view_ratio = side_view_ratio(seq) if spec.view == "side" and spec.key not in HAND_EXERCISES else 0.0
    camera_wrong = view_ratio > SIDE_VIEW_WRONG
    ignore = VIEW_SENSITIVE.get(spec.key, set()) if camera_wrong else set()

    rep_details, all_mistakes = [], Counter()
    hold = None
    method = RULES_VERSION
    partial = False

    if spec.kind == "hold":
        _same_exercise(spec, f, fall_at, camera_wrong)
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
        _same_exercise(spec, f, fall_at, camera_wrong, partial)
        # The trained model learned full-range movement: it would mark every shortened rep wrong, so
        # for adjusted targets (frail users) only its form verdicts count (bent elbow, swinging, ...), on
        # repetitions that reached the full range, never its range verdicts or its score (9 Oct condition
        # audit: with the model off, 9 of 26 bent-elbow, shrug and swinging clips passed at rom_scale 0.7).
        # Not for partial repetitions.
        frail = rom_scale < 1.0
        judged = [r for r in reps if not r.unfinished]
        model = (classifier.predict(pose_key, f, judged)
                 if use_model and not partial and not camera_wrong else None)
        range_rules = {m.label for m in spec.mistakes if m.rom_base is not None or m.frail_ok}
        if model:
            method = f"{RULES_VERSION}+{model['version']}"
        for i, rep in enumerate(judged):
            mistakes = [m for m in check_rep(spec, f, rep, rom_scale) if m not in ignore]
            score = max(0.0, 100.0 - MISTAKE_PENALTY * len(mistakes))
            detail = {"start_sec": round(float(f.t[rep.start]), 2), "end_sec": round(float(f.t[rep.end]), 2),
                      "side": rep.side or None, "rule_score": score, "mistakes": mistakes}
            if partial:
                detail["partial"] = True
            if model and model["p_correct"][i] is not None:
                p = float(model["p_correct"][i])
                detail["p_correct"] = round(p, 3)
                likely = model["likely_mistake"][i]
                if frail:
                    # Only on repetitions that reached the full range, and then scored as with full
                    # targets (never its range verdicts): on shortened ones the model blamed form for the
                    # short range (weak correct movements at rom 0.7 passing 87 -> 69 %), and without the
                    # model's half of the score a full-range repetition scored lower than at full targets
                    # (9 Oct viewer: the same correct sit-to-stand 88.5 % normally, 77.5 % at rom 0.7).
                    if not any(m in range_rules for m in check_rep(spec, f, rep, 1.0)):
                        if p < 0.5 and not mistakes and likely and likely not in range_rules and likely not in ignore:
                            mistakes = [likely]
                            detail["mistakes"] = mistakes
                        score = 0.5 * score + 0.5 * 100 * p
                    else:
                        detail.pop("p_correct")
                else:
                    if p < 0.5 and not mistakes and likely:
                        mistakes = [likely]
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
    if fall_at is None and spec.view == "front" and spec.key not in LYING_EXERCISES | HAND_EXERCISES:
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
    if spec.view == "front" and spec.key not in LYING_EXERCISES | HAND_EXERCISES:
        front_ratio = side_view_ratio(seq)
        if 0 < front_ratio < FRONT_VIEW_TIP:
            tips.append(FRONT_VIEW_MESSAGE)
            extra["camera_not_in_front"] = round(front_ratio, 2)
    if brightness is not None and brightness < DARK_BRIGHTNESS:
        tips.append(DARK_MESSAGE)
    if spec.key not in LYING_EXERCISES | HAND_EXERCISES and body_height_share(seq) < SMALL_BODY:
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
