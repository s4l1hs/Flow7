import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

# Firebase and auth related flags
FIREBASE_CREDENTIAL_PATH = os.getenv("FIREBASE_CREDENTIAL_PATH")
REQUIRE_STRICT_AUTH = os.getenv("REQUIRE_STRICT_AUTH", "false").lower() in ("1", "true", "yes")
FIREBASE_CHECK_REVOKED = os.getenv("FIREBASE_CHECK_REVOKED", "false").lower() in ("1", "true", "yes")

# Try to initialize firebase_admin if credentials are provided
FIREBASE_ADMIN_AVAILABLE = False
try:
    import firebase_admin
    from firebase_admin import credentials

    if FIREBASE_CREDENTIAL_PATH:
        cred = credentials.Certificate(FIREBASE_CREDENTIAL_PATH)
        firebase_admin.initialize_app(cred)
        FIREBASE_ADMIN_AVAILABLE = True
    else:
        # If no credential path, firebase_admin may still be importable but not configured
        FIREBASE_ADMIN_AVAILABLE = False
except Exception:
    # firebase_admin not available or failed to init
    FIREBASE_ADMIN_AVAILABLE = False

# DB URL helper (used by db module too) - provide a deterministic default
PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SQLITE_PATH = PROJECT_ROOT / "maindb.db"
DATABASE_URL = os.getenv("DATABASE_URL", f"sqlite:///{DEFAULT_SQLITE_PATH}")

# Firebase send tuning
FIREBASE_SEND_RETRIES = int(os.getenv("FIREBASE_SEND_RETRIES", "2"))
FIREBASE_SEND_BACKOFF = float(os.getenv("FIREBASE_SEND_BACKOFF", "1.5"))
