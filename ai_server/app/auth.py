"""Verifies the Supabase access token sent by ApiClient as a bearer token.

The server never sees a password or an email: only the token, whose `sub`
claim is the account_id (a pseudonymous UUID, NFR_15).
"""
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import Settings, get_settings

_bearer = HTTPBearer(auto_error=False)
_jwks_client = None


def _decode(token: str, s: Settings) -> dict:
    global _jwks_client
    if s.supabase_jwks_url:
        if _jwks_client is None:
            _jwks_client = jwt.PyJWKClient(s.supabase_jwks_url)
        key = _jwks_client.get_signing_key_from_jwt(token).key
        return jwt.decode(token, key, algorithms=["ES256", "RS256"], audience="authenticated")
    if s.supabase_jwt_secret:
        return jwt.decode(token, s.supabase_jwt_secret, algorithms=["HS256"], audience="authenticated")
    raise jwt.InvalidTokenError("No verification key configured")


def current_account_id(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    s: Settings = Depends(get_settings),
) -> str:
    if creds is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Missing bearer token")
    token = creds.credentials
    if s.dev_auth_bypass and token == "dev-token":
        return "00000000-0000-0000-0000-000000000000"
    try:
        claims = _decode(token, s)
    except jwt.PyJWKClientConnectionError as e:
        # Supabase's signing keys could not be fetched (project paused, no network): the token
        # may be fine, so 503, not 401, which the app shows as "session expired" (bug list #3).
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE,
                            "The service is temporarily unavailable. Please try again later.") from e
    except jwt.PyJWTError as e:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, f"Invalid token: {e}") from e
    sub = claims.get("sub")
    if not isinstance(sub, str) or not sub:
        # A signed token without an account id: refused, not a 500 (audit, 23 Oct).
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token: no account id")
    return sub
