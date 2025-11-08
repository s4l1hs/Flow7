from fastapi import Depends, HTTPException, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from firebase_admin import auth as firebase_auth
import base64
import json
from .db import get_db
from .models import UserSettings
from .config import FIREBASE_ADMIN_AVAILABLE, REQUIRE_STRICT_AUTH, FIREBASE_CHECK_REVOKED
from .state import USER_SUBSCRIPTIONS


token_auth_scheme = HTTPBearer(auto_error=False)


async def get_current_user(
    token: HTTPAuthorizationCredentials = Security(token_auth_scheme), db: Session = Depends(get_db)
):
    """Resolve the current user's UID using firebase_admin when available.
    Falls back to treating the token as a UID in non-strict mode for local/dev.
    """
    if token is None:
        raise HTTPException(status_code=401, detail="Missing authorization token")

    id_token = token.credentials

    uid = None
    if FIREBASE_ADMIN_AVAILABLE:
        try:
            decoded = firebase_auth.verify_id_token(id_token, check_revoked=FIREBASE_CHECK_REVOKED)
            uid = decoded.get("uid")
        except firebase_auth.RevokedIdTokenError:
            raise HTTPException(status_code=401, detail="Token revoked")
        except Exception as e:
            raise HTTPException(status_code=401, detail=f"Token verification failed: {e}")
    else:
        if REQUIRE_STRICT_AUTH:
            raise HTTPException(status_code=500, detail="Strict auth required but firebase_admin not configured")
        # Best-effort dev fallback: accept the token as a uid or try base64 decode
        uid = _parse_uid_from_token(id_token)

    if uid is None:
        raise HTTPException(status_code=401, detail="Unable to resolve user from token")

    # Ensure UserSettings exists and migrate from in-memory fallback if present
    us = db.query(UserSettings).get(uid)
    if us is None:
        # Create with defaults and migrate subscription from in-memory if present
        sub = USER_SUBSCRIPTIONS.get(uid, {}).get("subscription_level", "FREE")
        us = UserSettings(uid=uid, subscription_level=sub)
        db.add(us)
        db.commit()
        db.refresh(us)

    # Attach subscription and other settings to a simple user object for endpoints
    # Provide both `subscription_level` and legacy `subscription` for backward compatibility
    user = {
        "uid": uid,
        "subscription": us.subscription_level or "FREE",
        "subscription_level": us.subscription_level,
        "subscription_expires_at": us.subscription_expires_at,
        "subscription_score": us.subscription_score,
        "language_code": us.language_code,
        "theme_preference": us.theme,
        "theme": us.theme,
        "notifications_enabled": us.notifications_enabled,
        "timezone": us.timezone,
    }
    # Return a simple object with attribute access (compat with existing code expecting .uid)
    from types import SimpleNamespace
    return SimpleNamespace(**user)


def _parse_uid_from_token(token_str: str) -> str:
    # Try direct uid
    if token_str and len(token_str) < 64 and token_str.isalnum():
        return token_str
    # Try JWT-like base64 payload decode
    parts = token_str.split(".")
    if len(parts) >= 2:
        try:
            payload = parts[1]
            # Add padding
            padding = '=' * (-len(payload) % 4)
            payload += padding
            decoded = base64.urlsafe_b64decode(payload.encode())
            data = json.loads(decoded)
            return data.get("uid") or data.get("sub")
        except Exception:
            return None
    return None
