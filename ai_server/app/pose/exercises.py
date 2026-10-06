"""Posture rules for every catalogue exercise (pose_key).

Each exercise defines:
  * the landmarks that must be visible (FR300_17),
  * one signal that rises during a repetition, with rest / active levels for counting,
  * the target the signal should reach,
  * mistake checks per repetition. Mistake labels match fyp-notes/Recording_Guide.pdf,
    so the labelled clips test exactly the rule they are named after.

Every mistake is a MEASUREMENT (e.g. "largest sideways trunk lean in the repetition, degrees"),
a LIMIT and a DIRECTION (mistake when above, or when below, the limit). The limits below are
starting values; training/tune_rules.py picks better ones from labelled clips and writes them to
thresholds.json next to this file, which overrides these defaults when the server starts.
"""
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

import numpy as np

from .geometry import Features
from .landmarks import (
    L_ANKLE, L_ELBOW, L_FOOT, L_HEEL, L_HIP, L_KNEE, L_SHOULDER, L_WRIST, NOSE,
    R_ANKLE, R_ELBOW, R_FOOT, R_HEEL, R_HIP, R_KNEE, R_SHOULDER, R_WRIST,
)
from .reps import Rep, hold_seconds, phase_seconds

UPPER = [L_SHOULDER, R_SHOULDER, L_ELBOW, R_ELBOW, L_WRIST, R_WRIST, L_HIP, R_HIP]
LOWER = [L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANKLE, R_ANKLE]
FEET = [L_HEEL, R_HEEL, L_FOOT, R_FOOT]
WHOLE = [NOSE] + UPPER + LOWER[2:]
THRESHOLDS_FILE = Path(__file__).with_name("thresholds.json")

Measure = Callable[[Features, Rep], float]


@dataclass
class Mistake:
    label: str
    feedback: str
    measure: Measure
    limit: float
    above: bool          # True: mistake when measure > limit; False: when measure < limit
    unit: str = ""

    def value(self, f: Features, r: Rep) -> float:
        return float(self.measure(f, r))

    def check(self, f: Features, r: Rep) -> bool:
        v = self.value(f, r)
        return v > self.limit if self.above else v < self.limit

    def describe(self) -> str:
        return f"{self.label}: mistake when {'above' if self.above else 'below'} {self.limit:g} {self.unit}".strip()


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


def M(label, feedback, measure, limit, above, unit=""):
    return Mistake(label, feedback, measure, limit, above, unit)


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


def moving(f: Features, r: Rep, signal: str) -> str:
    """The side that moved in this rep: the rep's own side, or the one with the larger range."""
    if r.side:
        return r.side
    return "L" if rep_range(f[f"{signal}_L"], r) >= rep_range(f[f"{signal}_R"], r) else "R"


def peak_of(signal: Callable[[Features], np.ndarray]) -> Measure:
    return lambda f, r: rep_max(signal(f), r)


def hold_of(signal: Callable[[Features], np.ndarray], tol: float) -> Measure:
    return lambda f, r: hold_seconds(signal(f), f.t, r, tol)


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
        M("hands_used", "Keep your arms crossed over your chest; try to stand up without pushing on your legs or the chair.",
          lambda f, r: min(rep_min(f["wrist_thigh_L"], r), rep_min(f["wrist_thigh_R"], r)), 0.25, False, "torso lengths"),
        M("incomplete_stand", "Stand up fully: straighten your hips and knees at the top.",
          peak_of(knees), 160, False, "degrees"),
        M("no_forward_lean", "Lean your chest forward a little before you stand up.",
          lambda f, r: rep_max(f["lean_sagittal"], r), 12, False, "degrees"),
        M("uncontrolled_sit", "Sit down slowly and with control.",
          lambda f, r: phase_seconds(f.t, r)[1], 1.0, False, "seconds"),
        M("feet_forward", "Bring your feet back so your knees are above your ankles before you stand.",
          lambda f, r: float(f.both("shin_forward", "mean")[r.start]), 22, True, "degrees"),
    ]))

add(ExerciseSpec(
    key="shoulder_abduction", name="Shoulder Abduction", view="front", required=UPPER,
    signal=arm_elev, rest=30, active=55, target=80,
    mistakes=[
        M("low_range", "Raise your arms higher, up to shoulder height.", peak_of(arm_elev), 72, False, "degrees"),
        M("bent_elbow", "Keep your elbows straight as you lift.",
          lambda f, r: at_peak(f.both("elbow", "min"), r), 150, False, "degrees"),
        M("uneven_arms", "Lift both arms together to the same height.",
          lambda f, r: abs(at_peak(f["shoulder_elev_L"], r) - at_peak(f["shoulder_elev_R"], r)), 15, True, "degrees"),
        M("trunk_lean", "Keep your body upright; do not lean to the side.",
          lambda f, r: rep_max(f["lean_lateral"], r), 10, True, "degrees"),
        M("shoulder_shrug", "Relax your shoulders down, away from your ears.",
          lambda f, r: at_peak(f["shrug"], r) / max(float(f["shrug"][r.start]), 1e-6), 0.85, False, "ratio"),
    ]))

add(ExerciseSpec(
    key="shoulder_flexion", name="Shoulder Flexion", view="side", required=UPPER,
    signal=arm_elev_max, rest=30, active=55, target=80,
    mistakes=[
        M("low_range", "Raise your arms higher, up to shoulder height.", peak_of(arm_elev_max), 72, False, "degrees"),
        M("bent_elbow", "Keep your elbows straight as you lift.",
          lambda f, r: at_peak(f.both("elbow", "max"), r), 150, False, "degrees"),
        M("back_arch", "Keep your back still; do not lean backwards as your arms go up.",
          lambda f, r: rep_min(f["lean_sagittal"], r), -10, False, "degrees"),
        M("swinging", "Lift slowly and pause at the top instead of swinging.",
          lambda f, r: phase_seconds(f.t, r)[0], 0.6, False, "seconds"),
        M("trunk_forward", "Stand tall; do not bend forward at the waist.",
          lambda f, r: rep_max(f["lean_sagittal"], r), 15, True, "degrees"),
    ]))

add(ExerciseSpec(
    key="hip_abduction", name="Standing Hip Abduction", view="front", required=LOWER + [L_SHOULDER, R_SHOULDER],
    signal=leg_raise, rest=10, active=18, target=25,
    mistakes=[
        M("trunk_lean", "Keep your body upright; do not lean away from the lifting leg.",
          lambda f, r: rep_max(f["lean_lateral"], r), 10, True, "degrees"),
        M("low_range", "Lift your leg a little further out to the side.", peak_of(leg_raise), 20, False, "degrees"),
        M("leg_forward", "Lift the leg straight out to the side, not forwards.",
          lambda f, r: at_peak(f[f"leg_len_{moving(f, r, 'leg_from_down')}"], r), 0.88, False, "ratio"),
        M("bent_knee", "Keep the knee of the lifting leg straight.",
          lambda f, r: at_peak(f[f"knee_{moving(f, r, 'leg_from_down')}"], r), 160, False, "degrees"),
        M("toes_up", "Keep your toes pointing forwards.",
          lambda f, r: at_peak(f[f"foot_turn_{moving(f, r, 'leg_from_down')}"], r), 0.6, True, "ratio"),
    ]))

add(ExerciseSpec(
    key="knee_extension", name="Seated Knee Extension", view="side", required=LOWER + [L_SHOULDER, R_SHOULDER],
    signal=knee_ext, rest=125, active=145, target=160,
    mistakes=[
        M("incomplete_extension", "Straighten your knee fully, until the leg is level with your hip.",
          peak_of(knee_ext), 155, False, "degrees"),
        M("slouching", "Sit up straight with your back against the chair.",
          lambda f, r: rep_min(f["lean_sagittal"], r), -12, False, "degrees"),
        M("thigh_lift", "Keep your thigh resting on the seat; only the lower leg moves.",
          lambda f, r: rep_max(f[f"thigh_from_down_{moving(f, r, 'knee')}"], r) - 90, 15, True, "degrees"),
        M("no_hold", "Hold the straight leg for 2 seconds before lowering it.", hold_of(knee_ext, 8), 1.5, False, "seconds"),
        M("leaning_forward", "Keep your upper body upright; do not lean towards your knee.",
          lambda f, r: rep_max(f["lean_sagittal"], r), 15, True, "degrees"),
    ]))

# ---- Angle-rule exercises ---------------------------------------------------

add(ExerciseSpec(
    key="elbow_flexion", name="Elbow Flexion", view="side", required=UPPER,
    signal=elbow_flex, rest=40, active=70, target=110,
    mistakes=[
        M("upper_arm_moves", "Keep your upper arms still against your body.",
          lambda f, r: at_peak(f.both("shoulder_elev", "max"), r), 30, True, "degrees"),
        M("low_range", "Bend your elbows further, bringing your hands up to your shoulders.",
          peak_of(elbow_flex), 95, False, "degrees"),
        M("body_swing", "Keep your body still; do not rock back to lift.",
          lambda f, r: rep_range(f["lean_sagittal"], r), 10, True, "degrees"),
    ]))

add(ExerciseSpec(
    key="wall_push_up", name="Wall Push-Up", view="side", required=WHOLE,
    signal=elbow_flex, rest=30, active=45, target=65,
    mistakes=[
        M("hips_sag", "Keep your body straight; do not let your hips drop towards the wall.",
          lambda f, r: rep_max(f["body_line_ankle"], r), 0.12, True, "torso lengths"),
        M("hips_back", "Keep your body straight; do not push your hips back.",
          lambda f, r: rep_min(f["body_line_ankle"], r), -0.12, False, "torso lengths"),
        M("low_range", "Bend your elbows more to bring your chest closer to the wall.", peak_of(elbow_flex), 55, False, "degrees"),
    ]))

add(ExerciseSpec(
    key="heel_raise", name="Heel Raise", view="side", required=LOWER + FEET,
    signal=heel_lift, rest=0.03, active=0.06, target=0.10,
    mistakes=[
        M("low_raise", "Rise higher onto your toes.", peak_of(heel_lift), 0.08, False, "shin lengths"),
        M("knees_bend", "Keep your knees straight as you rise.",
          lambda f, r: rep_min(f.both("knee", "mean"), r), 165, False, "degrees"),
        M("leaning_forward", "Rise straight up; do not lean forward onto the chair.",
          lambda f, r: rep_max(f["lean_sagittal"], r), 12, True, "degrees"),
    ]))

add(ExerciseSpec(
    key="mini_squat", name="Mini Squat", view="side", required=LOWER + FEET + [L_SHOULDER, R_SHOULDER],
    signal=squat_depth, rest=8, active=15, target=25,
    mistakes=[
        M("too_deep", "Only bend your knees a little, about a third of the way down.", peak_of(squat_depth), 60, True, "degrees"),
        M("heels_lift", "Keep your heels on the floor.", peak_of(heel_lift), 0.06, True, "shin lengths"),
        M("trunk_forward", "Keep your chest up.", lambda f, r: rep_max(f["lean_sagittal"], r), 30, True, "degrees"),
    ]))

add(ExerciseSpec(
    key="seated_marching", name="Seated Marching", view="side", required=LOWER + [L_SHOULDER, R_SHOULDER, L_WRIST, R_WRIST],
    side_signals=thigh_lift_seated, rest=6, active=12, target=20,
    mistakes=[
        M("low_knee_lift", "Lift your knees higher.",
          lambda f, r: rep_max(f[f"thigh_from_down_{r.side or 'L'}"] - 90, r), 16, False, "degrees"),
        M("leaning_back", "Sit upright; do not lean back against the chair.",
          lambda f, r: rep_min(f["lean_sagittal"], r), -12, False, "degrees"),
        M("using_hands", "Lift your legs without pulling them up with your hands.",
          lambda f, r: at_peak(f.both("wrist_thigh", "min"), r), 0.2, False, "torso lengths"),
    ]))

add(ExerciseSpec(
    key="glute_bridge", name="Glute Bridge", view="side",
    required=[L_SHOULDER, R_SHOULDER, L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANKLE, R_ANKLE],
    signal=bridge, rest=-0.30, active=-0.15, target=-0.05,
    mistakes=[
        M("low_hips", "Lift your hips higher, until your body is straight from shoulders to knees.",
          peak_of(bridge), -0.10, False, "torso lengths"),
        M("over_arch", "Do not push your hips too high; keep your lower back from arching.",
          peak_of(bridge), 0.12, True, "torso lengths"),
        M("feet_far", "Bring your feet closer to your buttocks.",
          lambda f, r: at_peak(f.both("knee", "mean"), r), 115, True, "degrees"),
    ]))

add(ExerciseSpec(
    key="tandem_stance", name="Tandem Stance", view="front", required=LOWER + [L_SHOULDER, R_SHOULDER],
    kind="hold", hold_target_sec=15,
    mistakes=[
        # For a hold, the checks run on the whole clip (rep = full clip).
        M("feet_not_in_line", "Place one foot directly in front of the other, heel touching toe.",
          lambda f, r: float(np.mean(f["feet_gap"] < 0.6)), 0.7, False, "share of time"),
        M("stepping_out", "Try to hold the position without stepping out.",
          lambda f, r: float(np.sum(np.diff((f["feet_gap"] < 0.6).astype(int)) != 0)), 1.5, True, "changes"),
        M("leaning", "Stand upright; do not lean on the counter or to the side.",
          lambda f, r: float(np.median(f["lean_lateral"])), 8, True, "degrees"),
    ]))

add(ExerciseSpec(
    key="bird_dog", name="Bird Dog", view="side", required=UPPER + [L_KNEE, R_KNEE],
    side_signals=bird_dog_sides, rest=30, active=55, target=75,
    mistakes=[
        M("arm_leg_low", "Stretch your arm and leg further, until both are level with your back.",
          lambda f, r: rep_max(bird_dog_sides(f)[r.side or "L"], r), 70, False, "degrees"),
        M("back_sag", "Keep your back flat and your hips level.",
          lambda f, r: rep_max(np.abs(f["trunk_from_horizontal"]), r), 15, True, "degrees"),
        M("no_hold", "Hold the stretched position for 2 seconds.",
          lambda f, r: hold_seconds(bird_dog_sides(f)[r.side or "L"], f.t, r, 10), 1.5, False, "seconds"),
    ]))

add(ExerciseSpec(
    key="step_up", name="Step-Up", view="side", required=WHOLE,
    signal=hip_rise, rest=0.08, active=0.16, target=0.22,
    mistakes=[
        M("trunk_forward", "Keep your chest up as you step.", lambda f, r: rep_max(f["lean_sagittal"], r), 25, True, "degrees"),
        M("knee_not_straight", "Straighten your leading leg fully at the top.",
          lambda f, r: at_peak(f.both("knee", "max"), r), 165, False, "degrees"),
        M("drop_down", "Step down slowly and with control.", lambda f, r: phase_seconds(f.t, r)[1], 0.6, False, "seconds"),
    ]))

add(ExerciseSpec(
    key="march_in_place", name="March in Place", view="side", required=WHOLE,
    side_signals=thigh_lift_standing, rest=15, active=25, target=45,
    mistakes=[
        M("low_knee_lift", "Lift your knees higher.",
          lambda f, r: rep_max(f[f"thigh_from_down_{r.side or 'L'}"], r), 35, False, "degrees"),
        M("leaning_back", "Stand tall; do not lean backwards.", lambda f, r: rep_min(f["lean_sagittal"], r), -10, False, "degrees"),
        M("no_arm_swing", "Swing your arms as you march.",
          lambda f, r: rep_range(f.both("shoulder_elev", "max"), r), 12, False, "degrees"),
    ]))


# ---------------------------------------------------------------------------
# tuned limits
# ---------------------------------------------------------------------------

def apply_thresholds(path: Path = THRESHOLDS_FILE) -> dict:
    """Overrides limits from thresholds.json: {"<pose_key>.<mistake>": limit, "<pose_key>.rest": v, ...}."""
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    for name, value in data.get("limits", {}).items():
        key, _, part = name.partition(".")
        spec = EXERCISES.get(key)
        if spec is None:
            continue
        if part in ("rest", "active", "target"):
            setattr(spec, part, float(value))
            continue
        for m in spec.mistakes:
            if m.label == part:
                m.limit = float(value)
    return data


TUNED = apply_thresholds()


def get(key: str) -> ExerciseSpec:
    if key not in EXERCISES:
        raise KeyError(key)
    return EXERCISES[key]
