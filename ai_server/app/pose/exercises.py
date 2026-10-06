"""Posture rules for every catalogue exercise (pose_key).

Each exercise defines:
  * the landmarks that must be visible (FR300_17),
  * one signal that rises during a repetition, with rest / active levels for counting,
  * the target the signal should reach,
  * mistake checks per repetition. Mistake labels match fyp-notes/Recording_Guide.pdf,
    so the labelled clips test exactly the rule they are named after.

All thresholds are STARTING VALUES. Tune them with training/evaluate_rules.py
against the labelled clips; every number lives in this file.
"""
from dataclasses import dataclass, field
from typing import Callable

import numpy as np

from .geometry import Features
from .landmarks import (
    L_ANKLE, L_ELBOW, L_HIP, L_KNEE, L_SHOULDER, L_WRIST, NOSE,
    R_ANKLE, R_ELBOW, R_HIP, R_KNEE, R_SHOULDER, R_WRIST, L_HEEL, R_HEEL, L_FOOT, R_FOOT,
)
from .reps import Rep, hold_seconds, phase_seconds

UPPER = [L_SHOULDER, R_SHOULDER, L_ELBOW, R_ELBOW, L_WRIST, R_WRIST, L_HIP, R_HIP]
LOWER = [L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANKLE, R_ANKLE]
FEET = [L_HEEL, R_HEEL, L_FOOT, R_FOOT]
WHOLE = [NOSE] + UPPER + LOWER[2:]

# A check returns True when the MISTAKE is present in this repetition.
Check = Callable[[Features, Rep], bool]


@dataclass
class Mistake:
    label: str
    feedback: str
    check: Check


@dataclass
class ExerciseSpec:
    key: str
    name: str
    view: str                                   # "front" or "side"
    required: list[int]
    signal: Callable[[Features], np.ndarray] | None = None
    side_signals: Callable[[Features], dict[str, np.ndarray]] | None = None   # alternating limbs
    rest: float = 0.0
    active: float = 0.0
    target: float = 0.0                         # peak the signal should reach
    mistakes: list[Mistake] = field(default_factory=list)
    kind: str = "reps"                          # or "hold"
    hold_target_sec: float = 0.0


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def at_peak(series: np.ndarray, r: Rep) -> float:
    return float(series[r.peak])


def rep_max(series: np.ndarray, r: Rep) -> float:
    return float(series[r.slice()].max())


def rep_min(series: np.ndarray, r: Rep) -> float:
    return float(series[r.slice()].min())


def rep_range(series: np.ndarray, r: Rep) -> float:
    s = series[r.slice()]
    return float(s.max() - s.min())


def side_of(f: Features, name: str, r: Rep) -> np.ndarray:
    """The series of the limb that moved in this rep (or the more active one)."""
    if r.side in ("L", "R"):
        return f[f"{name}_{r.side}"]
    a, b = f[f"{name}_L"], f[f"{name}_R"]
    return a if rep_range(a, r) >= rep_range(b, r) else b


def moving_leg(f: Features, r: Rep, signal: str) -> str:
    if r.side:
        return r.side
    return "L" if rep_range(f[f"{signal}_L"], r) >= rep_range(f[f"{signal}_R"], r) else "R"


def peak_below(signal: Callable[[Features], np.ndarray], value: float) -> Check:
    return lambda f, r: rep_max(signal(f), r) < value


def hold_below(signal: Callable[[Features], np.ndarray], seconds: float, tol: float) -> Check:
    return lambda f, r: hold_seconds(signal(f), f.t, r, tol) < seconds


# ---------------------------------------------------------------------------
# signals
# ---------------------------------------------------------------------------

def knees(f):            return f.both("knee", "mean")
def arm_elev(f):         return f.both("shoulder_elev", "mean")
def arm_elev_max(f):     return f.both("shoulder_elev", "max")
def elbow_flex(f):       return 180 - f.both("elbow", "min")
def leg_raise(f):        return f.both("leg_from_down", "max")
def knee_ext(f):         return f.both("knee", "max")
def squat_depth(f):      return 180 - f.both("knee", "mean")
def heel_lift(f):        return f.both("heel_lift", "mean")
def bridge(f):           return f["bridge_line"]
def hip_rise(f):         return f["hip_rise"]


def thigh_lift_seated(f):
    return {k: f[f"thigh_from_down_{k}"] - 90 for k in ("L", "R")}


def thigh_lift_standing(f):
    return {k: f[f"thigh_from_down_{k}"] for k in ("L", "R")}


def bird_dog_sides(f):
    """Diagonal pairs: left arm with right leg, right arm with left leg."""
    return {"L": np.minimum(f["arm_from_down_L"], f["thigh_from_down_R"]),
            "R": np.minimum(f["arm_from_down_R"], f["thigh_from_down_L"])}


# ---------------------------------------------------------------------------
# the 15 exercises
# ---------------------------------------------------------------------------

EXERCISES: dict[str, ExerciseSpec] = {}


def add(spec: ExerciseSpec):
    EXERCISES[spec.key] = spec


# ---- Trained-model exercises (the rules also give the feedback text) ------

add(ExerciseSpec(
    key="sit_to_stand", name="Sit-to-Stand", view="side", required=WHOLE,
    signal=knees, rest=115, active=150, target=165,
    mistakes=[
        Mistake("hands_used", "Keep your arms crossed over your chest; try to stand up without pushing on your legs or the chair.",
                lambda f, r: min(rep_min(f["wrist_thigh_L"], r), rep_min(f["wrist_thigh_R"], r)) < 0.25),
        Mistake("incomplete_stand", "Stand up fully: straighten your hips and knees at the top.",
                lambda f, r: rep_max(knees(f), r) < 160 or rep_max(f.both("hip", "mean"), r) < 155),
        Mistake("no_forward_lean", "Lean your chest forward a little before you stand up.",
                lambda f, r: rep_max(f["lean_sagittal"], r) < 12),
        Mistake("uncontrolled_sit", "Sit down slowly and with control.",
                lambda f, r: phase_seconds(f.t, r)[1] < 1.0),
        Mistake("feet_forward", "Bring your feet back so your knees are above your ankles before you stand.",
                lambda f, r: f.both("shin_forward", "mean")[r.start] > 22),
    ]))

add(ExerciseSpec(
    key="shoulder_abduction", name="Shoulder Abduction", view="front", required=UPPER,
    signal=arm_elev, rest=30, active=55, target=80,
    mistakes=[
        Mistake("low_range", "Raise your arms higher, up to shoulder height.", peak_below(arm_elev, 72)),
        Mistake("bent_elbow", "Keep your elbows straight as you lift.",
                lambda f, r: at_peak(f.both("elbow", "min"), r) < 150),
        Mistake("uneven_arms", "Lift both arms together to the same height.",
                lambda f, r: abs(at_peak(f["shoulder_elev_L"], r) - at_peak(f["shoulder_elev_R"], r)) > 15),
        Mistake("trunk_lean", "Keep your body upright; do not lean to the side.",
                lambda f, r: rep_max(f["lean_lateral"], r) > 10),
        Mistake("shoulder_shrug", "Relax your shoulders down, away from your ears.",
                lambda f, r: at_peak(f["shrug"], r) < 0.85 * f["shrug"][r.start]),
    ]))

add(ExerciseSpec(
    key="shoulder_flexion", name="Shoulder Flexion", view="side", required=UPPER,
    signal=arm_elev_max, rest=30, active=55, target=80,
    mistakes=[
        Mistake("low_range", "Raise your arms higher, up to shoulder height.", peak_below(arm_elev_max, 72)),
        Mistake("bent_elbow", "Keep your elbows straight as you lift.",
                lambda f, r: at_peak(f.both("elbow", "max"), r) < 150),
        Mistake("back_arch", "Keep your back still; do not lean backwards as your arms go up.",
                lambda f, r: rep_min(f["lean_sagittal"], r) < -10),
        Mistake("swinging", "Lift slowly and pause at the top instead of swinging.",
                lambda f, r: phase_seconds(f.t, r)[0] < 0.6
                or hold_seconds(arm_elev_max(f), f.t, r, 8) < 0.3),
        Mistake("trunk_forward", "Stand tall; do not bend forward at the waist.",
                lambda f, r: rep_max(f["lean_sagittal"], r) > 15),
    ]))

add(ExerciseSpec(
    key="hip_abduction", name="Standing Hip Abduction", view="front", required=LOWER + [L_SHOULDER, R_SHOULDER],
    signal=leg_raise, rest=10, active=18, target=25,
    mistakes=[
        Mistake("trunk_lean", "Keep your body upright; do not lean away from the lifting leg.",
                lambda f, r: rep_max(f["lean_lateral"], r) > 10),
        Mistake("low_range", "Lift your leg a little further out to the side.", peak_below(leg_raise, 20)),
        Mistake("leg_forward", "Lift the leg straight out to the side, not forwards.",
                lambda f, r: at_peak(f[f"leg_len_{moving_leg(f, r, 'leg_from_down')}"], r) < 0.88),
        Mistake("bent_knee", "Keep the knee of the lifting leg straight.",
                lambda f, r: at_peak(f[f"knee_{moving_leg(f, r, 'leg_from_down')}"], r) < 160),
        Mistake("toes_up", "Keep your toes pointing forwards.",
                lambda f, r: at_peak(f[f"foot_turn_{moving_leg(f, r, 'leg_from_down')}"], r) > 0.6),
    ]))

add(ExerciseSpec(
    key="knee_extension", name="Seated Knee Extension", view="side", required=LOWER + [L_SHOULDER, R_SHOULDER],
    signal=knee_ext, rest=125, active=145, target=160,
    mistakes=[
        Mistake("incomplete_extension", "Straighten your knee fully, until the leg is level with your hip.",
                peak_below(knee_ext, 155)),
        Mistake("slouching", "Sit up straight with your back against the chair.",
                lambda f, r: rep_min(f["lean_sagittal"], r) < -12),
        Mistake("thigh_lift", "Keep your thigh resting on the seat; only the lower leg moves.",
                lambda f, r: rep_max(f[f"thigh_from_down_{moving_leg(f, r, 'knee')}"], r) - 90 > 15),
        Mistake("no_hold", "Hold the straight leg for 2 seconds before lowering it.", hold_below(knee_ext, 1.5, 8)),
        Mistake("leaning_forward", "Keep your upper body upright; do not lean towards your knee.",
                lambda f, r: rep_max(f["lean_sagittal"], r) > 15),
    ]))

# ---- Angle-rule exercises ---------------------------------------------------

add(ExerciseSpec(
    key="elbow_flexion", name="Elbow Flexion", view="side", required=UPPER,
    signal=elbow_flex, rest=40, active=70, target=110,
    mistakes=[
        Mistake("upper_arm_moves", "Keep your upper arms still against your body.",
                lambda f, r: at_peak(f.both("shoulder_elev", "max"), r) > 30),
        Mistake("low_range", "Bend your elbows further, bringing your hands up to your shoulders.", peak_below(elbow_flex, 95)),
        Mistake("body_swing", "Keep your body still; do not rock back to lift.",
                lambda f, r: rep_range(f["lean_sagittal"], r) > 10),
    ]))

add(ExerciseSpec(
    key="wall_push_up", name="Wall Push-Up", view="side", required=WHOLE,
    signal=elbow_flex, rest=30, active=45, target=65,
    mistakes=[
        Mistake("hips_sag", "Keep your body straight; do not let your hips drop towards the wall.",
                lambda f, r: rep_max(f["body_line_ankle"], r) > 0.12),
        Mistake("hips_back", "Keep your body straight; do not push your hips back.",
                lambda f, r: rep_min(f["body_line_ankle"], r) < -0.12),
        Mistake("low_range", "Bend your elbows more to bring your chest closer to the wall.", peak_below(elbow_flex, 55)),
    ]))

add(ExerciseSpec(
    key="heel_raise", name="Heel Raise", view="side", required=LOWER + FEET,
    signal=heel_lift, rest=0.03, active=0.06, target=0.10,
    mistakes=[
        Mistake("low_raise", "Rise higher onto your toes.", peak_below(heel_lift, 0.08)),
        Mistake("knees_bend", "Keep your knees straight as you rise.",
                lambda f, r: rep_min(f.both("knee", "mean"), r) < 165),
        Mistake("leaning_forward", "Rise straight up; do not lean forward onto the chair.",
                lambda f, r: rep_max(f["lean_sagittal"], r) > 12),
    ]))

add(ExerciseSpec(
    key="mini_squat", name="Mini Squat", view="side", required=LOWER + FEET + [L_SHOULDER, R_SHOULDER],
    signal=squat_depth, rest=8, active=15, target=25,
    mistakes=[
        Mistake("too_deep", "Only bend your knees a little, about a third of the way down.",
                lambda f, r: rep_max(squat_depth(f), r) > 60),
        Mistake("heels_lift", "Keep your heels on the floor.",
                lambda f, r: rep_max(heel_lift(f), r) > 0.06),
        Mistake("trunk_forward", "Keep your chest up.",
                lambda f, r: rep_max(f["lean_sagittal"], r) > 30),
    ]))

add(ExerciseSpec(
    key="seated_marching", name="Seated Marching", view="side", required=LOWER + [L_SHOULDER, R_SHOULDER, L_WRIST, R_WRIST],
    side_signals=thigh_lift_seated, rest=6, active=12, target=20,
    mistakes=[
        Mistake("low_knee_lift", "Lift your knees higher.",
                lambda f, r: rep_max(f[f"thigh_from_down_{r.side}"] - 90, r) < 16),
        Mistake("leaning_back", "Sit upright; do not lean back against the chair.",
                lambda f, r: rep_min(f["lean_sagittal"], r) < -12),
        Mistake("using_hands", "Lift your legs without pulling them up with your hands.",
                lambda f, r: at_peak(f.both("wrist_thigh", "min"), r) < 0.2),
    ]))

add(ExerciseSpec(
    key="glute_bridge", name="Glute Bridge", view="side", required=[L_SHOULDER, R_SHOULDER, L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANKLE, R_ANKLE],
    signal=bridge, rest=-0.30, active=-0.15, target=-0.05,
    mistakes=[
        Mistake("low_hips", "Lift your hips higher, until your body is straight from shoulders to knees.",
                peak_below(bridge, -0.10)),
        Mistake("over_arch", "Do not push your hips too high; keep your lower back from arching.",
                lambda f, r: rep_max(bridge(f), r) > 0.12),
        Mistake("feet_far", "Bring your feet closer to your buttocks.",
                lambda f, r: at_peak(f.both("knee", "mean"), r) > 115),
    ]))

add(ExerciseSpec(
    key="tandem_stance", name="Tandem Stance", view="front", required=LOWER + [L_SHOULDER, R_SHOULDER],
    kind="hold", hold_target_sec=15,
    mistakes=[
        # For a hold, the checks run on the whole clip (rep = full clip).
        Mistake("feet_not_in_line", "Place one foot directly in front of the other, heel touching toe.",
                lambda f, r: float(np.mean(f["feet_gap"] < 0.6)) < 0.7),
        Mistake("stepping_out", "Try to hold the position without stepping out.",
                lambda f, r: int(np.sum(np.diff((f["feet_gap"] < 0.6).astype(int)) != 0)) >= 2),
        Mistake("leaning", "Stand upright; do not lean on the counter or to the side.",
                lambda f, r: float(np.median(f["lean_lateral"])) > 8 or float(np.std(f["hip_sway"])) > 0.08),
    ]))

add(ExerciseSpec(
    key="bird_dog", name="Bird Dog", view="side", required=UPPER + [L_KNEE, R_KNEE],
    side_signals=bird_dog_sides, rest=30, active=55, target=75,
    mistakes=[
        Mistake("arm_leg_low", "Stretch your arm and leg further, until both are level with your back.",
                lambda f, r: rep_max(bird_dog_sides(f)[r.side], r) < 70),
        Mistake("back_sag", "Keep your back flat and your hips level.",
                lambda f, r: rep_max(np.abs(f["trunk_from_horizontal"]), r) > 15),
        Mistake("no_hold", "Hold the stretched position for 2 seconds.",
                lambda f, r: hold_seconds(bird_dog_sides(f)[r.side], f.t, r, 10) < 1.5),
    ]))

add(ExerciseSpec(
    key="step_up", name="Step-Up", view="side", required=WHOLE,
    signal=hip_rise, rest=0.08, active=0.16, target=0.22,
    mistakes=[
        Mistake("trunk_forward", "Keep your chest up as you step.",
                lambda f, r: rep_max(f["lean_sagittal"], r) > 25),
        Mistake("knee_not_straight", "Straighten your leading leg fully at the top.",
                lambda f, r: at_peak(f.both("knee", "max"), r) < 165),
        Mistake("drop_down", "Step down slowly and with control.",
                lambda f, r: phase_seconds(f.t, r)[1] < 0.6),
    ]))

add(ExerciseSpec(
    key="march_in_place", name="March in Place", view="side", required=WHOLE,
    side_signals=thigh_lift_standing, rest=15, active=25, target=45,
    mistakes=[
        Mistake("low_knee_lift", "Lift your knees higher.",
                lambda f, r: rep_max(f[f"thigh_from_down_{r.side}"], r) < 35),
        Mistake("leaning_back", "Stand tall; do not lean backwards.",
                lambda f, r: rep_min(f["lean_sagittal"], r) < -10),
        Mistake("no_arm_swing", "Swing your arms as you march.",
                lambda f, r: rep_range(f.both("shoulder_elev", "max"), r) < 12),
    ]))


def get(key: str) -> ExerciseSpec:
    if key not in EXERCISES:
        raise KeyError(key)
    return EXERCISES[key]
