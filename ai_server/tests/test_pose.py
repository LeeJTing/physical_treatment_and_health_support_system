"""Posture pipeline tests on synthetic skeletons with known joint angles,
plus /pose request validation. Real-clip accuracy is measured separately
with training/evaluate_rules.py once the labelled clips exist."""
import math

import cv2
import numpy as np
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.pose import exercises
from app.pose.analyse import PoseError, analyse
from app.pose.geometry import Features, angle3
from app.pose.landmarks import (
    L_ANKLE, L_ELBOW, L_FOOT, L_HEEL, L_HIP, L_KNEE, L_SHOULDER, L_WRIST, NOSE,
    R_ANKLE, R_ELBOW, R_FOOT, R_HEEL, R_HIP, R_KNEE, R_SHOULDER, R_WRIST, PoseSequence, VideoInfo,
)
from app.pose.reps import Rep, find_reps, hold_seconds

client = TestClient(app)
DEV = {"Authorization": "Bearer dev-token"}
W, H, FPS = 720, 1280, 10.0


def rot(v, deg):
    a = math.radians(deg)
    return np.array([v[0] * math.cos(a) - v[1] * math.sin(a), v[0] * math.sin(a) + v[1] * math.cos(a)])


def limb(origin, direction_deg, length):
    """Point at `length` from origin; 0 deg = straight down, positive = towards image right."""
    return origin + rot(np.array([0.0, length]), -direction_deg)


def front_pose(arm_L=0.0, arm_R=0.0, elbow_bend=0.0, lean=0.0, shrug=0.0, feet_gap=60.0):
    """Standing, facing the camera. arm_* = arm raise to the side (0 down, 90 level)."""
    p = np.zeros((33, 2))
    hip_mid = np.array([W / 2, 700.0])
    trunk_up = rot(np.array([0.0, -260.0]), lean)
    sh_mid = hip_mid + trunk_up
    p[L_HIP], p[R_HIP] = hip_mid + [40, 0], hip_mid - [40, 0]
    p[L_SHOULDER], p[R_SHOULDER] = sh_mid + [70, -shrug], sh_mid - [70, shrug]
    p[NOSE] = sh_mid + [0, -110]
    for sh, el, wr, sign in ((L_SHOULDER, L_ELBOW, L_WRIST, 1), (R_SHOULDER, R_ELBOW, R_WRIST, -1)):
        a = arm_L if sign == 1 else arm_R
        p[el] = limb(p[sh], sign * a, 130)
        p[wr] = limb(p[el], sign * (a + elbow_bend), 120)
    for hip, kn, an, he, ft, dx in ((L_HIP, L_KNEE, L_ANKLE, L_HEEL, L_FOOT, 1), (R_HIP, R_KNEE, R_ANKLE, R_HEEL, R_FOOT, -1)):
        p[an] = np.array([W / 2 + dx * feet_gap / 2, 1180.0])
        p[kn] = (p[hip] + p[an]) / 2
        p[he], p[ft] = p[an] + [0, 15], p[an] + [0, 25]
    return p


def side_seated(knee_L=90.0, lean=0.0, thigh_lift=0.0):
    """Sitting, side view, facing image right. knee_L = knee angle (90 bent, 180 straight)."""
    p = np.zeros((33, 2))
    hip = np.array([180.0, 750.0])
    sh = hip + rot(np.array([0.0, -260.0]), lean)  # + lean = forward (towards the right)
    p[L_HIP] = p[R_HIP] = hip
    p[L_SHOULDER] = p[R_SHOULDER] = sh
    p[NOSE] = sh + [40, -110]
    for el, wr, sh_i in ((L_ELBOW, L_WRIST, L_SHOULDER), (R_ELBOW, R_WRIST, R_SHOULDER)):
        p[el] = sh + [0, 130]
        p[wr] = p[el] + [60, 60]
    for kn, an, he, ft, k_ang in ((L_KNEE, L_ANKLE, L_HEEL, L_FOOT, knee_L), (R_KNEE, R_ANKLE, R_HEEL, R_FOOT, 90.0)):
        thigh_dir = 90 + (thigh_lift if kn == L_KNEE else 0)        # 90 = level, pointing right
        p[kn] = limb(hip, thigh_dir, 230)
        p[an] = limb(p[kn], thigh_dir - (180 - k_ang), 220)
        p[he] = p[an] + [-10, 10]
        p[ft] = p[an] + [30, 10]
    return p


def sequence(frames):
    xy = np.stack(frames).astype(np.float32)
    n = len(frames)
    return PoseSequence(xy=xy, vis=np.ones((n, 33), np.float32), t=np.arange(n, dtype=np.float32) / FPS,
                        info=VideoInfo(FPS, n, W, H))


def wave(n_reps, rest, peak, rep_sec=3.0, pause_sec=1.0, hold_sec=0.0):
    """Rest -> rise -> (hold) -> fall, repeated, sampled at FPS."""
    out = [rest] * int(pause_sec * FPS)
    for _ in range(n_reps):
        up = int(rep_sec / 2 * FPS)
        out += [rest + (peak - rest) * (1 - math.cos(math.pi * i / up)) / 2 for i in range(up)]
        out += [peak] * int(hold_sec * FPS)
        out += [peak - (peak - rest) * (1 - math.cos(math.pi * i / up)) / 2 for i in range(up)]
        out += [rest] * int(pause_sec * FPS)
    return out


# ---- building blocks ---------------------------------------------------------

def test_angle3_straight_and_right_angle():
    a, b = np.array([[0.0, 0.0]]), np.array([[0.0, 1.0]])
    assert angle3(a, b, np.array([[0.0, 2.0]]))[0] == pytest.approx(180, abs=0.01)
    assert angle3(a, b, np.array([[1.0, 1.0]]))[0] == pytest.approx(90)


def test_find_reps_counts_and_ignores_jitter():
    sig = np.array(wave(3, 10, 90) + [12, 14, 11, 13, 10])
    t = np.arange(len(sig)) / FPS
    assert len(find_reps(sig, t, rest=30, active=55)) == 3


def test_hold_seconds():
    sig = np.array(wave(1, 0, 100, hold_sec=2.0))
    t = np.arange(len(sig)) / FPS
    rep = find_reps(sig, t, 20, 50)[0]
    assert hold_seconds(sig, t, rep, tolerance=5) >= 1.9


def test_every_catalogue_exercise_has_rules():
    import json
    from pathlib import Path
    cat = json.loads((Path(__file__).parents[2] / "assets" / "seed" / "catalogue.json").read_text(encoding="utf-8"))
    keys = {e["pose_key"] for e in cat["exercises"]}
    assert None not in keys and keys == set(exercises.EXERCISES)


def test_mistake_labels_are_unique_per_exercise():
    for spec in exercises.EXERCISES.values():
        labels = [m.label for m in spec.mistakes]
        assert len(labels) == len(set(labels)), spec.key


# ---- shoulder abduction (front view) ----------------------------------------

def test_shoulder_abduction_correct_form():
    res = analyse("shoulder_abduction", sequence([front_pose(a, a) for a in wave(5, 5, 88)]), use_model=False)
    assert res["repetitions"] == 5
    assert res["mistakes"] == {} and res["accuracy"] == 100
    assert res["feedback"] == ["Good form. Keep it up!"]


@pytest.mark.parametrize("label, frames", [
    ("low_range", [front_pose(a, a) for a in wave(4, 5, 62)]),
    ("bent_elbow", [front_pose(a, a, elbow_bend=60 * a / 88) for a in wave(4, 5, 88)]),
    ("uneven_arms", [front_pose(a, a * 0.7) for a in wave(4, 5, 88)]),
    ("trunk_lean", [front_pose(a, a, lean=15 * a / 88) for a in wave(4, 5, 88)]),
])
def test_shoulder_abduction_mistakes(label, frames):
    res = analyse("shoulder_abduction", sequence(frames), use_model=False)
    assert label in res["mistakes"], res["mistakes"]
    assert res["accuracy"] < 100


def _with_ears(p, tilt=0.0, lean=0.0):
    """Ears 35 px either side of the head; tilt (deg) turns the head, lean the whole upper body."""
    from app.pose.landmarks import L_EAR, R_EAR
    p = p.copy()
    head = p[NOSE] + [0, 10]
    half = rot(np.array([35.0, 0.0]), tilt + lean)
    p[L_EAR], p[R_EAR] = head + half, head - half
    return p


def test_shoulder_abduction_head_tilt_beyond_the_trunk():
    # REHAB26-ViewAngles, 9 Oct: "head tilted to side" while lifting.
    tilted = [_with_ears(front_pose(a, a), tilt=20 * a / 88) for a in wave(4, 5, 88)]
    assert "head_tilt" in analyse("shoulder_abduction", sequence(tilted), use_model=False)["mistakes"]
    level = [_with_ears(front_pose(a, a)) for a in wave(4, 5, 88)]
    assert analyse("shoulder_abduction", sequence(level), use_model=False)["mistakes"] == {}
    # A whole-body lean turns the ears with the trunk: reported as trunk_lean only.
    leaning = [_with_ears(front_pose(a, a, lean=15 * a / 88), lean=15 * a / 88) for a in wave(4, 5, 88)]
    m = analyse("shoulder_abduction", sequence(leaning), use_model=False)["mistakes"]
    assert "trunk_lean" in m and "head_tilt" not in m


# ---- wrist and hand (hand landmarks, 9 Oct) ------------------------------------

def _hand(openness=1.0, spread_deg=0.0, lift_deg=90.0, origin=(360.0, 900.0), palm=80.0):
    """21 MediaPipe hand points: wrist at origin, the hand pointing lift_deg above level (90 = up),
    fingertips at openness x palm from the wrist, index and little finger spread_deg either side."""
    h = np.full((21, 2), np.nan)
    o = np.array(origin)

    def towards(deg, length):
        a = math.radians(deg)
        return o + length * np.array([math.cos(a), -math.sin(a)])

    h[0] = o
    for mcp, tip, off in ((5, 8, -1.0), (9, 12, -1 / 3), (13, 16, 1 / 3), (17, 20, 1.0)):
        h[mcp] = towards(lift_deg - off * 12, palm)
        h[tip] = towards(lift_deg - off * spread_deg, openness * palm)
        for k, w in ((1, 1 / 3), (2, 2 / 3)):
            h[mcp + k] = h[mcp] + w * (h[tip] - h[mcp])
    h[1:5] = [towards(lift_deg + 40, palm * s) for s in (0.3, 0.6, 0.8, 1.0)]
    return h


def _hand_sequence(hands):
    seq = sequence([front_pose()] * len(hands))
    seq.hands = np.full((len(hands), 2, 21, 2), np.nan, np.float32)
    seq.hands[:, 0] = np.stack(hands)
    return seq


def test_hand_open_close_counts_openings_and_checks_the_spread():
    good = [_hand(o, 20 * (o - 0.95)) for o in wave(5, 0.95, 2.0)]
    res = analyse("hand_open_close", _hand_sequence(good), use_model=False)
    assert res["repetitions"] == 5 and res["mistakes"] == {}, res["mistakes"]
    together = [_hand(o, 3) for o in wave(5, 0.95, 2.0)]          # opens fully, fingers kept together
    res = analyse("hand_open_close", _hand_sequence(together), use_model=False)
    assert "fingers_not_spread" in res["mistakes"] and "low_range" not in res["mistakes"]
    small = [_hand(o, 20 * (o - 0.95)) for o in wave(5, 0.95, 1.65)]
    assert "low_range" in analyse("hand_open_close", _hand_sequence(small), use_model=False)["mistakes"]


def test_wrist_extension_counts_lifts_and_low_ones():
    full = [_hand(1.9, 10, lift) for lift in wave(5, -30, 75)]
    res = analyse("wrist_extension", _hand_sequence(full), use_model=False)
    assert res["repetitions"] == 5 and res["mistakes"] == {}, res["mistakes"]
    low = [_hand(1.9, 10, lift) for lift in wave(5, -30, 45)]
    assert "low_range" in analyse("wrist_extension", _hand_sequence(low), use_model=False)["mistakes"]


def test_hand_exercises_need_a_hand_in_the_picture():
    with pytest.raises(PoseError) as e:
        analyse("hand_open_close", sequence([front_pose()] * 60), use_model=False)
    assert e.value.code == "hand_not_visible"


# ---- seated knee extension (side view) --------------------------------------

def test_knee_extension_correct_with_hold():
    res = analyse("knee_extension", sequence([side_seated(k) for k in wave(4, 90, 175, hold_sec=2.0)]), use_model=False)
    assert res["repetitions"] == 4 and res["mistakes"] == {}


def test_knee_extension_no_hold_and_incomplete():
    # A real no-hold kick is quick (Elwin's clips: 0.3 s near the top; limit tuned to 0.59 s).
    no_hold = analyse("knee_extension", sequence([side_seated(k) for k in wave(4, 90, 175, rep_sec=1.5)]),
                      use_model=False)
    assert "no_hold" in no_hold["mistakes"]
    half = analyse("knee_extension", sequence([side_seated(k) for k in wave(4, 90, 148, hold_sec=2.0)]), use_model=False)
    assert "incomplete_extension" in half["mistakes"]


def test_knee_extension_slouching():
    res = analyse("knee_extension",
                  # limit tuned to -29 deg on Elwin's clips (his chair reclines ~20 deg, slouching ~-39)
                  sequence([side_seated(k, lean=-35) for k in wave(4, 90, 175, hold_sec=2.0)]), use_model=False)
    assert "slouching" in res["mistakes"]


# ---- tandem stance (hold) ----------------------------------------------------

def test_tandem_stance_hold():
    good = analyse("tandem_stance", sequence([front_pose(feet_gap=5)] * 200), use_model=False)
    assert good["hold_seconds"] >= 15 and good["accuracy"] == 100
    bad = analyse("tandem_stance", sequence([front_pose(feet_gap=90)] * 200), use_model=False)
    assert "feet_not_in_line" in bad["mistakes"] and bad["accuracy"] < 50


# ---- errors ------------------------------------------------------------------

def test_no_person_is_pose_not_detected():
    seq = sequence([front_pose()] * 50)
    seq.xy[:] = np.nan
    seq.vis[:] = 0
    with pytest.raises(PoseError) as e:
        analyse("shoulder_abduction", seq, use_model=False)
    assert e.value.code == "pose_not_detected"


def test_body_outside_picture_is_full_body_not_visible():
    frames = [front_pose(a, a) for a in wave(4, 5, 88)]
    for p in frames:
        p[:, 1] += 600  # feet and legs below the bottom edge
    with pytest.raises(PoseError) as e:
        analyse("hip_abduction", sequence(frames), use_model=False)
    assert e.value.code == "full_body_not_visible"


def test_side_view_with_far_limbs_hidden_is_still_analysed():
    # Filmed from the side, the far arm and leg are behind the body (MediaPipe visibility ~0.06
    # on real clips). That must not count as "whole body not visible".
    seq = sequence([side_seated(k) for k in wave(4, 90, 175, hold_sec=2.0)])
    seq.vis[:, [R_ELBOW, R_WRIST, R_KNEE, R_ANKLE]] = 0.06
    assert analyse("knee_extension", seq, use_model=False)["repetitions"] >= 3
    front = sequence([front_pose(a, a) for a in wave(4, 5, 88)])
    front.vis[:, [R_ELBOW, R_WRIST]] = 0.06   # front view: both arms must be seen
    with pytest.raises(PoseError) as e:
        analyse("shoulder_abduction", front, use_model=False)
    assert e.value.code == "full_body_not_visible"


def test_standing_still_is_no_repetitions():
    with pytest.raises(PoseError) as e:
        analyse("shoulder_abduction", sequence([front_pose()] * 120), use_model=False)
    assert e.value.code == "no_repetitions"


# ---- /pose request validation -----------------------------------------------

def _video(path, seconds, w=720, h=1280, fps=10):
    out = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"mp4v"), fps, (w, h))
    frame = np.full((h, w, 3), 40, np.uint8)
    for _ in range(int(seconds * fps)):
        out.write(frame)
    out.release()
    return path


def post(path, key="shoulder_abduction", name=None):
    with open(path, "rb") as fh:
        return client.post("/pose", headers=DEV, data={"exercise_key": key},
                           files={"file": (name or path.name, fh, "video/mp4")})


def test_pose_needs_token(tmp_path):
    r = client.post("/pose", data={"exercise_key": "sit_to_stand"}, files={"file": ("a.mp4", b"x", "video/mp4")})
    assert r.status_code == 401


def test_pose_rejects_unknown_exercise_and_format(tmp_path):
    v = _video(tmp_path / "a.mp4", 12)
    assert post(v, key="juggling").json()["error"]["code"] == "unknown_exercise"
    assert post(v, name="a.avi").json()["error"]["code"] == "invalid_video"


def test_pose_rejects_garbage_short_and_low_res(tmp_path):
    junk = tmp_path / "junk.mp4"
    junk.write_bytes(b"\x00" * 1000)
    assert post(junk).json()["error"]["code"] == "invalid_video"
    short = post(_video(tmp_path / "short.mp4", 5))
    assert short.status_code == 422 and "10 and 30" in short.json()["error"]["message"]
    low = post(_video(tmp_path / "low.mp4", 12, w=360, h=640))
    assert "720p" in low.json()["error"]["message"]


def test_pose_empty_scene_is_pose_not_detected(tmp_path):
    r = post(_video(tmp_path / "empty.mp4", 11))
    assert r.status_code == 422 and r.json()["error"]["code"] == "pose_not_detected"


def test_pose_exercise_list():
    r = client.get("/pose/exercises", headers=DEV)
    assert r.status_code == 200 and len(r.json()["exercises"]) == 17   # + wrist extension, hand open/close (9 Oct)


def test_descent_time_runs_from_top_to_seated_not_to_rep_end():
    # Stand at 180, sit back down to 90 over `down` seconds; the rep ends at the rest line (112),
    # before the person is seated, so the old peak->rep end timing under-measured careful sits.
    from types import SimpleNamespace
    from app.pose.exercises import descent_seconds

    def run(down):
        n_down = int(down * FPS)
        sig = np.concatenate([np.full(10, 90.0), np.linspace(90, 180, 10), np.full(5, 180.0),
                              np.linspace(180, 90, n_down), np.full(15, 90.0)])
        f = SimpleNamespace(t=np.arange(len(sig)) / FPS)
        peak = 22
        end = peak + 3 + int(np.argmax(sig[peak + 3:] < 112))
        return descent_seconds(lambda _: sig, f, Rep(start=10, peak=peak, end=end))

    assert run(2.0) == pytest.approx(1.7, abs=0.25)   # slow, controlled: well above the 0.7 s limit
    assert run(0.5) < 0.7                             # dropping into the chair


# ---- elderly users: possible fall, gentler targets, partial repetitions (8 Oct) ----------------

def test_possible_fall_is_reported():
    frames = [front_pose(a, a) for a in wave(3, 5, 88)] + [front_pose(0, 0, lean=85)] * 20
    res = analyse("shoulder_abduction", sequence(frames), use_model=False)
    assert res["safety_alert"]["type"] == "possible_fall"
    assert res["feedback"][0].startswith("Stop and rest: it looks like you may have lost your balance")


def test_normal_exercise_has_no_fall_alert():
    res = analyse("shoulder_abduction", sequence([front_pose(a, a) for a in wave(5, 5, 88)]), use_model=False)
    assert "safety_alert" not in res


def test_fall_is_reported_even_without_repetitions():
    frames = [front_pose(0, 0)] * 30 + [front_pose(0, 0, lean=85)] * 20
    res = analyse("shoulder_abduction", sequence(frames), use_model=False)
    assert res["safety_alert"]["type"] == "possible_fall" and res["repetitions"] == 0


def test_older_patients_get_gentler_range_targets():
    frames = [front_pose(a, a) for a in wave(4, 5, 75)]
    assert "low_range" in analyse("shoulder_abduction", sequence(frames), use_model=False)["mistakes"]
    res = analyse("shoulder_abduction", sequence(frames), use_model=False, rom_scale=exercises.rom_scale_for("HIGH"))
    assert "low_range" not in res["mistakes"] and res["rom_scale"] == 0.7


def test_gentler_targets_keep_the_form_rules():
    frames = [front_pose(a, a, elbow_bend=60 * a / 88) for a in wave(4, 5, 88)]
    res = analyse("shoulder_abduction", sequence(frames), use_model=False, rom_scale=0.7)
    assert "bent_elbow" in res["mistakes"]


def test_small_movements_count_as_partial_repetitions():
    res = analyse("shoulder_abduction", sequence([front_pose(a, a) for a in wave(4, 5, 48)]), use_model=False)
    assert res["partial_repetitions"] is True and res["repetitions"] == 4
    assert res["feedback"][0].startswith("We saw small movements")


def test_rom_scale_for_risk_and_age():
    assert exercises.rom_scale_for() == 1.0 and exercises.rom_scale_for("LOW", 40) == 1.0
    assert exercises.rom_scale_for("MODERATE") == 0.85 and exercises.rom_scale_for(None, 68) == 0.85
    assert exercises.rom_scale_for("high") == 0.7 and exercises.rom_scale_for("LOW", 80) == 0.7
    assert exercises.rom_scale_for("MEDIUM") == 0.85                 # the app's own name for it


def test_frail_patients_may_use_their_hands_and_step_out():
    """Posture text review (8 Oct): for frail users the safe choice is not a mistake."""
    marked = {(k, m.label) for k, s in exercises.EXERCISES.items() for m in s.mistakes if m.frail_ok}
    assert marked == {("sit_to_stand", "hands_used"), ("tandem_stance", "stepping_out")}
    hands = next(m for m in exercises.EXERCISES["sit_to_stand"].mistakes if m.label == "hands_used")
    always = exercises.Mistake("x", "", lambda f, r: 0.0, 1.0, False)       # 0 < 1: always a mistake
    always.frail_ok = True
    rep = Rep(0, 1, 2)
    assert always.check(None, rep, 1.0) and not always.check(None, rep, 0.85)
    assert "keep using them" in hands.feedback


def _shift(frames, dx):
    out = []
    for p, d in zip(frames, dx):
        q = p.copy()
        q[:, 0] += d
        out.append(q)
    return out


def test_large_side_to_side_sway_gives_a_balance_tip():
    frames = [front_pose(a, a) for a in wave(4, 5, 88)]
    sway = [85 * math.sin(i / 6) for i in range(len(frames))]      # about +-0.3 torso lengths
    res = analyse("shoulder_abduction", sequence(_shift(frames, sway)), use_model=False)
    assert res.get("balance_tip") is True
    assert res["feedback"][-1].startswith("You swayed from side to side")
    calm = analyse("shoulder_abduction", sequence(frames), use_model=False)
    assert "balance_tip" not in calm


def test_frail_patients_get_a_shorter_hold_target():
    full = analyse("tandem_stance", sequence([front_pose(feet_gap=10)] * 110), use_model=False)
    gentle = analyse("tandem_stance", sequence([front_pose(feet_gap=10)] * 110), use_model=False, rom_scale=0.7)
    assert gentle["accuracy"] >= full["accuracy"]


def test_dark_video_gives_a_quality_tip():
    frames = [front_pose(a, a) for a in wave(4, 5, 88)]
    res = analyse("shoulder_abduction", sequence(frames), use_model=False, brightness=50)
    assert res["quality_tips"] and res["feedback"][-1].startswith("Your video is quite dark")
    assert "quality_tips" not in analyse("shoulder_abduction", sequence(frames), use_model=False, brightness=130)


def test_small_figure_gives_a_quality_tip():
    frames = [front_pose(a, a) for a in wave(4, 5, 88)]
    small = []
    for p in frames:                                   # shrink the person to a third, around the centre
        q = p.copy()
        q[:, 0] = W / 2 + (q[:, 0] - W / 2) / 3
        q[:, 1] = H / 2 + (q[:, 1] - H / 2) / 3
        small.append(q)
    res = analyse("shoulder_abduction", sequence(small), use_model=False)
    assert any(t.startswith("You look small") for t in res["quality_tips"])


# ---- is it the selected exercise? (identity.py, 8 Oct) --------------------------------------

def _sig(**kw):
    base = {"arm_raise": 5.0, "elbow_bend": 10.0, "knee_bend": 5.0, "knee_median": 175.0, "hip_rise": 0.03,
            "trunk_upright": 88.0, "thigh_lift": 3.0, "leg_side": 2.0, "heel_lift": 0.05, "heels_together": 0.6,
            "thighs_together": 0.2, "arm_sideways": float("nan"), "view_ratio": 0.1}
    return {**base, **kw}


def test_identity_accepts_the_selected_exercise_and_refuses_others():
    from app.pose.identity import check
    sit_to_stand = _sig(knee_bend=85, knee_median=105, hip_rise=0.5, thigh_lift=75, thighs_together=0.99)
    assert check("sit_to_stand", sit_to_stand) is None
    assert check("knee_extension", sit_to_stand) == "you stood up"
    assert check("shoulder_abduction", {**sit_to_stand, "arm_raise": 40}) == "your knees bent a lot"
    assert check("march_in_place", sit_to_stand) is not None
    abduction_front = _sig(arm_raise=90, arm_sideways=1.0, view_ratio=0.67)
    assert check("shoulder_abduction", abduction_front) is None
    assert check("shoulder_flexion", abduction_front) == "your arms went out to the side, not forwards"
    flexion_side = _sig(arm_raise=85, arm_sideways=0.98, view_ratio=0.06)
    assert check("shoulder_flexion", flexion_side) is None
    assert check("shoulder_abduction", flexion_side) == "your arms went forwards, not out to the side"
    lying = _sig(trunk_upright=-12, hip_rise=0.35, knee_median=45)
    assert check("glute_bridge", lying) is None and check("heel_raise", lying) is not None


def test_identity_tells_a_forward_raise_from_a_backward_swing():
    # REHAB26-ViewAngles (9 Oct): shoulder extension filmed from the side had passed as shoulder flexion.
    from app.pose.identity import check
    flexion_side = _sig(arm_raise=85, arm_sideways=0.98, view_ratio=0.06, facing=0.15, arm_forward=0.9)
    extension_side = _sig(arm_raise=50, arm_sideways=0.6, view_ratio=0.06, facing=-0.15, arm_forward=-0.7)
    assert check("shoulder_flexion", flexion_side) is None
    assert check("shoulder_flexion", extension_side) == "your arm went backwards, not forwards"
    # From the front the nose is between the ears: forwards and back look alike, so never refuse on it.
    assert check("shoulder_flexion", {**extension_side, "facing": 0.02, "view_ratio": 0.3}) is None


def test_identity_measures_arm_direction_from_the_face():
    from app.pose.identity import signature
    from app.pose.landmarks import L_EAR, R_EAR

    def side(arm_deg):              # standing, side view, facing image right; arm_deg > 0 = forwards
        p = np.zeros((33, 2))
        hip, sh = np.array([360.0, 700.0]), np.array([360.0, 440.0])
        p[L_HIP] = p[R_HIP] = hip
        p[L_SHOULDER] = p[R_SHOULDER] = sh
        p[NOSE], p[L_EAR], p[R_EAR] = sh + [45, -110], sh + [0, -105], sh + [0, -105]
        for el, wr in ((L_ELBOW, L_WRIST), (R_ELBOW, R_WRIST)):
            p[el] = limb(sh, arm_deg, 130)
            p[wr] = limb(p[el], arm_deg, 120)
        for kn, an in ((L_KNEE, L_ANKLE), (R_KNEE, R_ANKLE)):
            p[kn], p[an] = hip + [0, 240], hip + [0, 480]
        return p

    for sign in (1, -1):
        frames = [side(sign * a) for a in list(range(0, 80, 8)) + list(range(80, 0, -8))] * 3
        s = signature(Features(sequence(frames)))
        assert s["facing"] > 0.1 and np.sign(s["arm_forward"]) == sign


def test_mini_squat_counts_reps_when_the_knees_never_fully_straighten():
    # REHAB26 (9 Oct): standing knees read 10-13 degrees bent, above the 8 degree start level, and ten
    # squats were counted as two. Small squats keep the exercise's own levels.
    from app.pose.analyse import rep_levels
    spec = exercises.EXERCISES["mini_squat"]
    one = [12, 14, 25, 45, 60, 45, 25, 14]
    sig = np.array(one * 10 + [12, 12], dtype=float)
    t = np.arange(len(sig)) / FPS
    assert len(find_reps(sig, t, spec.rest, spec.active)) <= 1
    assert len(find_reps(sig, t, *rep_levels(spec, sig))) == 10
    small = np.array([2, 4, 10, 18, 20, 18, 10, 4] * 5 + [2, 2], dtype=float)
    assert rep_levels(spec, small) == (spec.rest, spec.active)


def test_identity_never_refuses_on_what_it_cannot_measure():
    from app.pose.identity import check
    weak_raise = _sig(arm_raise=30, arm_sideways=float("nan"), view_ratio=float("nan"))   # small, partial raise
    assert check("shoulder_abduction", weak_raise) is None and check("shoulder_flexion", weak_raise) is None


def test_wrong_exercise_is_reported_only_after_movement_was_found():
    with pytest.raises(PoseError) as e:
        analyse("shoulder_abduction", sequence([front_pose()] * 120), use_model=False)
    assert e.value.code == "no_repetitions"


# ---- condition audit (9 Oct, training/audit_conditions.py) ------------------------------

def test_an_unfinished_last_repetition_is_not_judged():
    # The recording stopped half way up the last repetition.
    sig = np.array(wave(3, 0, 60) + [0, 5, 10, 20, 30, 40, 50], dtype=float)
    t = np.arange(len(sig)) / FPS
    reps = find_reps(sig, t, 10, 30)
    assert len(reps) == 4 and reps[-1].unfinished and not any(r.unfinished for r in reps[:3])
    frames = [front_pose(a, a) for a in wave(3, 5, 88)] + [front_pose(a, a) for a in (5, 15, 25, 30, 40, 50, 60, 70, 80)]
    res = analyse("shoulder_abduction", sequence(frames), use_model=False)
    assert res["repetitions"] == 4 and len(res["rep_details"]) == 3 and res["mistakes"] == {}
    only = np.array([0, 0, 0, 5, 10, 20, 30, 40, 45, 50], dtype=float)   # a single one is kept as evidence
    assert len(find_reps(only, np.arange(len(only)) / FPS, 10, 30)) == 1


def test_a_tilted_phone_turned_back_gives_the_same_result():
    from app.pose.landmarks import turned
    frames = [front_pose(a, a) for a in wave(4, 5, 88)]
    upright = analyse("shoulder_abduction", sequence(frames), use_model=False)
    tilted = turned(sequence(frames), 12)
    back = analyse("shoulder_abduction", turned(tilted, -12), use_model=False)
    assert back["repetitions"] == upright["repetitions"] and back["mistakes"] == upright["mistakes"] == {}
    assert np.allclose(turned(tilted, -12).xy, sequence(frames).xy, atol=1e-3)


def test_a_small_movement_is_not_called_the_wrong_exercise(monkeypatch):
    from app.pose import analyse as analyse_module
    from app.pose import identity
    spec = exercises.EXERCISES["sit_to_stand"]
    f = Features(sequence([front_pose()] * 30))
    monkeypatch.setattr(identity, "check_detail", lambda key, sig: ("no standing up from the chair was seen", True))
    with pytest.raises(PoseError) as e:
        analyse_module._same_exercise(spec, f, None, partial=True)
    assert e.value.code == "wrong_exercise" and e.value.message.startswith("We could only see a small movement")
    with pytest.raises(PoseError) as e:                                # full repetitions: another exercise
        analyse_module._same_exercise(spec, f, None, partial=False)
    assert "check that you chose the right exercise" in e.value.message
    monkeypatch.setattr(identity, "check_detail", lambda key, sig: ("you were sitting", False))
    with pytest.raises(PoseError) as e:                                # not about size: another exercise
        analyse_module._same_exercise(spec, f, None, partial=True)
    assert "check that you chose the right exercise" in e.value.message


def test_identity_tells_a_too_small_movement_from_another_exercise():
    from app.pose.identity import check_detail
    assert check_detail("shoulder_abduction", _sig(arm_raise=10)) == ("no arm raising was seen", True)
    assert check_detail("knee_extension", _sig(knee_bend=60, knee_median=170, hip_rise=0.05))[1] is False
    assert check_detail("shoulder_abduction", _sig(arm_raise=90, arm_sideways=1.0, view_ratio=0.67)) == (None, False)


def test_frail_targets_keep_the_models_form_verdicts_but_not_its_range_verdicts(monkeypatch):
    from app.pose import classifier
    frames = [front_pose(a, a) for a in wave(4, 5, 88)]

    def fake(label):
        return lambda key, f, reps: {"p_correct": [0.2] * len(reps), "likely_mistake": [label] * len(reps),
                                     "version": "fake_v1"}
    monkeypatch.setattr(classifier, "predict", fake("bent_elbow"))
    frail = analyse("shoulder_abduction", sequence(frames), rom_scale=0.7)
    full = analyse("shoulder_abduction", sequence(frames))
    assert frail["mistakes"] == full["mistakes"] == {"bent_elbow": 4} and frail["accuracy"] == full["accuracy"]
    monkeypatch.setattr(classifier, "predict", fake("low_range"))        # a range verdict is never added
    res = analyse("shoulder_abduction", sequence(frames), rom_scale=0.7)
    assert res["mistakes"] == {}
    short = [front_pose(a, a) for a in wave(4, 5, 62)]                  # shortened reps: rules only
    res = analyse("shoulder_abduction", sequence(short), rom_scale=0.7)
    assert res["mistakes"] == {} and res["accuracy"] == 100 and "p_correct" not in res["rep_details"][0]


def test_the_model_leaves_much_slower_repetitions_to_the_rules(monkeypatch):
    torch = pytest.importorskip("torch")  # the laptop's server venv has no torch (deleted below)
    from app.pose import classifier
    frames = [front_pose(a, a) for a in wave(4, 5, 88, rep_sec=3.0)]
    f = Features(sequence(frames))
    reps = analyse_reps = __import__("app.pose.analyse", fromlist=["detect_reps"]).detect_reps(
        exercises.EXERCISES["shoulder_abduction"], f)
    n_in = len(classifier.INPUTS["shoulder_abduction"]) + 1
    model = classifier.build_model(n_in, 5)
    ckpt = {"mistakes": ["low_range", "bent_elbow", "uneven_arms", "trunk_lean", "shoulder_shrug"],
            "features": classifier.INPUTS["shoulder_abduction"], "duration_range": [0.5, 1.5]}
    monkeypatch.setattr(classifier, "latest_weights", lambda key: __import__("pathlib").Path("fake_v1.pt"))
    monkeypatch.setattr(classifier, "_load", lambda path: (model, ckpt))
    out = classifier.predict("shoulder_abduction", f, analyse_reps)
    assert all(p is None for p in out["p_correct"]) and len(reps) == 4      # 3 s reps, trained on <= 1.5 s
    ckpt["duration_range"] = [1.0, 4.0]
    out = classifier.predict("shoulder_abduction", f, analyse_reps)
    assert all(p is not None for p in out["p_correct"])
    del torch


def test_a_front_view_exercise_filmed_from_the_side_gets_a_tip():
    facing = [front_pose(a, a) for a in wave(4, 5, 88)]
    assert "camera_not_in_front" not in analyse("shoulder_abduction", sequence(facing), use_model=False)
    side_on = []
    for p in facing:                                    # shoulders and hips seen narrower, as from 45+ deg round
        q = p.copy()
        cx = (p[L_SHOULDER, 0] + p[R_SHOULDER, 0]) / 2
        for j in (L_SHOULDER, R_SHOULDER, L_HIP, R_HIP):
            q[j, 0] = cx + (p[j, 0] - cx) * 0.75
        side_on.append(q)
    res = analyse("shoulder_abduction", sequence(side_on), use_model=False)
    assert res["camera_not_in_front"] < 0.5 and any("face the phone" in tip for tip in res["quality_tips"])


def test_latest_weights_skips_names_that_are_not_versions(tmp_path):
    # A copy such as sit_to_stand_v4_backup.pt matched the pattern and its int() failed every
    # /pose request for the exercise (audit, 24 Oct).
    from app.pose import classifier
    for name in ("sit_to_stand_v3.pt", "sit_to_stand_v12.pt", "sit_to_stand_v4_backup.pt",
                 "sit_to_stand_vx.pt", "shoulder_flexion_v9.pt"):
        (tmp_path / name).write_bytes(b"")
    assert classifier.latest_weights("sit_to_stand", tmp_path).name == "sit_to_stand_v12.pt"
    assert classifier.latest_weights("knee_extension", tmp_path) is None
