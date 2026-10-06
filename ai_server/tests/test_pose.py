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


# ---- seated knee extension (side view) --------------------------------------

def test_knee_extension_correct_with_hold():
    res = analyse("knee_extension", sequence([side_seated(k) for k in wave(4, 90, 175, hold_sec=2.0)]), use_model=False)
    assert res["repetitions"] == 4 and res["mistakes"] == {}


def test_knee_extension_no_hold_and_incomplete():
    no_hold = analyse("knee_extension", sequence([side_seated(k) for k in wave(4, 90, 175)]), use_model=False)
    assert "no_hold" in no_hold["mistakes"]
    half = analyse("knee_extension", sequence([side_seated(k) for k in wave(4, 90, 148, hold_sec=2.0)]), use_model=False)
    assert "incomplete_extension" in half["mistakes"]


def test_knee_extension_slouching():
    res = analyse("knee_extension",
                  sequence([side_seated(k, lean=-18) for k in wave(4, 90, 175, hold_sec=2.0)]), use_model=False)
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
    assert r.status_code == 200 and len(r.json()["exercises"]) == 15


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
