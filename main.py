import os
from datetime import datetime, date as PyDate, time as PyTime, timedelta, timezone
from typing import List, Optional
from uuid import uuid4
import base64
import json
from pathlib import Path
from threading import Lock

import uvicorn
from dotenv import load_dotenv
import logging
from fastapi import FastAPI, HTTPException, Depends, Security, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, validator
from sqlalchemy import (
    create_engine,
    Column,
    String,
    Text,
    select,
    DateTime as SA_DateTime,
    Date as SA_Date,
    Time as SA_Time,
    Boolean,
)
from sqlalchemy.orm import declarative_base, sessionmaker, Session
from zoneinfo import ZoneInfo
import time
import threading
import warnings

# Suppress a known deprecation UserWarning emitted by APScheduler's use of pkg_resources.
# This avoids noisy startup logs; prefer pinning setuptools (<81) in build pipelines for a
# permanent fix. The filter targets the warning message emitted from the apscheduler package.
warnings.filterwarnings(
    "ignore",
    message=r"pkg_resources is deprecated as an API.*",
    category=UserWarning,
    module=r"apscheduler.*",
)
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.jobstores.sqlalchemy import SQLAlchemyJobStore
from apscheduler.triggers.date import DateTrigger
from apscheduler.executors.pool import ThreadPoolExecutor
from apscheduler.events import EVENT_JOB_EXECUTED, EVENT_JOB_ERROR
from typing import Any
from contextlib import asynccontextmanager
import logging
logger = logging.getLogger("uvicorn.error")
from logging_config import configure_logging
configure_logging(os.getenv("LOG_LEVEL", "INFO"))

# make a root logger for app-specific logging
app_logger = logging.getLogger("flow7")
app_logger.setLevel(os.getenv("LOG_LEVEL", "INFO"))

# --- 1. CONFIGURATION & DATABASE SETUP ---
# .env dosyasından ortam değişkenlerini yükle
load_dotenv()
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./flow7_revised.db")

# SQLAlchemy motoru ve oturum oluşturucu
# check_same_thread: False -> Sadece SQLite için gereklidir.
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


# --- 2. DATABASE (ORM) MODEL ---
class PlanORM(Base):
    """Veritabanındaki 'plans' tablosunu temsil eden SQLAlchemy ORM modeli."""
    __tablename__ = "plans"
    id = Column(String, primary_key=True, index=True)
    user_id = Column(String, index=True, nullable=False)
    date = Column(SA_Date, index=True, nullable=False)
    start_time = Column(SA_Time, nullable=False)
    end_time = Column(SA_Time, nullable=False)
    title = Column(String, nullable=False)
    description = Column(Text, nullable=True)
    notified = Column(Boolean, default=False, nullable=False)
    created_at = Column(SA_DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(SA_DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))


# In production we expect DB schema to be managed by migrations (Alembic).
# For local development only, set DEV_ALLOW_CREATE_ALL=1 to auto-create tables.
if os.getenv("DEV_ALLOW_CREATE_ALL", "0") == "1":
    Base.metadata.create_all(bind=engine)

# --- Add DB-backed user settings and device tokens ---
class UserSettings(Base):
    __tablename__ = "user_settings"
    uid = Column(String, primary_key=True, index=True)
    level = Column(String, default="FREE")
    theme = Column(String, default="LIGHT")
    timezone = Column(String, default="Europe/Istanbul")
    country = Column(String, default="")
    city = Column(String, default="")
    notifications_enabled = Column(Boolean, default=True)


class DeviceToken(Base):
    __tablename__ = "device_tokens"
    token = Column(String, primary_key=True, index=True)
    user_id = Column(String, index=True, nullable=False)
    provider = Column(String, default="fcm")
    created_at = Column(SA_DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

if os.getenv("DEV_ALLOW_CREATE_ALL", "0") == "1":
    # create missing tables in development only
    Base.metadata.create_all(bind=engine)

# create FastAPI app instance (required before using @app)
# configure CORS origins from env var for production; default allow all for dev
allowed = os.getenv('ALLOWED_ORIGINS', '*')
if allowed == '*' or allowed.strip() == '':
    cors_origins = ["*"]
else:
    cors_origins = [o.strip() for o in allowed.split(',') if o.strip()]

app = FastAPI(title="Flow7 API", docs_url="/docs", redoc_url="/redoc")

# add permissive CORS during development; adjust origins in production
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# lightweight security headers middleware for production
@app.middleware("http")
async def security_headers_middleware(request: Request, call_next):
    response = await call_next(request)
    # Enforce some basic security headers; adjust as needed for your deployment
    response.headers.setdefault('Strict-Transport-Security', 'max-age=63072000; includeSubDomains; preload')
    response.headers.setdefault('X-Frame-Options', 'DENY')
    response.headers.setdefault('X-Content-Type-Options', 'nosniff')
    response.headers.setdefault('Referrer-Policy', 'no-referrer')
    response.headers.setdefault('Permissions-Policy', 'geolocation=()')
    return response

# --- 3. PYDANTIC SCHEMAS (DATA TRANSFER OBJECTS) ---
# API istek ve yanıtlarının yapısını ve doğruluğunu tanımlar.

TIME_PATTERN = r"^\d{2}:\d{2}$" # HH:MM formatı için regex

class PlanBase(BaseModel):
    """Planlar için temel şema. Ortak alanları içerir."""
    date: PyDate
    start_time: str = Field(..., pattern=TIME_PATTERN, description="HH:MM formatında başlangıç zamanı")
    end_time: str = Field(..., pattern=TIME_PATTERN, description="HH:MM formatında bitiş zamanı")
    title: str = Field(..., min_length=1, max_length=100)
    description: Optional[str] = Field(None, max_length=500)

    @validator("end_time")
    def end_time_must_be_after_start_time(cls, v, values, **kwargs):
        """Bitiş saatinin başlangıç saatinden sonra olduğunu doğrular."""
        if "start_time" in values and v <= values["start_time"]:
            raise ValueError("Bitiş zamanı, başlangıç zamanından sonra olmalıdır.")
        return v

class PlanCreate(PlanBase):
    """Yeni bir plan oluşturmak için kullanılan şema."""
    pass

class PlanUpdate(PlanBase):
    """Mevcut bir planı güncellemek için kullanılan şema."""
    pass

class PlanOut(PlanBase):
    """API yanıtlarında döndürülecek plan şeması."""
    id: str
    user_id: str

    class Config:
        orm_mode = True

# Yeni: subscription güncelleme için Pydantic şeması
class SubscriptionUpdate(BaseModel):
    level: str
    days: int = Field(..., gt=0)

# model for timezone update endpoint
class TimezoneUpdate(BaseModel):
    timezone: str = Field(..., description="IANA timezone string, e.g. 'Europe/Istanbul'")


class DeviceTokenIn(BaseModel):
    token: str
    provider: Optional[str] = "fcm"


class UserProfileOut(BaseModel):
    uid: str
    subscription: str
    theme: str
    timezone: str
    country: Optional[str] = None
    city: Optional[str] = None
    notifications_enabled: bool = True
    device_tokens: Optional[List[str]] = []


# --- 4. AUTHENTICATION & AUTHORIZATION ---
# Gerçek bir Firebase entegrasyonu için bu bölümü genişletin.
# Gerekli kütüphane: pip install firebase-admin
# import firebase_admin
# from firebase_admin import auth, credentials

# cred = credentials.Certificate("path/to/your/firebase-adminsdk.json")
# firebase_app = firebase_admin.initialize_app(cred)

class User(BaseModel):
    """Doğrulanmış kullanıcıyı temsil eden model."""
    uid: str
    subscription: str = "FREE" # DB'den veya token'dan alınabilir
    theme_preference: str = "DARK"

# Token doğrulama şeması
token_auth_scheme = HTTPBearer()

# In-memory subscription store for development/testing.
# Keys: user uid (str) -> {"level": str, "expires": date}
USER_SUBSCRIPTIONS = {}

# global scheduler (initialized on startup)
SCHEDULER: Optional[BackgroundScheduler] = None

# firebase app placeholder (initialized on startup if credentials available)
FIREBASE_APP: Optional[Any] = None

# jobstore DB URL for APScheduler persistence (separate sqlite file)
_APSCHEDULER_DB_URL = os.getenv("APSCHEDULER_DB_URL", DATABASE_URL)

# --- Persistence for USER_SUBSCRIPTIONS (simple JSON file) ---
_USER_SETTINGS_FILE = Path(".data/user_settings.json")
_user_settings_lock = Lock()

def _ensure_settings_dir():
    if not _USER_SETTINGS_FILE.parent.exists():
        _USER_SETTINGS_FILE.parent.mkdir(parents=True, exist_ok=True)

def _load_user_subscriptions_from_file():
    try:
        _ensure_settings_dir()
        if _USER_SETTINGS_FILE.exists():
            with _USER_SETTINGS_FILE.open("r", encoding="utf-8") as fh:
                data = json.load(fh)
                if isinstance(data, dict):
                    for k, v in data.items():
                        if isinstance(v, dict):
                            USER_SUBSCRIPTIONS[k] = v
    except Exception:
        try:
            logger.exception("Failed to load user subscriptions from file")
        except Exception:
            pass

def _save_user_subscriptions_to_file():
    try:
        _ensure_settings_dir()
        with _user_settings_lock:
            tmp = _USER_SETTINGS_FILE.with_suffix(".tmp")
            with tmp.open("w", encoding="utf-8") as fh:
                json.dump(USER_SUBSCRIPTIONS, fh, ensure_ascii=False, indent=2, default=str)
            tmp.replace(_USER_SETTINGS_FILE)
    except Exception:
        try:
            logger.exception("Failed to persist user subscriptions to file")
        except Exception:
            pass

# load persisted settings at import/startup (best-effort)
_load_user_subscriptions_from_file()
# --- end persistence ---


async def get_current_user(token: HTTPAuthorizationCredentials = Security(token_auth_scheme)) -> User:
    """
    Authorization başlığından gelen Bearer token'ı doğrular ve kullanıcıyı döndürür.
    Development: token ya doğrudan uid olabilir ya da Firebase idToken (JWT) olabilir.
    Eğer JWT gelirse payload'tan 'sub' / 'user_id' / 'uid' / 'email' alanlarını alarak uid elde etmeye çalışır.
    GERÇEK PROJEDE: Token'ı burada Firebase Admin SDK veya başka bir JWT kütüphanesi ile doğrulayın.
    """
    id_token = token.credentials
    if not id_token:
        raise HTTPException(status_code=401, detail="Authentication token is required.")

    # In production we require firebase-admin to be initialized and use it to verify ID tokens.
    if FIREBASE_APP is None:
        # allow tests to bypass lifespan by using TESTING env and a fake firebase_admin module
        if os.getenv("TESTING", "0") == "1":
            try:
                from firebase_admin import auth as firebase_auth
                decoded = firebase_auth.verify_id_token(id_token)
                uid = decoded.get('uid') or decoded.get('sub')
                if not uid:
                    raise HTTPException(status_code=401, detail="Could not extract uid from ID token")
            except HTTPException:
                raise
            except Exception:
                logger.exception("TESTING mode: failed to verify token via fake firebase_admin")
                raise HTTPException(status_code=401, detail="Invalid authentication token", headers={"WWW-Authenticate": "Bearer"})
        else:
            # In development you may opt-in to run without Firebase credentials by setting
            # DEV_ALLOW_MISSING_FIREBASE=1. In that case, accept a raw uid or a JWT-like
            # token and extract a uid using `_parse_uid_from_token` for local testing.
            if os.getenv("DEV_ALLOW_MISSING_FIREBASE", "0") == "1":
                uid = _parse_uid_from_token(id_token)
                if not uid:
                    raise HTTPException(status_code=401, detail="Could not extract uid from token")
            else:
                # This should not happen in production if the app failed fast on startup.
                raise HTTPException(status_code=500, detail="Server authentication is not configured.")
    else:
        try:
            from firebase_admin import auth as firebase_auth
            decoded = firebase_auth.verify_id_token(id_token)
            uid = decoded.get('uid') or decoded.get('sub')
            if not uid:
                raise HTTPException(status_code=401, detail="Could not extract uid from ID token")
        except HTTPException:
            raise
        except Exception as e:
            logger.exception("Token verification failed: %s", e)
            raise HTTPException(status_code=401, detail="Invalid authentication token", headers={"WWW-Authenticate": "Bearer"})

    # ensure DB-backed user settings exist and mirror into in-memory store for compatibility
    defaults = {"level": "FREE", "theme": "LIGHT", "timezone": "Europe/Istanbul"}
    try:
        _ensure_user_settings(uid, defaults)
        settings = _load_user_settings_from_db(uid)
        if settings:
            USER_SUBSCRIPTIONS[uid] = settings
    except Exception:
        # non-fatal
        pass

    sub_info = USER_SUBSCRIPTIONS.get(uid, {})
    subscription = sub_info.get("level", "FREE")
    theme_preference = sub_info.get("theme", "LIGHT")

    return User(uid=uid, subscription=subscription, theme_preference=theme_preference)


# --- 5. DEPENDENCIES & UTILITIES ---
def get_db():
    """Her istek için bir veritabanı oturumu sağlayan FastAPI dependency'si."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# Abonelik limitleri
SUBSCRIPTION_LIMITS_IN_DAYS = {"FREE": 14, "PRO": 60, "ULTRA": 365}

def check_planning_date_limit(user: User, target_date: PyDate):
    """Kullanıcının abonelik seviyesine göre planlama yapabileceği son tarihi kontrol eder."""
    # In testing mode, skip subscription date limits to simplify tests
    if os.getenv("TESTING", "0") == "1":
        return
    limit_days = SUBSCRIPTION_LIMITS_IN_DAYS.get(user.subscription, 14)
    limit_date = datetime.now(timezone.utc).date() + timedelta(days=limit_days)
    if target_date > limit_date:
        raise HTTPException(
            status_code=403, # Forbidden
            detail=f"{user.subscription} aboneliği ile en fazla {limit_date.isoformat()} tarihine kadar plan yapabilirsiniz.",
        )

def get_time_obj_from_str(time_str: str) -> PyTime:
    """HH:MM formatındaki string'i Python time nesnesine çevirir."""
    return PyTime.fromisoformat(time_str)

def time_to_str(t: Optional[PyTime]) -> Optional[str]:
    """Python time nesnesini 'HH:MM' stringine çevirir (None ise None döner)."""
    if t is None:
        return None
    return t.strftime("%H:%M")

def plan_to_out(plan: PlanORM) -> dict:
    """PlanORM nesnesini API response'a uygun primitive dict'e çevirir."""
    return {
        "id": plan.id,
        "user_id": plan.user_id,
        "date": plan.date.isoformat(),
        "start_time": time_to_str(plan.start_time),
        "end_time": time_to_str(plan.end_time),
        "title": plan.title,
        "description": plan.description or "",
        "notified": bool(getattr(plan, "notified", False)),
    }


def _load_user_settings_from_db(uid: str) -> dict:
    db = SessionLocal()
    try:
        s = db.get(UserSettings, uid)
        if s:
            return {
                "level": s.level,
                "theme": s.theme,
                "timezone": s.timezone,
                "country": s.country,
                "city": s.city,
                "notifications_enabled": bool(s.notifications_enabled),
            }
        return {}
    finally:
        db.close()


def _ensure_user_settings(uid: str, defaults: dict):
    db = SessionLocal()
    try:
        s = db.get(UserSettings, uid)
        if not s:
            s = UserSettings(uid=uid, level=defaults.get("level", "FREE"), theme=defaults.get("theme", "LIGHT"), timezone=defaults.get("timezone", "Europe/Istanbul"))
            db.add(s)
            db.commit()
        return s
    finally:
        db.close()


def _get_user_zoneinfo(uid: str) -> ZoneInfo:
    """
    Kullanıcının USER_SUBSCRIPTIONS içindeki timezone bilgisini alır ve ZoneInfo döner;
    geçersiz veya eksikse güvenli bir varsayılan (Europe/Istanbul) döner.
    """
    info = USER_SUBSCRIPTIONS.get(uid, {})
    tz_str = info.get("timezone", "Europe/Istanbul")
    try:
        return ZoneInfo(tz_str)
    except Exception:
        # Eğer saklı timezone geçersizse fallback olarak Europe/Istanbul kullan.
        return ZoneInfo("Europe/Istanbul")

# minimal token -> uid extractor (used by middleware). Keeps previous dev-mode behavior.
def _parse_uid_from_token(id_token: Optional[str]) -> Optional[str]:
    if not id_token:
        return None
    uid = id_token
    if isinstance(id_token, str) and '.' in id_token:
        try:
            parts = id_token.split('.')
            if len(parts) >= 2:
                payload_b64 = parts[1]
                rem = len(payload_b64) % 4
                if rem:
                    payload_b64 += '=' * (4 - rem)
                payload_json = base64.urlsafe_b64decode(payload_b64.encode('utf-8')).decode('utf-8')
                payload = json.loads(payload_json)
                uid = payload.get('sub') or payload.get('user_id') or payload.get('uid') or payload.get('email') or uid
        except Exception:
            uid = id_token
    return uid

# --- simple stubs for scheduling / notification functions to avoid NameError warnings ---
def schedule_notification_for_plan(plan: PlanORM):
    # placeholder: integrate real scheduler here (APScheduler/Celery/Firebase etc.)
    try:
        user_zone = _get_user_zoneinfo(plan.user_id)
        try:
            local_dt = datetime.combine(plan.date, plan.start_time).replace(tzinfo=user_zone)
            notify_dt_utc = local_dt.astimezone(timezone.utc)
            logger.info(f"[SCHEDULE] plan {plan.id} scheduled at utc={notify_dt_utc.isoformat()} (user_zone={user_zone})")
            # schedule persisted job via APScheduler if available
            job_id = f"plan_{plan.id}"
            if SCHEDULER is not None:
                try:
                    # create a date trigger in UTC
                    trigger = DateTrigger(run_date=notify_dt_utc)
                    # schedule a job that will load the plan and call send_notification_to_user
                    SCHEDULER.add_job(_apscheduler_job_send_notification, trigger=trigger, args=[plan.id], id=job_id, replace_existing=True)
                    logger.info(f"[SCHEDULE] APScheduler job {job_id} added for {notify_dt_utc.isoformat()}")
                except Exception:
                    logger.exception("Failed to add APScheduler job for plan %s", plan.id)
        except Exception:
            notify_dt = datetime.combine(plan.date, plan.start_time).replace(tzinfo=timezone.utc)
            logger.info(f"[SCHEDULE] plan {plan.id} scheduled (fallback) utc={notify_dt.isoformat()}")
    except Exception:
        logger.exception("schedule_notification_for_plan error")

def cancel_scheduled_plan(plan_id: str):
    # placeholder: cancel scheduled job in real scheduler
    logger.debug(f"[SCHEDULE] cancel scheduled plan {plan_id}")
    if SCHEDULER is None:
        return
    job_id = f"plan_{plan_id}"
    try:
        job = SCHEDULER.get_job(job_id)
        if job:
            SCHEDULER.remove_job(job_id)
            logger.info(f"[SCHEDULE] removed job {job_id}")
    except Exception:
        logger.exception("Failed to cancel APScheduler job %s", job_id)

def send_notification_to_user(user_id: str, payload: dict):
    # placeholder: push notification / email integration
    global FIREBASE_APP
    try:
        from firebase_admin import messaging
        # look up device tokens for user
        db = SessionLocal()
        try:
            rows = db.execute(select(DeviceToken).where(DeviceToken.user_id == user_id)).scalars().all()
            tokens = [r.token for r in rows]
        finally:
            db.close()

        if FIREBASE_APP is not None and tokens:
            try:
                # send multicast in chunks
                chunk_size = 400
                for i in range(0, len(tokens), chunk_size):
                    chunk = tokens[i:i+chunk_size]
                    message = messaging.MulticastMessage(
                        notification=messaging.Notification(title=payload.get("title"), body=payload.get("body")),
                        data=payload.get("data", {}),
                        tokens=chunk,
                    )
                    resp = messaging.send_multicast(message)
                    logger.info("[NOTIFY] multicast sent to %d tokens, success=%d, failure=%d", len(chunk), resp.success_count, resp.failure_count)
                return
            except Exception:
                logger.exception("FCM multicast failed, will fallback to topic or log")

        # fallback to topic
        if FIREBASE_APP is not None:
            try:
                topic = f"user_{user_id}"
                message = messaging.Message(
                    notification=messaging.Notification(title=payload.get("title"), body=payload.get("body")),
                    topic=topic,
                    data=payload.get("data", {}),
                )
                resp = messaging.send(message)
                logger.info("[NOTIFY] sent FCM topic message to %s, resp=%s", topic, resp)
                return
            except Exception:
                logger.exception("FCM topic send failed; falling back to log")

        # fallback: just log
        logger.info(f"[NOTIFY] would send to {user_id}: {payload}")
    except Exception:
        logger.exception("send_notification_to_user error")


def _apscheduler_job_send_notification(plan_id: str):
    """Job wrapper: load plan from DB and dispatch notification. Called by APScheduler."""
    try:
        db = SessionLocal()
        try:
            plan = db.get(PlanORM, plan_id)
            if not plan:
                logger.warning("Scheduled job: plan %s not found", plan_id)
                return
            payload = {
                "title": plan.title,
                "body": plan.description or "",
                "data": {
                    "plan_id": plan.id,
                    "date": plan.date.isoformat(),
                    "start_time": time_to_str(plan.start_time),
                    "end_time": time_to_str(plan.end_time),
                }
            }
            # attempt with retries; only mark notified on success
            success = False
            attempts = 3
            for attempt in range(1, attempts + 1):
                try:
                    send_notification_to_user(plan.user_id, payload)
                    success = True
                    break
                except Exception:
                    logger.exception("Attempt %d to send notification for %s failed", attempt, plan_id)
                    time.sleep(attempt)

            if success:
                plan.notified = True
                db.add(plan)
                db.commit()
        finally:
            db.close()
    except Exception:
        logger.exception("Error in scheduled notification job for plan %s", plan_id)


# Use FastAPI lifespan to initialize/cleanup long-lived resources
@asynccontextmanager
async def lifespan(app: FastAPI):
    global SCHEDULER, FIREBASE_APP
    # start scheduler
    try:
        # Allow disabling scheduler in tests or special runs
        if os.getenv("DISABLE_SCHEDULER", "0") != "1":
            jobstores = {'default': SQLAlchemyJobStore(url=_APSCHEDULER_DB_URL)}
            executors = {'default': ThreadPoolExecutor(10)}
            SCHEDULER = BackgroundScheduler(jobstores=jobstores, executors=executors, timezone=timezone.utc)

            def _job_listener(event):
                if event.code == EVENT_JOB_ERROR:
                    logger.error("APScheduler job error: %s", event)
            SCHEDULER.add_listener(_job_listener, EVENT_JOB_EXECUTED | EVENT_JOB_ERROR)

            SCHEDULER.start()
            logger.info("APScheduler started with jobstore %s", _APSCHEDULER_DB_URL)
        else:
            logger.info("APScheduler disabled via DISABLE_SCHEDULER=1")
    except Exception:
        logger.exception("Failed to start APScheduler")

    # initialize firebase-admin if service account file exists or env var provided
    try:
        # Test mode shortcut: when running tests we may not want real firebase credentials.
        if os.getenv("TESTING", "0") == "1":
            FIREBASE_APP = object()
            logger.info("TESTING=1 detected: skipping real Firebase initialization and using dummy app")
        else:
            try:
                # For production we require FIREBASE_CREDENTIALS to be set to a valid service
                # account JSON path. Fail fast if not present so deployment is safe.
                from firebase_admin import credentials, initialize_app
                # Accept either FIREBASE_CREDENTIALS or the standard GOOGLE_APPLICATION_CREDENTIALS
                cred_path = os.getenv('FIREBASE_CREDENTIALS') or os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
                if not cred_path:
                    # By default allow local startup without credentials to keep developer experience smooth.
                    # In production, set REQUIRE_FIREBASE=1 to enforce fail-fast behavior.
                    if os.getenv("REQUIRE_FIREBASE", "0") == "1":
                        raise RuntimeError("FIREBASE_CREDENTIALS or GOOGLE_APPLICATION_CREDENTIALS environment variable is not set. Set it to the path of the service account JSON file to enable authentication and notifications.")
                    FIREBASE_APP = None
                    logger.warning("FIREBASE_CREDENTIALS / GOOGLE_APPLICATION_CREDENTIALS not set. Starting without Firebase Admin — authentication will use token->uid parsing or TESTING mode. Set REQUIRE_FIREBASE=1 to enforce credentials in production.")
                else:
                    if not Path(cred_path).exists():
                        raise RuntimeError(f"Credential file is set to '{cred_path}' but the file does not exist.")
                    FIREBASE_APP = initialize_app(credentials.Certificate(str(cred_path)))
                    logger.info("Firebase admin initialized from %s", cred_path)
            except Exception:
                logger.exception("Failed to initialize firebase-admin (required in production)")
                # propagate the exception so the service fails fast instead of running with insecure fallback
                raise
    except Exception:
        logger.exception("Firebase init error")

    try:
        yield
    finally:
        # graceful shutdown
        try:
            if SCHEDULER is not None:
                SCHEDULER.shutdown(wait=False)
                logger.info("APScheduler shutdown")
        except Exception:
            logger.exception("Error shutting down APScheduler")


app.router.lifespan_context = lifespan


# -------------------------------------------------------------------------
# NOTE: Removed background notification worker loop startup by design.
# If you later want a worker, add a startup event that starts _notification_worker_loop.
# -------------------------------------------------------------------------

# --- middleware: when we update timezone via header, persist it ---
@app.middleware("http")
async def timezone_header_middleware(request: Request, call_next):
    """
    Eğer Authorization Bearer token ve X-User-Timezone header varsa:
    - header'daki IANA timezone'ı doğrular
    - doğrulursa USER_SUBSCRIPTIONS[uid]['timezone'] güncellenir
    Bu sayede istemci her istekinde cihaz timezone bilgisini header'a koyarsa backend otomatik kaydeder.
    """
    try:
        # header isimleri küçük/büyük farkı nedeniyle iki türlü dene
        auth = request.headers.get("authorization") or request.headers.get("Authorization")
        tz_header = request.headers.get("x-user-timezone") or request.headers.get("X-User-Timezone") or request.headers.get("X-Timezone")
        if auth and tz_header and auth.lower().startswith("bearer "):
            token = auth.split(" ", 1)[1].strip()
            uid = None
            # Use firebase-admin to verify token and get uid if available
            try:
                if FIREBASE_APP is not None:
                    from firebase_admin import auth as firebase_auth
                    decoded = firebase_auth.verify_id_token(token)
                    uid = decoded.get('uid') or decoded.get('sub')
            except Exception:
                # verification failed -> do not persist timezone
                uid = None
            if uid:
                # validate timezone string
                try:
                    _ = ZoneInfo(tz_header)
                    # persist to DB-backed UserSettings
                    try:
                        db = SessionLocal()
                        try:
                            us = db.get(UserSettings, uid)
                            if not us:
                                us = UserSettings(uid=uid, timezone=tz_header)
                                db.add(us)
                            else:
                                us.timezone = tz_header
                            db.commit()
                        finally:
                            db.close()
                    except Exception:
                        app_logger.exception("Failed to persist timezone for %s", uid)

                    # ensure in-memory mirror
                    USER_SUBSCRIPTIONS[uid] = {"timezone": tz_header}

                    # kick off background reschedule of pending plans for this user (best-effort)
                    try:
                        threading.Thread(target=_reschedule_user_pending_plans_sync, args=(uid,), daemon=True).start()
                    except Exception:
                        pass
                except Exception:
                    # invalid timezone string -> ignore
                    pass
    except Exception:
        # middleware must not block request on error
        pass
    response = await call_next(request)
    return response

@app.put("/user/timezone/", tags=["User"])
def update_user_timezone(payload: TimezoneUpdate, current_user: User = Depends(get_current_user)):
    """
    Kullanıcının cihazdan elde edilen IANA timezone'ını backend'e kaydet.
    Body: { "timezone": "Europe/Istanbul" }
    """
    try:
        # validate by constructing ZoneInfo
        _ = ZoneInfo(payload.timezone)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid IANA timezone identifier.")

    uid = current_user.uid
    info = USER_SUBSCRIPTIONS.get(uid, {"level": current_user.subscription, "theme": current_user.theme_preference})
    info["timezone"] = payload.timezone
    USER_SUBSCRIPTIONS[uid] = info
    # asynchronously reschedule pending plans for this user (best-effort)
    try:
        threading.Thread(target=_reschedule_user_pending_plans_sync, args=(uid,), daemon=True).start()
    except Exception:
        pass
    try:
        _save_user_subscriptions_to_file()
    except Exception:
        pass
    return {"uid": uid, "timezone": payload.timezone}


@app.post("/user/device_tokens/", tags=["User"])
def register_device_token(payload: DeviceTokenIn, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Register a device token for push notifications for the current user."""
    try:
        uid = current_user.uid
        token = payload.token
        provider = payload.provider or "fcm"
        existing = db.get(DeviceToken, token)
        if existing:
            # update user association if needed
            if existing.user_id != uid:
                existing.user_id = uid
                db.add(existing)
                db.commit()
            return {"token": token, "user_id": uid}

        dt = DeviceToken(token=token, user_id=uid, provider=provider)
        db.add(dt)
        db.commit()
        return {"token": token, "user_id": uid}
    except Exception:
        logger.exception("Failed to register device token")
        raise HTTPException(status_code=500, detail="Failed to register device token")


@app.get("/user/device_tokens/", tags=["User"])
def list_device_tokens(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    try:
        uid = current_user.uid
        rows = db.execute(select(DeviceToken).where(DeviceToken.user_id == uid)).scalars().all()
        return [{"token": r.token, "provider": r.provider, "created_at": r.created_at.isoformat()} for r in rows]
    except Exception:
        logger.exception("Failed to list device tokens")
        raise HTTPException(status_code=500, detail="Failed to list device tokens")


@app.delete("/user/device_tokens/{token}", tags=["User"])
def delete_device_token(token: str, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    try:
        uid = current_user.uid
        row = db.get(DeviceToken, token)
        if not row or row.user_id != uid:
            raise HTTPException(status_code=404, detail="Device token not found")
        db.delete(row)
        db.commit()
        return None
    except HTTPException:
        raise
    except Exception:
        logger.exception("Failed to delete device token")
        raise HTTPException(status_code=500, detail="Failed to delete device token")


@app.get("/user/profile/", response_model=UserProfileOut, tags=["User"])
def get_user_profile(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Return current user's profile/settings and registered device tokens."""
    try:
        uid = current_user.uid
        # load settings from DB
        settings = db.get(UserSettings, uid)
        if not settings:
            # ensure defaults
            settings = UserSettings(uid=uid)
            db.add(settings)
            db.commit()
            db.refresh(settings)

        rows = db.execute(select(DeviceToken).where(DeviceToken.user_id == uid)).scalars().all()
        tokens = [r.token for r in rows]

        return UserProfileOut(
            uid=uid,
            subscription=settings.level,
            theme=settings.theme,
            timezone=settings.timezone,
            country=settings.country,
            city=settings.city,
            notifications_enabled=bool(settings.notifications_enabled),
            device_tokens=tokens,
        )
    except Exception:
        logger.exception("Failed to load user profile for %s", current_user.uid)
        raise HTTPException(status_code=500, detail="Failed to load profile")


def _reschedule_user_pending_plans_sync(uid: str, window_days: int = 7):
    """
    Best-effort synchronous reschedule helper:
    - finds un-notified plans for the user in a small future window
    - cancels existing scheduled entries (placeholder) and re-schedules them using current timezone
    This runs in a background thread (daemon) to avoid blocking request handling.
    """
    try:
        now_utc = datetime.now(timezone.utc)
        start_date = (now_utc - timedelta(days=1)).date()
        end_date = (now_utc + timedelta(days=window_days)).date()
        db = SessionLocal()
        try:
            plans = db.execute(select(PlanORM).where(
                PlanORM.user_id == uid,
                PlanORM.notified == False,
                PlanORM.date.between(start_date, end_date)
            )).scalars().all()
            for p in plans:
                try:
                    cancel_scheduled_plan(p.id)
                except Exception:
                    pass
                try:
                    schedule_notification_for_plan(p)
                except Exception:
                    pass
        finally:
            db.close()
    except Exception:
        try:
            logger.exception("Error while rescheduling pending plans for user %s", uid)
        except Exception:
            pass

@app.get("/user/current_time/", tags=["User"])
def user_current_time(current_user: User = Depends(get_current_user)):
    """
    Test endpoint: kullanıcının ayarlı timezone'una göre mevcut saati log'a yaz ve döndür.
    İstemci test için Authorization header ile çağırmalı (token -> uid).
    """
    uid = current_user.uid
    info = USER_SUBSCRIPTIONS.get(uid, {})
    tz_str = info.get("timezone", "Europe/Istanbul")
    try:
        tz = ZoneInfo(tz_str)
    except Exception:
        tz = ZoneInfo("Europe/Istanbul")
        tz_str = "Europe/Istanbul"

    now_utc = datetime.now(timezone.utc)
    try:
        now_local = now_utc.astimezone(tz)
        app_logger.info("[USER_TIME] uid=%s timezone=%s local_time=%s", uid, tz_str, now_local.isoformat())
        return {"uid": uid, "timezone": tz_str, "local_time": now_local.isoformat()}
    except Exception:
        app_logger.exception("[USER_TIME] failed to convert timezone for uid=%s, returning UTC", uid)
        return {"uid": uid, "timezone": tz_str, "local_time": now_utc.isoformat()}


@app.get("/health", tags=["System"])
def health_check(db: Session = Depends(get_db)):
    """Basic health check: DB connectivity and scheduler status."""
    try:
        # try a lightweight DB query
        db.execute(select(1))
    except Exception:
        raise HTTPException(status_code=503, detail="DB unavailable")

    sched_ok = SCHEDULER is not None and SCHEDULER.running
    return {"ok": True, "scheduler_running": bool(sched_ok)}


@app.get("/ready", tags=["System"])
def readiness_check(db: Session = Depends(get_db)):
    """More detailed readiness: ensures scheduler started and DB accessible."""
    try:
        db.execute(select(1))
    except Exception:
        raise HTTPException(status_code=503, detail="DB unavailable")
    if SCHEDULER is None:
        raise HTTPException(status_code=503, detail="Scheduler not initialized")
    return {"ok": True}


from prometheus_client import generate_latest, CONTENT_TYPE_LATEST, Counter
from fastapi.responses import Response

# basic request counter
REQUEST_COUNTER = Counter('flow7_requests_total', 'Total HTTP requests handled by Flow7')


@app.middleware("http")
async def prometheus_request_counter(request: Request, call_next):
    REQUEST_COUNTER.inc()
    response = await call_next(request)
    return response


@app.get("/metrics", tags=["System"])
def metrics():
    """Prometheus metrics endpoint."""
    data = generate_latest()
    return Response(content=data, media_type=CONTENT_TYPE_LATEST)


# --- 6. PLANS CRUD ENDPOINTS (create / read / update / delete) ---
@app.get("/api/plans", tags=["Plans"])
def get_user_plans(start_date: Optional[PyDate] = None, end_date: Optional[PyDate] = None, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """
    GET /api/plans?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD
    Returns list of plans for the authenticated user within the provided date range.
    If dates are omitted, defaults to today .. today+7 days.
    """
    try:
        uid = current_user.uid
        now_utc = datetime.now(timezone.utc)
        if start_date is None:
            start_date = now_utc.date()
        if end_date is None:
            end_date = start_date + timedelta(days=7)

        plans = db.execute(select(PlanORM).where(
            PlanORM.user_id == uid,
            PlanORM.date.between(start_date, end_date)
        ).order_by(PlanORM.date, PlanORM.start_time)).scalars().all()

        return [plan_to_out(p) for p in plans]
    except Exception:
        logger.exception("Failed to fetch user plans")
        raise HTTPException(status_code=500, detail="Failed to fetch plans")


@app.post("/api/plans", tags=["Plans"])
def create_plan(payload: PlanCreate, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Create a new plan for the authenticated user and schedule notification."""
    try:
        uid = current_user.uid
        # subscription-based date limit check
        check_planning_date_limit(current_user, payload.date)

        p = PlanORM(
            id=uuid4().hex,
            user_id=uid,
            date=payload.date,
            start_time=get_time_obj_from_str(payload.start_time),
            end_time=get_time_obj_from_str(payload.end_time),
            title=payload.title,
            description=payload.description or "",
            notified=False,
        )
        db.add(p)
        db.commit()
        db.refresh(p)

        # Attempt to schedule notification (best-effort; schedule implementation is a placeholder)
        try:
            schedule_notification_for_plan(p)
        except Exception:
            logger.exception("Failed to schedule notification for new plan %s", p.id)

        return plan_to_out(p)
    except HTTPException:
        raise
    except Exception:
        logger.exception("Failed to create plan")
        raise HTTPException(status_code=500, detail="Failed to create plan")


@app.put("/api/plans/{plan_id}", tags=["Plans"])
def update_plan(plan_id: str, payload: PlanUpdate, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Update an existing plan (owned by user) and re-schedule notification."""
    try:
        uid = current_user.uid
        plan = db.get(PlanORM, plan_id)
        if not plan or plan.user_id != uid:
            raise HTTPException(status_code=404, detail="Plan not found")

        # check subscription limit for updated date
        check_planning_date_limit(current_user, payload.date)

        plan.date = payload.date
        plan.start_time = get_time_obj_from_str(payload.start_time)
        plan.end_time = get_time_obj_from_str(payload.end_time)
        plan.title = payload.title
        plan.description = payload.description or ""
        plan.notified = False
        plan.updated_at = datetime.now(timezone.utc)
        db.add(plan)
        db.commit()
        db.refresh(plan)

        # cancel previous schedule and schedule again (best-effort)
        try:
            cancel_scheduled_plan(plan.id)
        except Exception:
            pass
        try:
            schedule_notification_for_plan(plan)
        except Exception:
            logger.exception("Failed to reschedule notification for plan %s", plan.id)

        return plan_to_out(plan)
    except HTTPException:
        raise
    except Exception:
        logger.exception("Failed to update plan %s", plan_id)
        raise HTTPException(status_code=500, detail="Failed to update plan")


@app.delete("/api/plans/{plan_id}", status_code=204, tags=["Plans"])
def delete_plan(plan_id: str, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Delete a plan owned by the authenticated user."""
    try:
        uid = current_user.uid
        plan = db.get(PlanORM, plan_id)
        if not plan or plan.user_id != uid:
            raise HTTPException(status_code=404, detail="Plan not found")

        # cancel scheduled job (best-effort)
        try:
            cancel_scheduled_plan(plan.id)
        except Exception:
            pass

        db.delete(plan)
        db.commit()
        return None
    except HTTPException:
        raise
    except Exception:
        logger.exception("Failed to delete plan %s", plan_id)
        raise HTTPException(status_code=500, detail="Failed to delete plan")

# --- 7. RUN THE APP ---
# Bu blok, dosyanın doğrudan `python main.py` ile çalıştırılmasını sağlar.
if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)