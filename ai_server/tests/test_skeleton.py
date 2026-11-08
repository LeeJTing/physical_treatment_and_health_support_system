import jwt
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app

client = TestClient(app)
DEV = {"Authorization": "Bearer dev-token"}
VALID = {
    "rehab": {"affected_body_area": "BOTH_LEGS", "recovery_stage": "EARLY", "mobility_level": "LOW", "goal": "MOBILITY"},
    "safety_limit": {"max_exercise_intensity": "LOW", "max_session_duration_min": 20},
    "plans": [{"plan_id": "p1", "target_body_area": "BOTH_LEGS", "recovery_stage": "EARLY", "mobility_level": "LOW",
               "plan_exercise": [{"prescribed_duration_sec": 60,
                                  "exercise": {"exercise_id": "e1", "target_body_area": "BOTH_LEGS", "intensity_level": "LOW"}}]}],
}


def test_health_needs_no_token():
    r = client.get("/health")
    assert r.status_code == 200 and r.json()["status"] == "ok"


def test_test_token_is_refused_unless_turned_on(monkeypatch):
    """Bug list #17: no .env line must not mean 'anyone with the public test token gets in'."""
    from app.config import Settings
    monkeypatch.delenv("DEV_AUTH_BYPASS", raising=False)
    assert Settings(_env_file=None).dev_auth_bypass is False
    # /health says so, for run_tunnel.ps1 (the tests run with it on: conftest.py).
    assert client.get("/health").json()["dev_token_accepted"] is True


def test_missing_token_is_401_with_error_contract():
    r = client.post("/recommend", json={})
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "unauthorised"


def test_dev_token_accepted():
    assert client.post("/recommend", json=VALID, headers=DEV).status_code == 200
    assert client.get("/chat/categories", headers=DEV).status_code == 200


def test_real_supabase_style_token(monkeypatch):
    secret = "test-secret-at-least-32-bytes-long!!"
    monkeypatch.setenv("SUPABASE_JWT_SECRET", secret)
    monkeypatch.setenv("SUPABASE_JWKS_URL", "")  # independent of a local .env with the real project's JWKS
    monkeypatch.setenv("DEV_AUTH_BYPASS", "false")
    get_settings.cache_clear()
    try:
        tok = jwt.encode({"sub": "abc", "aud": "authenticated"}, secret, algorithm="HS256")
        assert client.post("/recommend", json=VALID, headers={"Authorization": f"Bearer {tok}"}).status_code == 200
        bad = jwt.encode({"sub": "abc", "aud": "authenticated"}, "wrong-secret-also-32-bytes-long!!!", algorithm="HS256")
        assert client.post("/recommend", json=VALID, headers={"Authorization": f"Bearer {bad}"}).status_code == 401
        assert client.post("/recommend", json=VALID, headers=DEV).status_code == 401
        no_sub = jwt.encode({"aud": "authenticated"}, secret, algorithm="HS256")
        r = client.post("/recommend", json=VALID, headers={"Authorization": f"Bearer {no_sub}"})
        assert r.status_code == 401  # was a 500 (KeyError 'sub')
    finally:
        get_settings.cache_clear()


def test_unreachable_signing_keys_are_503_not_401(monkeypatch):
    """Bug list #3: Supabase paused or offline is not an expired session."""
    import app.auth as auth

    class Down:
        def get_signing_key_from_jwt(self, _):
            raise jwt.PyJWKClientConnectionError("Fail to fetch data from the url")

    monkeypatch.setenv("SUPABASE_JWKS_URL", "https://example.invalid/jwks.json")
    monkeypatch.setenv("DEV_AUTH_BYPASS", "false")
    monkeypatch.setattr(auth, "_jwks_client", Down())
    get_settings.cache_clear()
    try:
        tok = jwt.encode({"sub": "abc", "aud": "authenticated"}, "k" * 32, algorithm="HS256")
        r = client.post("/recommend", json=VALID, headers={"Authorization": f"Bearer {tok}"})
        assert r.status_code == 503
        assert r.json()["error"]["code"] == "service_unavailable"
    finally:
        get_settings.cache_clear()


def test_pose_accepts_multipart():
    r = client.post("/pose", headers=DEV, files={"file": ("clip.mp4", b"\x00" * 10, "video/mp4")},
                    data={"exercise_key": "sit_to_stand"})
    assert r.status_code == 422 and r.json()["error"]["code"] == "invalid_video"
