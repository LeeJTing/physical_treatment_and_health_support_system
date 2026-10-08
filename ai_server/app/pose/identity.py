"""Is the video the exercise the patient selected? (8 Oct, bug from Elwin: a video of another exercise
came back as a pass for shoulder abduction.)

signature() summarises the whole clip in a few camera-independent numbers: how much the arms, elbows,
knees, hips and heels move, the body's posture (standing, sitting, lying) and the direction of the arm
raise. The rules that use them are in identity.check (filled in from training/exercise_signatures.py).
"""
import numpy as np

from .geometry import Features
from .landmarks import L_ELBOW, L_HIP, L_SHOULDER, L_WRIST, R_ELBOW, R_HIP, R_SHOULDER, R_WRIST


def _rng(x: np.ndarray) -> float:
    x = x[np.isfinite(x)]
    return float(np.percentile(x, 95) - np.percentile(x, 5)) if len(x) > 3 else 0.0


def _med(x: np.ndarray) -> float:
    x = x[np.isfinite(x)]
    return float(np.median(x)) if len(x) else float("nan")


def signature(f: Features) -> dict[str, float]:
    s = {}
    s["arm_raise"] = max(_rng(f["shoulder_elev_L"]), _rng(f["shoulder_elev_R"]))          # degrees
    s["elbow_bend"] = max(_rng(f["elbow_L"]), _rng(f["elbow_R"]))                          # degrees
    s["knee_bend"] = max(_rng(f["knee_L"]), _rng(f["knee_R"]))                             # degrees
    s["knee_median"] = min(_med(f["knee_L"]), _med(f["knee_R"]))                           # ~90 seated, ~170 standing
    s["hip_rise"] = _rng(f["hip_rise"])                                                    # torso lengths
    s["trunk_upright"] = _med(f["trunk_from_horizontal"])                                  # 90 upright, 0 lying
    s["thigh_lift"] = max(_rng(f["thigh_from_down_L"]), _rng(f["thigh_from_down_R"]))     # degrees
    s["leg_side"] = max(_rng(f["leg_from_down_L"]), _rng(f["leg_from_down_R"]))           # degrees
    s["heel_lift"] = max(_rng(f["heel_lift_L"]), _rng(f["heel_lift_R"]))                   # shin lengths
    hl, hr = f["heel_lift_L"], f["heel_lift_R"]
    ok = np.isfinite(hl) & np.isfinite(hr)
    s["heels_together"] = float(np.corrcoef(hl[ok], hr[ok])[0, 1]) if ok.sum() > 5 and np.std(hl[ok]) > 0 and np.std(hr[ok]) > 0 else 0.0
    tl, tr = f["thigh_from_down_L"], f["thigh_from_down_R"]
    ok = np.isfinite(tl) & np.isfinite(tr)
    s["thighs_together"] = float(np.corrcoef(tl[ok], tr[ok])[0, 1]) if ok.sum() > 5 and np.std(tl[ok]) > 0 and np.std(tr[ok]) > 0 else 0.0
    # Direction of the arm raise at its highest: wrist off to the side of the shoulder (abduction seen
    # from the front) versus in line with it (flexion seen from the front), as a share of arm length.
    xy = f.seq.xy
    out = []
    for sh, el, wr in ((L_SHOULDER, L_ELBOW, L_WRIST), (R_SHOULDER, R_ELBOW, R_WRIST)):
        arm = np.linalg.norm(xy[:, sh] - xy[:, el], axis=1) + np.linalg.norm(xy[:, el] - xy[:, wr], axis=1)
        side = np.abs(xy[:, wr, 0] - xy[:, sh, 0]) / (arm + 1e-9)
        up = xy[:, sh, 1] - xy[:, wr, 1]                                   # + when the wrist is above the shoulder
        high = np.isfinite(side) & np.isfinite(up) & (up > -0.2 * arm)
        if high.sum() >= 3:
            out.append(float(np.median(side[high])))
    s["arm_sideways"] = max(out) if out else float("nan")
    hips = (xy[:, L_HIP] + xy[:, R_HIP]) / 2
    shoulders = (xy[:, L_SHOULDER] + xy[:, R_SHOULDER]) / 2
    width = np.linalg.norm(xy[:, L_SHOULDER] - xy[:, R_SHOULDER], axis=1)
    torso = np.linalg.norm(shoulders - hips, axis=1)
    s["view_ratio"] = _med(width / (torso + 1e-9))
    return s


# Each exercise's must-haves, set from Elwin's and p02's labelled clips (training/exercise_signatures.py,
# correct and incorrect versions) with wide margins: weak, partial attempts of the right exercise must
# still pass (evidence of doing it comes first), only clearly different movements are refused.
# (signature, ">=" or "<", value, what the patient is told is missing or unexpected)
UPRIGHT = ("trunk_upright", ">=", 35.0, "you were lying down")          # lying ones: glute bridge, bird dog
STANDING = ("knee_median", ">=", 110.0, "you were sitting")
SEATED = ("knee_median", "<", 140.0, "you were standing")
# Knee bend, not hip height, tells arm exercises from leg ones: hip height is noisy on shaky or
# low-resolution video (MobiPhysio p95 0.6 torso lengths) while real arm reps keep the knees within
# 25-37 degrees (p95-p99, MobiPhysio and IntelliRehabDS) and sit-to-stand, squats and step-ups bend them
# 49 degrees or more (p5 of Elwin's clips).
LEGS_STILL = ("knee_bend", "<", 45.0, "your knees bent a lot")
RULES: dict[str, list[tuple[str, str, float, str]]] = {
    "sit_to_stand": [("hip_rise", ">=", 0.2, "no standing up from the chair was seen"),
                     ("knee_bend", ">=", 30.0, "your knees hardly bent"), UPRIGHT],
    "knee_extension": [("knee_bend", ">=", 25.0, "no knee straightening was seen"),
                       ("hip_rise", "<", 0.3, "you stood up"), SEATED, UPRIGHT],
    "seated_marching": [("thigh_lift", ">=", 8.0, "no knee lifting was seen"),
                        ("knee_bend", "<", 50.0, "your knee straightened out in front"), SEATED, UPRIGHT],
    "march_in_place": [("thigh_lift", ">=", 20.0, "no knee lifting was seen"),
                       ("thighs_together", "<", 0.6, "both legs moved together"), STANDING, UPRIGHT],
    "mini_squat": [("knee_bend", ">=", 20.0, "no knee bending was seen"),
                   ("hip_rise", ">=", 0.1, "your hips did not lower"),
                   ("thighs_together", ">=", 0.2, "your legs moved one at a time"), STANDING, UPRIGHT],
    "step_up": [("hip_rise", ">=", 0.12, "no stepping up was seen"),
                ("thighs_together", "<", 0.5, "both legs moved together"), UPRIGHT],
    "heel_raise": [("heel_lift", ">=", 0.04, "your heels hardly lifted"),
                   ("heels_together", ">=", 0.5, "your heels did not rise together"),
                   ("leg_side", "<", 12.0, "a leg moved out to the side"),
                   ("arm_raise", "<", 45.0, "your arms were raised"), STANDING, UPRIGHT],
    "hip_abduction": [("leg_side", ">=", 8.0, "no leg lifting to the side was seen"),
                      ("hip_rise", "<", 0.35, "your hips moved up and down"), STANDING, UPRIGHT],
    "tandem_stance": [("arm_raise", "<", 40.0, "your arms were raised"), LEGS_STILL, UPRIGHT],
    "glute_bridge": [("trunk_upright", "<", 35.0, "you were not lying on your back"),
                     ("hip_rise", ">=", 0.1, "no hip lifting was seen")],
    "bird_dog": [("trunk_upright", "<", 40.0, "you were not on your hands and knees"),
                 ("arm_raise", ">=", 20.0, "no arm reaching was seen")],
    "shoulder_abduction": [("arm_raise", ">=", 25.0, "no arm raising was seen"), LEGS_STILL, UPRIGHT],
    "shoulder_flexion": [("arm_raise", ">=", 25.0, "no arm raising was seen"), LEGS_STILL, UPRIGHT],
    "elbow_flexion": [("elbow_bend", ">=", 45.0, "no elbow bending was seen"), LEGS_STILL, UPRIGHT],
    # Hand exercises (wrist_extension, hand_open_close): no rules here. The body is half hidden by the
    # table, so the body signature is unreliable; a repetition found on the hand points is the evidence.
    "wall_push_up": [("elbow_bend", ">=", 25.0, "no elbow bending was seen"),
                     ("arm_raise", ">=", 20.0, "your arms were not up at the wall"),
                     ("heels_together", ">=", 0.4, "your feet moved"), LEGS_STILL, UPRIGHT],
}


def check(key: str, sig: dict[str, float]) -> str | None:
    """None when the clip can be the exercise, else a short reason ("your knees bent a lot")."""
    for name, op, limit, why in RULES.get(key, []):
        v = sig.get(name, float("nan"))
        if not np.isfinite(v):
            continue                                      # not measurable: never refuse on it
        if (op == ">=" and v < limit) or (op == "<" and v >= limit):
            return why
    # Arms raised sideways or forwards: from the front, abduction moves the wrists out to the side
    # of the shoulders (0.96-1.0 of the arm's length in Elwin's and p02's clips) and flexion keeps them
    # in front of the body; from the side it is the other way round.
    side, view = sig.get("arm_sideways", float("nan")), sig.get("view_ratio", float("nan"))
    if np.isfinite(side) and np.isfinite(view):
        if key == "shoulder_flexion" and view > 0.45 and side > 0.7:
            return "your arms went out to the side, not forwards"
        if key == "shoulder_abduction" and view < 0.3 and side > 0.7:
            return "your arms went forwards, not out to the side"
    return None
