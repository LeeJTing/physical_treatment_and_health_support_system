"""The development viewer (devtools/) and the step-by-step trace it shows (app/pose/trace.py)."""
from fastapi.testclient import TestClient

from app.config import Settings
from app.pose.trace import trace
from test_pose import DEV, _video, client, front_pose, sequence, wave


def test_trace_shows_every_step_and_the_same_result_as_analyse():
    from app.pose.analyse import analyse
    seq = sequence([front_pose(a, a, elbow_bend=60 * a / 88 if i > 40 else 0) for i, a in enumerate(wave(4, 5, 88))])
    tr = trace("shoulder_abduction", seq)
    assert tr["result"] == analyse("shoulder_abduction", seq)
    assert tr["video"]["frames_analysed"] == len(seq.t) == tr["video"]["body_found_frames"]
    assert len(tr["signal"]["values"]) == len(seq.t) and tr["signal"]["count_level"] == 55
    assert [r["n"] for r in tr["repetitions"]] == [1, 2, 3, 4]
    assert {c["label"] for c in tr["repetitions"][0]["rules"]} >= {"low_range", "bent_elbow", "head_tilt"}
    fired = [c["label"] for r in tr["repetitions"] for c in r["rules"] if c["fired"]]
    assert "bent_elbow" in fired and tr["result"]["mistakes"]["bent_elbow"] >= 1
    assert tr["identity"]["refused_because"] is None and tr["identity"]["rules"][0]["passed"] is True


def test_with_dev_tools_a_phone_request_is_kept_and_answered_as_usual(tmp_path, monkeypatch):
    from app.routers import pose as pose_router
    v = _video(tmp_path / "blank.mp4", 12)
    with open(v, "rb") as fh:
        plain = client.post("/pose", headers=DEV, data={"exercise_key": "sit_to_stand"},
                            files={"file": ("blank.mp4", fh, "video/mp4")}).json()
    runs = tmp_path / "runs"
    monkeypatch.setattr(pose_router, "get_settings", lambda: Settings(dev_tools=True, dev_runs_dir=str(runs)))
    with open(v, "rb") as fh:
        dev = client.post("/pose", headers=DEV, data={"exercise_key": "sit_to_stand"},
                          files={"file": ("blank.mp4", fh, "video/mp4")}).json()
    assert dev == plain and dev["error"]["code"] == "pose_not_detected"
    kept = list(runs.iterdir())
    assert len(kept) == 1 and {p.name for p in kept[0].iterdir()} == {"video.mp4", "landmarks.npz", "trace.json"}


def test_without_dev_tools_nothing_is_kept(tmp_path, monkeypatch):
    from app.routers import pose as pose_router
    runs = tmp_path / "runs"
    monkeypatch.setattr(pose_router, "get_settings", lambda: Settings(dev_tools=False, dev_runs_dir=str(runs)))
    with open(_video(tmp_path / "blank.mp4", 12), "rb") as fh:
        client.post("/pose", headers=DEV, data={"exercise_key": "sit_to_stand"},
                    files={"file": ("blank.mp4", fh, "video/mp4")})
    assert not runs.exists()


def test_the_viewer_lists_and_shows_runs_and_refuses_the_tunnel(tmp_path, monkeypatch):
    from app.pose.trace import save_run
    from devtools import viewer
    monkeypatch.setattr(viewer, "RUNS", tmp_path)
    seq = sequence([front_pose(a, a) for a in wave(3, 5, 88)])
    run_id = save_run(tmp_path, None, seq, trace("shoulder_abduction", seq), "test")
    c = TestClient(viewer.app)
    listed = c.get("/api/runs").json()
    assert listed[0]["id"] == run_id and listed[0]["accuracy"] is not None and listed[0]["repetitions"] == 3
    one = c.get(f"/api/runs/{run_id}").json()
    assert len(one["frames"]["xy"]) == len(seq.t) and one["frames"]["has_video"] is False
    assert c.get("/api/runs/../../etc").status_code == 404
    assert c.get("/api/runs", headers={"cf-connecting-ip": "1.2.3.4"}).status_code == 403
    assert "Posture check viewer" in c.get("/").text
