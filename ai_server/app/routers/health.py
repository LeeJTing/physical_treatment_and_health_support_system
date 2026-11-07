from fastapi import APIRouter

from ..config import get_settings

router = APIRouter(tags=["health"])


@router.get("/health")
def health():
    """Unauthenticated liveness check, used before a demo to wake the server."""
    s = get_settings()
    # Read by run_tunnel.ps1, which refuses to open a public address while the test token works.
    return {"status": "ok", "version": s.api_version, "dev_token_accepted": s.dev_auth_bypass}


@router.get("/")
def root():
    """Opening the bare tunnel address in a browser shows that the server is up
    (otherwise FastAPI answers "Not Found", which looks like a failure)."""
    return {
        "service": "HealthGuide AI server",
        "status": "ok",
        "version": get_settings().api_version,
        "endpoints": ["/health", "/recommend", "/chat", "/chat/categories", "/pose", "/pose/exercises"],
        "note": "Every endpoint except /health and / needs the app's login token.",
    }
