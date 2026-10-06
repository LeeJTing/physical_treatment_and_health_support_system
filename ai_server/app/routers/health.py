from fastapi import APIRouter

from ..config import get_settings

router = APIRouter(tags=["health"])


@router.get("/health")
def health():
    """Unauthenticated liveness check, used before a demo to wake the server."""
    return {"status": "ok", "version": get_settings().api_version}
