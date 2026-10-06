import jwt
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app

client = TestClient(app)
DEV = {"Authorization": "Bearer dev-token"}


def test_health_needs_no_token():
    r = client.get("/health")
    assert r.status_code == 200 and r.json()["status"] == "ok"


def test_missing_token_is_401_with_error_contract():
    r = client.post("/recommend", json={})
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "unauthorised"


def test_dev_token_accepted():
    assert client.post("/recommend", json={}, headers=DEV).status_code == 200
    assert client.get("/chat/categories", headers=DEV).status_code == 200


def test_real_supabase_style_token(monkeypatch):
    secret = "test-secret-at-least-32-bytes-long!!"
    monkeypatch.setenv("SUPABASE_JWT_SECRET", secret)
    monkeypatch.setenv("DEV_AUTH_BYPASS", "false")
    get_settings.cache_clear()
    try:
        tok = jwt.encode({"sub": "abc", "aud": "authenticated"}, secret, algorithm="HS256")
        assert client.post("/recommend", json={}, headers={"Authorization": f"Bearer {tok}"}).status_code == 200
        bad = jwt.encode({"sub": "abc", "aud": "authenticated"}, "wrong-secret-also-32-bytes-long!!!", algorithm="HS256")
        assert client.post("/recommend", json={}, headers={"Authorization": f"Bearer {bad}"}).status_code == 401
        assert client.post("/recommend", json={}, headers=DEV).status_code == 401
    finally:
        get_settings.cache_clear()


def test_pose_accepts_multipart():
    r = client.post("/pose", headers=DEV, files={"file": ("clip.mp4", b"\x00" * 10, "video/mp4")},
                    data={"exercise_key": "sit_to_stand"})
    assert r.status_code == 200 and "accuracy" in r.json()
