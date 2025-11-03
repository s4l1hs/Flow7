import os
from datetime import datetime, date as PyDate, time as PyTime, timedelta, timezone
from typing import List, Optional
from uuid import uuid4
import base64
import json

import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Depends, Security, logger, Request
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
    Integer as SA_Integer
)
import asyncio
from sqlalchemy.orm import declarative_base, sessionmaker, Session
from zoneinfo import ZoneInfo
import time
import threading
# Scheduler (APScheduler) for persistent per-plan jobs
APScheduler_AVAILABLE = False
try:
    from apscheduler.schedulers.background import BackgroundScheduler
    from apscheduler.schedulers.blocking import BlockingScheduler
    from apscheduler.jobstores.sqlalchemy import SQLAlchemyJobStore
    APScheduler_AVAILABLE = True
except Exception:
    APScheduler_AVAILABLE = False
# Optional firebase-admin for sending FCM push messages from server
FIREBASE_ADMIN_AVAILABLE = False
try:
    import firebase_admin
    from firebase_admin import credentials, messaging, auth
    FIREBASE_ADMIN_AVAILABLE = True
    FIREBASE_CREDENTIAL_PATH = os.getenv("FIREBASE_CREDENTIAL_PATH")
    if FIREBASE_CREDENTIAL_PATH:
        try:
            cred = credentials.Certificate(FIREBASE_CREDENTIAL_PATH)
            try:
                firebase_admin.initialize_app(cred)
            except Exception:
                # already initialized
                pass
        except Exception:
            FIREBASE_ADMIN_AVAILABLE = False
except Exception:
    FIREBASE_ADMIN_AVAILABLE = False

# --- 1. CONFIGURATION & DATABASE SETUP ---
# .env dosyasından ortam değişkenlerini yükle
load_dotenv()
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./flow7_revised.db")
# Auth / Firebase strict flags
REQUIRE_STRICT_AUTH = os.getenv("REQUIRE_STRICT_AUTH", "false").lower() == "true"
FIREBASE_CHECK_REVOKED = os.getenv("FIREBASE_CHECK_REVOKED", "false").lower() == "true"

# Fail-fast: if strict auth is required but firebase admin isn't available, abort startup
if REQUIRE_STRICT_AUTH and not FIREBASE_ADMIN_AVAILABLE:
    raise RuntimeError("REQUIRE_STRICT_AUTH=true but firebase_admin is not configured/available. Set FIREBASE_CREDENTIAL_PATH or disable REQUIRE_STRICT_AUTH in development.")

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
    # UTC timestamp for when we intend to send notification (persisted so restarts keep intent)
    notify_at = Column(SA_DateTime(timezone=True), nullable=True, index=True)
    created_at = Column(SA_DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(SA_DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))


# --- NEW: persistent user settings ORM ---
class UserSettings(Base):
    __tablename__ = "user_settings"
    uid = Column(String, primary_key=True, index=True)
    language_code = Column(String(8), nullable=True)
    theme = Column(String(16), nullable=True)
    notifications_enabled = Column(Boolean, default=True, nullable=False)
    timezone = Column(String(64), nullable=True)
    country = Column(String(64), nullable=True)
    city = Column(String(64), nullable=True)
    username = Column(String(128), nullable=True)
    # NEW: persist subscription info (migrate from in-memory USER_SUBSCRIPTIONS)
    subscription_level = Column(String(64), nullable=True, default="FREE")
    subscription_expires_at = Column(SA_DateTime(timezone=True), nullable=True)
    subscription_score = Column(SA_Integer, nullable=False, default=0)
    created_at = Column(SA_DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(SA_DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

# Device token storage for push targets (server-side)
class DeviceToken(Base):
    __tablename__ = "device_tokens"
    id = Column(String, primary_key=True, index=True, default=lambda: str(uuid4()))
    uid = Column(String, index=True, nullable=False)
    token = Column(String, nullable=False, unique=True)
    platform = Column(String(32), nullable=True)
    created_at = Column(SA_DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

# Veritabanı ve tabloları oluştur (yeni tablolar dahil)
Base.metadata.create_all(bind=engine)


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

def get_db():
    """Her istek için bir veritabanı oturumu sağlayan FastAPI dependency'si."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

async def get_current_user(
    token: HTTPAuthorizationCredentials = Security(token_auth_scheme),
    db: Session = Depends(get_db)  # <-- 1. DB BAĞIMLILIĞINI BURAYA EKLEYİN
) -> User:
    """
    Authorization başlığından gelen Bearer token'ı doğrular ve kullanıcıyı döndürür.
    ...
    """
    id_token = token.credentials
    if not id_token:
        raise HTTPException(status_code=401, detail="Kimlik doğrulama token'ı sağlanmadı.")

    # ... (Token doğrulama ve 'uid' alma mantığınız (satır 228-260) burada kalmalı) ...
    if FIREBASE_ADMIN_AVAILABLE:
        try:
            decoded = auth.verify_id_token(id_token, check_revoked=FIREBASE_CHECK_REVOKED)
            uid = decoded.get("uid") or decoded.get("sub") or decoded.get("user_id") or decoded.get("email")
            if not uid:
                raise HTTPException(status_code=401, detail="Token doğrulandı ama uid bulunamadı.")
        except Exception as e:
            raise HTTPException(status_code=401, detail=f"Invalid or revoked token: {e}", headers={"WWW-Authenticate": "Bearer"})
    else:
        # firebase_admin not available -> development fallback
        try:
            uid = id_token
            if isinstance(id_token, str) and "." in id_token:
                parts = id_token.split(".")
                if len(parts) >= 2:
                    payload_b64 = parts[1]
                    rem = len(payload_b64) % 4
                    if rem:
                        payload_b64 += "=" * (4 - rem)
                    payload_json = base64.urlsafe_b64decode(payload_b64.encode("utf-8")).decode("utf-8")
                    payload = json.loads(payload_json)
                    uid = payload.get("sub") or payload.get("user_id") or payload.get("uid") or payload.get("email") or uid
        except Exception:
            uid = id_token


    # --- NEW: read persistent settings from DB so subscription/theme are authoritative ---
    subscription = "FREE"
    theme_preference = "DARK"
    try:
        # db = SessionLocal() # <-- 2. BU SATIRI SİLİN
        # try:
        settings = db.get(UserSettings, uid) # <-- 3. BAĞIMLILIKTAN GELEN 'db' KULLANILACAK
        if settings:
            subscription = settings.subscription_level or subscription
            theme_preference = settings.theme or theme_preference
        else:
            # create default DB row from in-memory fallback if desired
            fallback = USER_SUBSCRIPTIONS.get(uid, {})
            settings = UserSettings(
                uid=uid,
                language_code=fallback.get("language_code") or "en",
                theme=fallback.get("theme") or theme_preference,
                notifications_enabled=bool(fallback.get("notifications_enabled", True)),
                timezone=fallback.get("timezone") or "Europe/Istanbul",
                country=fallback.get("country"),
                city=fallback.get("city"),
                username=fallback.get("username"),
                subscription_level=fallback.get("level") or "FREE",
            )
            db.add(settings)
            db.commit()
            db.refresh(settings)
            subscription = settings.subscription_level or subscription
            theme_preference = settings.theme or theme_preference
        # finally:
        #     db.close() # <-- 4. BU SATIRI SİLİN
    except Exception:
        # On DB error fall back to in-memory values (best-effort)
        sub_info = USER_SUBSCRIPTIONS.get(uid)
        if sub_info:
            subscription = sub_info.get("level", subscription)
            theme_preference = sub_info.get("theme", theme_preference)

    # Ensure a minimal in-memory entry exists for compatibility
    if uid not in USER_SUBSCRIPTIONS:
        USER_SUBSCRIPTIONS[uid] = {
            "level": subscription,
            "theme": theme_preference,
            "timezone": None,
            "notifications_enabled": True,
        }

    # Return the authenticated user model (subscription/theme populated from DB or fallback)
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


def _get_user_zoneinfo(uid: str) -> ZoneInfo:
    """
    Resolve the effective ZoneInfo for a user.
    Priority:
      1. session_timezone (temporary) if set and not expired
      2. persistent timezone stored in UserSettings.timezone
      3. fallback USER_SUBSCRIPTIONS timezone or Europe/Istanbul
    """
    try:
        db = SessionLocal()
        try:
            s = db.get(UserSettings, uid)
            if s:
                if s.timezone:
                    try:
                        return ZoneInfo(s.timezone)
                    except Exception:
                        pass
        finally:
            db.close()
    except Exception:
        pass
    # last fallback: in-memory or sensible default
    info = USER_SUBSCRIPTIONS.get(uid, {})
    tz_str = info.get("timezone", "Europe/Istanbul")
    try:
        return ZoneInfo(tz_str)
    except Exception:
        return ZoneInfo("Europe/Istanbul")


# --- 6. API ENDPOINTS (ROUTING) ---
app = FastAPI(
    title="Flow7 API",
    description="Flow7 planlama uygulaması için FastAPI arka uç servisi.",
    version="2.0.0",
)

# --- CORS (development için; production'da kökenleri kısıtlayın) ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],                # development: tüm kökenlere izin. Prod: listeleyin.
    allow_credentials=True,
    allow_methods=["*"],                # GET, POST, PUT, DELETE, OPTIONS vb.
    allow_headers=["*"],                # Authorization dahil tüm başlıklara izin
)

@app.get("/api/status", tags=["General"])
def get_api_status():
    """API'nin sağlık durumunu kontrol eder."""
    return {"status": "ok", "version": "2.0.0", "timestamp": datetime.now(timezone.utc)}

@app.post("/api/plans", response_model=PlanOut, status_code=201, tags=["Plans"])
def create_plan(
    plan_data: PlanCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Yeni bir kullanıcı planı oluşturur.
    """
    check_planning_date_limit(current_user, plan_data.date)

    start_time_obj = get_time_obj_from_str(plan_data.start_time)
    end_time_obj = get_time_obj_from_str(plan_data.end_time)

    # Çakışma kontrolü
    existing_plan = db.execute(select(PlanORM).where(
        PlanORM.user_id == current_user.uid,
        PlanORM.date == plan_data.date,
        PlanORM.start_time < end_time_obj,
        PlanORM.end_time > start_time_obj
    )).scalars().first()

    if existing_plan:
        raise HTTPException(status_code=409, detail="Belirtilen zaman aralığında mevcut bir planınız var (zaman çakışması).")

    new_plan = PlanORM(
        id=str(uuid4()),
        user_id=current_user.uid,
        date=plan_data.date,
        start_time=start_time_obj,
        end_time=end_time_obj,
        title=plan_data.title,
        description=plan_data.description,
        notified=False,
    )
    db.add(new_plan)
    db.commit()
    db.refresh(new_plan)

    # Schedule if the plan is for today and its start_time is still in the future
    try:
        now = datetime.now(timezone.utc)
        if new_plan.date == now.date():
            # compute notify datetime using user's timezone
            user_zone = _get_user_zoneinfo(new_plan.user_id)
            try:
                local_dt = datetime.combine(new_plan.date, new_plan.start_time).replace(tzinfo=user_zone)
                notify_dt = local_dt.astimezone(timezone.utc)
            except Exception:
                notify_dt = datetime.combine(new_plan.date, new_plan.start_time).replace(tzinfo=timezone.utc)
            if notify_dt > now and _user_notifications_enabled(new_plan.user_id):
                schedule_notification_for_plan(new_plan)
    except Exception:
        logger.exception("Error scheduling newly created plan %s", new_plan.id)

    return plan_to_out(new_plan)


@app.get("/api/plans", response_model=List[PlanOut], tags=["Plans"])
def get_user_plans_by_date_range(
    start_date: PyDate,
    end_date: PyDate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Belirtilen tarih aralığındaki tüm kullanıcı planlarını listeler."""
    if start_date > end_date:
        raise HTTPException(status_code=400, detail="Başlangıç tarihi, bitiş tarihinden sonra olamaz.")

    plans = db.execute(select(PlanORM).where(
        PlanORM.user_id == current_user.uid,
        PlanORM.date.between(start_date, end_date)
    ).order_by(PlanORM.date, PlanORM.start_time)).scalars().all()

    return [plan_to_out(p) for p in plans]


@app.put("/api/plans/{plan_id}", response_model=PlanOut, tags=["Plans"])
def update_plan(
    plan_id: str,
    plan_data: PlanUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Mevcut bir planı günceller.
    """
    db_plan = db.get(PlanORM, plan_id)
    if not db_plan:
        raise HTTPException(status_code=404, detail="Plan bulunamadı.")
    if db_plan.user_id != current_user.uid:
        raise HTTPException(status_code=403, detail="Bu planı güncelleme yetkiniz yok.")

    check_planning_date_limit(current_user, plan_data.date)

    start_time_obj = get_time_obj_from_str(plan_data.start_time)
    end_time_obj = get_time_obj_from_str(plan_data.end_time)

    # Kendisi hariç diğer planlarla çakışma kontrolü
    existing_plan = db.execute(select(PlanORM).where(
        PlanORM.id != plan_id,
        PlanORM.user_id == current_user.uid,
        PlanORM.date == plan_data.date,
        PlanORM.start_time < end_time_obj,
        PlanORM.end_time > start_time_obj
    )).scalars().first()

    if existing_plan:
        raise HTTPException(status_code=409, detail="Güncellenen zaman aralığı başka bir planla çakışıyor.")

    # Verileri güncelle (time alanlarını time objesine çevir)
    db_plan.date = plan_data.date
    db_plan.start_time = start_time_obj
    db_plan.end_time = end_time_obj
    db_plan.title = plan_data.title
    db_plan.description = plan_data.description
    # Reset notified flag if times changed (allow future notification)
    db_plan.notified = False
    db.commit()
    db.refresh(db_plan)

    # Re-schedule: cancel any existing task, then if updated plan is today and in future, schedule
    try:
        cancel_scheduled_plan(db_plan.id)
        now = datetime.now(timezone.utc)
        if db_plan.date == now.date():
            user_zone = _get_user_zoneinfo(db_plan.user_id)
            try:
                local_dt = datetime.combine(db_plan.date, db_plan.start_time).replace(tzinfo=user_zone)
                notify_dt = local_dt.astimezone(timezone.utc)
            except Exception:
                notify_dt = datetime.combine(db_plan.date, db_plan.start_time).replace(tzinfo=timezone.utc)
            if notify_dt > now and _user_notifications_enabled(db_plan.user_id):
                schedule_notification_for_plan(db_plan)
    except Exception:
        logger.exception("Error re-scheduling updated plan %s", db_plan.id)

    return plan_to_out(db_plan)


@app.delete("/api/plans/{plan_id}", status_code=204, tags=["Plans"])
def delete_plan(
    plan_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Mevcut bir planı siler."""
    db_plan = db.get(PlanORM, plan_id)
    if not db_plan:
        raise HTTPException(status_code=404, detail="Silinecek plan bulunamadı.")
    if db_plan.user_id != current_user.uid:
        raise HTTPException(status_code=403, detail="Bu planı silme yetkiniz yok.")

    # cancel scheduled task if any
    try:
        cancel_scheduled_plan(plan_id)
    except Exception:
        logger.exception("Error cancelling scheduled task for deleted plan %s", plan_id)

    db.delete(db_plan)
    db.commit()
    return

@app.put("/user/subscription/", tags=["User"])
def update_subscription(
    payload: SubscriptionUpdate,
    db: Session = Depends(get_db), 
    current_user: User = Depends(get_current_user),
):
    """
    Kullanıcının abonelik seviyesini veritabanında kalıcı olarak günceller.
    """
    settings = get_or_create_user_settings(current_user.uid, db)

    expires_dt = datetime.now(timezone.utc) + timedelta(days=payload.days)

    settings.subscription_level = payload.level
    settings.subscription_expires_at = expires_dt
    settings.updated_at = datetime.now(timezone.utc)
    
    db.add(settings)
    db.commit()
    db.refresh(settings)

    if current_user.uid in USER_SUBSCRIPTIONS:
         USER_SUBSCRIPTIONS[current_user.uid]["level"] = payload.level
         USER_SUBSCRIPTIONS[current_user.uid]["expires"] = expires_dt

    return {"uid": current_user.uid, "level": settings.subscription_level, "expires_at": settings.subscription_expires_at.isoformat()}


@app.get("/user/profile/", tags=["User"])
def user_profile(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """
    Basit profil endpoint'i: uid, subscriptionLevel, expires_at (varsa), theme_preference,
    language_code ve notifications_enabled.
    """
    uid = current_user.uid
    settings = get_or_create_user_settings(uid, db)
    expires = settings.subscription_expires_at
    return {
        "uid": uid,
        "subscriptionLevel": settings.subscription_level or current_user.subscription,
        "expires_at": expires.isoformat() if expires else None,
        "theme_preference": settings.theme or current_user.theme_preference,
        "language_code": settings.language_code or "en",
        "notifications_enabled": bool(settings.notifications_enabled),
        "username": settings.username,
        "score": int(settings.subscription_score or 0),
    }

class ThemePreferenceUpdate(BaseModel):
    """Kullanıcının tema tercihini güncellemek için kullanılan şema."""
    # Sadece 'LIGHT' veya 'DARK' kabul eder
    theme: str = Field(..., pattern=r"^(LIGHT|DARK)$", description="LIGHT veya DARK olmalı")

@app.put("/user/theme/", tags=["User"])
def update_user_theme(
    payload: ThemePreferenceUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    uid = current_user.uid
    settings = get_or_create_user_settings(uid, db)
    settings.theme = payload.theme
    settings.updated_at = datetime.now(timezone.utc)
    db.add(settings)
    db.commit()
    db.refresh(settings)
    return {"uid": uid, "theme_preference": settings.theme}

# --- ADD: Language & Notifications schemas ---
class LanguageUpdate(BaseModel):
    language_code: str = Field(..., min_length=2, max_length=8, description="ISO language code, e.g. 'en'")

class NotificationsUpdate(BaseModel):
    enabled: bool

@app.put("/user/language/", tags=["User"])
def update_user_language(payload: LanguageUpdate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    uid = current_user.uid
    settings = get_or_create_user_settings(uid, db)
    settings.language_code = payload.language_code
    settings.updated_at = datetime.now(timezone.utc)
    db.add(settings)
    db.commit()
    db.refresh(settings)
    return {"uid": uid, "language_code": settings.language_code}

@app.put("/user/notifications/", tags=["User"])
def update_user_notifications(payload: NotificationsUpdate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    uid = current_user.uid
    settings = get_or_create_user_settings(uid, db)
    settings.notifications_enabled = bool(payload.enabled)
    settings.updated_at = datetime.now(timezone.utc)
    db.add(settings)
    db.commit()
    db.refresh(settings)
    return {"uid": uid, "notifications_enabled": settings.notifications_enabled}

# --- ADD: notification worker ---
def get_or_create_user_settings(uid: str, db: Session):
    """
    DB'de user settings yoksa USER_SUBSCRIPTIONS içinden fallback alıp kaydeder.
    Dönen: UserSettings ORM instance
    """
    settings = db.get(UserSettings, uid)
    if settings:
        return settings
    # build from in-memory fallback if present
    fallback = USER_SUBSCRIPTIONS.get(uid, {})
    # try to extract subscription fields from fallback (if any)
    subs_level = fallback.get("level") or fallback.get("subscription_level") or "FREE"
    subs_expires = fallback.get("expires") or fallback.get("expires_at") or None
    # normalize expires to aware datetime in UTC if string or datetime
    subs_expires_dt = None
    try:
        if isinstance(subs_expires, str):
            subs_expires_dt = datetime.fromisoformat(subs_expires)
            if subs_expires_dt.tzinfo is None:
                subs_expires_dt = subs_expires_dt.replace(tzinfo=timezone.utc)
        elif isinstance(subs_expires, datetime):
            subs_expires_dt = subs_expires.astimezone(timezone.utc)
    except Exception:
        subs_expires_dt = None
    subs_score = int(fallback.get("score", fallback.get("subscription_score", 0) or 0))

    settings = UserSettings(
        uid=uid,
        language_code=fallback.get("language_code") or fallback.get("language") or "en",
        theme=fallback.get("theme") or "DARK",
        notifications_enabled=bool(fallback.get("notifications_enabled", True)),
        timezone=fallback.get("timezone") or "Europe/Istanbul",
        country=fallback.get("country"),
        city=fallback.get("city"),
        username=fallback.get("username"),
        subscription_level=subs_level,
        subscription_expires_at=subs_expires_dt,
        subscription_score=subs_score,
    )
    db.add(settings)
    db.commit()
    db.refresh(settings)
    return settings


def _user_notifications_enabled(uid: str) -> bool:
    """Return whether the user has notifications enabled (DB-backed with in-memory fallback)."""
    try:
        db = SessionLocal()
        try:
            s = db.get(UserSettings, uid)
            if s is not None:
                return bool(s.notifications_enabled)
        finally:
            db.close()
    except Exception:
        pass
    return bool(USER_SUBSCRIPTIONS.get(uid, {}).get("notifications_enabled", True))


def send_notification_to_user(uid: str, payload: dict):
    """
    Send a formatted notification to all device tokens of the given user.
    Payload example: {"title":..., "description":..., "start_time":..., "end_time":..., "date":...}
    """
    try:
        db = SessionLocal()
        try:
            rows = db.execute(select(DeviceToken.token).where(DeviceToken.uid == uid)).scalars().all()
        finally:
            db.close()

        if not rows:
            print(f"[NOTIFY] no device tokens for uid={uid}, payload={payload}")
            return

        # Resolve effective timezone for formatting times
        try:
            tz = _get_user_zoneinfo(uid)
        except Exception:
            tz = ZoneInfo("UTC")

        title = payload.get("title", "Flow7")
        description = payload.get("description", "") or ""

        # format start/end times into user's timezone if date provided
        start_display = payload.get("start_time", "")
        end_display = payload.get("end_time", "")
        try:
            date_str = payload.get("date")
            if date_str and start_display:
                d = PyDate.fromisoformat(date_str)
                st = PyTime.fromisoformat(start_display)
                local_dt = datetime.combine(d, st).replace(tzinfo=tz)
                start_display = local_dt.strftime("%H:%M")
            if date_str and end_display:
                et = PyTime.fromisoformat(end_display)
                end_local = datetime.combine(PyDate.fromisoformat(date_str), et).replace(tzinfo=tz)
                end_display = end_local.strftime("%H:%M")
        except Exception:
            # leave original strings if parsing fails
            pass

        # Build notification body per required format:
        # Title
        # Description
        # start_time - end_time
        body_lines = [title]
        if description:
            body_lines.append(description)
        times_line = ""
        if start_display and end_display:
            times_line = f"{start_display} - {end_display}"
        elif start_display:
            times_line = f"{start_display}"
        if times_line:
            body_lines.append(times_line)
        body = "\n".join(body_lines)

        # Send via firebase-admin if configured
        # Be robust: some firebase_admin versions or runtime environments may not have
        # messaging.send_multicast or may behave differently. Try multicast first,
        # on failure fall back to per-token send with retries and exponential backoff.
        FIREBASE_RETRIES = int(os.getenv("FIREBASE_SEND_RETRIES", "3"))
        FIREBASE_BACKOFF = float(os.getenv("FIREBASE_SEND_BACKOFF", "0.5"))

        if FIREBASE_ADMIN_AVAILABLE:
            try:
                tokens = list(rows)
                data_payload = {"type": "plan_notification", "date": payload.get("date",""), "start_time": payload.get("start_time",""), "end_time": payload.get("end_time","")}

                # Try multicast if available
                if hasattr(messaging, "send_multicast") and hasattr(messaging, "MulticastMessage"):
                    try:
                        message = messaging.MulticastMessage(
                            notification=messaging.Notification(title=title, body=body),
                            data=data_payload,
                            tokens=tokens,
                        )
                        response = messaging.send_multicast(message)
                        # response may have success_count/failure_count and responses list
                        succ = getattr(response, "success_count", None)
                        fail = getattr(response, "failure_count", None)
                        if fail:
                            for idx, resp in enumerate(getattr(response, "responses", [])):
                                if not getattr(resp, "success", False):
                                    try:
                                        print(f"[NOTIFY] failed token: {tokens[idx]} -> {getattr(resp, 'exception', '<err>')}")
                                    except Exception:
                                        pass
                        print(f"[NOTIFY] multicast result uid={uid}: success={succ} fail={fail}")
                        return
                    except Exception as e:
                        print(f"[NOTIFY] multicast send failed: {e} -- falling back to per-token send")

                # Fallback: send per-token (with retries)
                for token in tokens:
                    sent = False
                    last_exc = None
                    for attempt in range(1, FIREBASE_RETRIES + 1):
                        try:
                            # build a simple message for single token targets
                            if hasattr(messaging, "Message"):
                                msg = messaging.Message(notification=messaging.Notification(title=title, body=body), data=data_payload, token=token)
                                res = messaging.send(msg)
                            else:
                                # As a last resort, try send function with raw args
                                res = messaging.send(messaging.Notification(title=title, body=body), token=token)
                            sent = True
                            break
                        except Exception as e:
                            last_exc = e
                            sleep_time = FIREBASE_BACKOFF * (2 ** (attempt - 1))
                            print(f"[NOTIFY] token send attempt {attempt}/{FIREBASE_RETRIES} failed for token={token}: {e}; retrying in {sleep_time}s")
                            time.sleep(sleep_time)
                    if not sent:
                        print(f"[NOTIFY] failed to send to token {token} after {FIREBASE_RETRIES} attempts: {last_exc}")
                # after per-token attempts
                return
            except Exception as e:
                print(f"[NOTIFY] firebase-admin send error (outer): {e} -- falling back to log")

        # fallback to logging (or other transports)
        print(f"[NOTIFY-LOG] uid={uid} tokens={len(rows)} title={title} body={body} payload={payload}")
    except Exception as e:
        print(f"[NOTIFY] send error for uid={uid}: {e}")


def schedule_notification_for_plan(plan: PlanORM):
    """
    Schedule a single-run APScheduler job for the given plan and persist notify_at in DB.
    Job id: plan_{plan.id}
    """
    try:
        if not APScheduler_AVAILABLE:
            # fallback to logging-only behavior
            user_zone = _get_user_zoneinfo(plan.user_id)
            try:
                local_dt = datetime.combine(plan.date, plan.start_time).replace(tzinfo=user_zone)
                notify_dt_utc = local_dt.astimezone(timezone.utc)
                print(f"[SCHEDULE-LOG] plan {plan.id} would be scheduled at utc={notify_dt_utc.isoformat()} (user_zone={user_zone})")
            except Exception:
                notify_dt_utc = datetime.combine(plan.date, plan.start_time).replace(tzinfo=timezone.utc)
                print(f"[SCHEDULE-LOG] plan {plan.id} would be scheduled (fallback) utc={notify_dt_utc.isoformat()}")
            # persist notify_at even in logging-only mode
            try:
                db = SessionLocal()
                try:
                    p = db.get(PlanORM, plan.id)
                    if p:
                        p.notify_at = notify_dt_utc
                        db.add(p)
                        db.commit()
                finally:
                    db.close()
            except Exception:
                pass
            return

        # compute notify datetime
        user_zone = _get_user_zoneinfo(plan.user_id)
        try:
            local_dt = datetime.combine(plan.date, plan.start_time).replace(tzinfo=user_zone)
            notify_dt_utc = local_dt.astimezone(timezone.utc)
        except Exception:
            notify_dt_utc = datetime.combine(plan.date, plan.start_time).replace(tzinfo=timezone.utc)

        # persist notify_at to DB so restarts can re-schedule deterministically
        try:
            db = SessionLocal()
            try:
                p = db.get(PlanORM, plan.id)
                if p:
                    p.notify_at = notify_dt_utc
                    db.add(p)
                    db.commit()
                    db.refresh(p)
            finally:
                db.close()
        except Exception as e:
            print(f"[SCHEDULE] warning: failed to persist notify_at for plan {plan.id}: {e}")

        job_id = f"plan_{plan.id}"
        # ensure scheduler exists
        if "scheduler" in globals() and globals()["scheduler"] is not None:
            try:
                globals()["scheduler"].add_job(
                    func=dispatch_notification_job,
                    trigger="date",
                    run_date=notify_dt_utc,
                    id=job_id,
                    args=[plan.id],
                    replace_existing=True,
                    misfire_grace_time=60,
                )
                print(f"[SCHEDULE] scheduled job {job_id} at {notify_dt_utc.isoformat()}")
                return
            except Exception as e:
                print(f"[SCHEDULE] failed to add job to scheduler: {e}")

        # fallback: just log
        print(f"[SCHEDULE-LOG] plan {plan.id} would be scheduled at utc={notify_dt_utc.isoformat()}")
    except Exception:
        logger.exception("Error while scheduling plan %s", getattr(plan, "id", "<unknown>"))


def cancel_scheduled_plan(plan_id: str):
    """
    Placeholder: daha gelişmiş scheduler'ı iptal etmek için kullanılır; şimdilik no-op.
    """
    try:
        job_id = f"plan_{plan_id}"
        if "scheduler" in globals() and globals()["scheduler"] is not None:
            try:
                globals()["scheduler"].remove_job(job_id)
                print(f"[CANCEL] removed job {job_id}")
                return
            except Exception:
                # job may not exist
                pass
        print(f"[CANCEL-LOG] would cancel job {job_id} (scheduler not available or job missing)")
    except Exception:
        logger.exception("Error cancelling scheduled plan %s", plan_id)


def dispatch_notification_job(plan_id: str):
    """
    Job callback executed by the scheduler. Loads the plan, checks user prefs and sends notification.
    Marks plan.notified = True on success or when notifications are disabled.
    """
    try:
        db = SessionLocal()
        try:
            plan = db.get(PlanORM, plan_id)
            if not plan:
                print(f"[DISPATCH] plan {plan_id} not found; skipping")
                return
            if plan.notified:
                print(f"[DISPATCH] plan {plan_id} already notified; skipping")
                return

            if not _user_notifications_enabled(plan.user_id):
                plan.notified = True
                db.add(plan)
                db.commit()
                print(f"[DISPATCH] notifications disabled for user {plan.user_id}; marking plan {plan_id} as notified")
                return

            payload = {
                "title": plan.title,
                "description": plan.description or "",
                "start_time": time_to_str(plan.start_time),
                "end_time": time_to_str(plan.end_time),
                "date": plan.date.isoformat(),
            }

            try:
                send_notification_to_user(plan.user_id, payload)
            except Exception as e:
                print(f"[DISPATCH] failed to send notification for plan {plan_id}: {e}")

            plan.notified = True
            db.add(plan)
            db.commit()
            print(f"[DISPATCH] finished job for plan {plan_id}")
        finally:
            db.close()
    except Exception:
        logger.exception("Unhandled error in dispatch_notification_job for plan %s", plan_id)


def _init_scheduler(start: bool = True, blocking: bool = False):
    """
    Initialize globals()['scheduler'] with a persistent SQLAlchemyJobStore.
    If APScheduler isn't installed, this becomes a no-op.
    If blocking=True, uses BlockingScheduler and .start() will block the current thread.
    """
    if not APScheduler_AVAILABLE:
        print("[SCHEDULER] APScheduler not available; scheduler disabled")
        globals()["scheduler"] = None
        return None

    if globals().get("scheduler") is not None:
        return globals()["scheduler"]

    jobstores = {"default": SQLAlchemyJobStore(url=DATABASE_URL)}
    try:
        if blocking:
            sched = BlockingScheduler(jobstores=jobstores, timezone=timezone.utc)
            globals()["scheduler"] = sched
            return sched
        else:
            sched = BackgroundScheduler(jobstores=jobstores, timezone=timezone.utc)
            globals()["scheduler"] = sched
            if start:
                try:
                    sched.start()
                    print("[SCHEDULER] background scheduler started")
                except Exception as e:
                    print(f"[SCHEDULER] failed to start scheduler: {e}")
            return sched
    except Exception as e:
        print(f"[SCHEDULER] error initializing scheduler: {e}")
        globals()["scheduler"] = None
        return None


@app.on_event("startup")
def _on_startup_init_scheduler():
    """FastAPI startup: initialize background scheduler and (best-effort) re-schedule pending plans."""
    try:
        sched = _init_scheduler(start=True, blocking=False)
        # re-schedule pending (un-notified) plans for the near future
        try:
            now_utc = datetime.now(timezone.utc)
            start_date = (now_utc - timedelta(days=1)).date()
            end_date = (now_utc + timedelta(days=7)).date()
            db = SessionLocal()
            try:
                plans = db.execute(select(PlanORM).where(
                    PlanORM.notified == False,
                    PlanORM.date.between(start_date, end_date)
                )).scalars().all()
                for p in plans:
                    try:
                        # If we have a persisted notify_at and it's in the future, prefer it;
                        # otherwise recompute from current user timezone (useful after timezone changes).
                        if getattr(p, "notify_at", None):
                            try:
                                if p.notify_at > now_utc:
                                    # schedule exactly at persisted UTC time
                                    if "scheduler" in globals() and globals()["scheduler"] is not None:
                                        job_id = f"plan_{p.id}"
                                        globals()["scheduler"].add_job(
                                            func=dispatch_notification_job,
                                            trigger="date",
                                            run_date=p.notify_at,
                                            id=job_id,
                                            args=[p.id],
                                            replace_existing=True,
                                            misfire_grace_time=60,
                                        )
                                        print(f"[SCHEDULE] scheduled job {job_id} from persisted notify_at {p.notify_at.isoformat()}")
                                        continue
                            except Exception:
                                pass
                        # otherwise compute fresh schedule (respects current DB timezone for the user)
                        schedule_notification_for_plan(p)
                    except Exception:
                        pass
            finally:
                db.close()
        except Exception:
            pass
    except Exception:
        logger.exception("Error in startup scheduler initialization")


@app.on_event("shutdown")
def _on_shutdown_stop_scheduler():
    try:
        sched = globals().get("scheduler")
        if sched is not None:
            try:
                sched.shutdown(wait=False)
                print("[SCHEDULER] scheduler shutdown")
            except Exception:
                pass
    except Exception:
        pass

# --- ADD: Timezone update endpoint ---
class TimezoneUpdate(BaseModel):
    timezone: str = Field(..., description="IANA timezone string, e.g. 'Europe/Istanbul'")
    persist: Optional[bool] = Field(False, description="If true, save as user's persistent timezone. Otherwise treated as a temporary/session timezone")
    ttl_hours: Optional[int] = Field(168, description="TTL in hours for session timezone (if persist is false). Default: 168h = 7 days")

def _parse_uid_from_token(id_token: str) -> Optional[str]:
    """
    Minimal token -> uid extractor (aynı logic get_current_user içinde kullandığımızla uyumlu).
    Development: token doğrudan uid olabilir veya JWT payload'ından sub/email çekilir.
    """
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

@app.middleware("http")
async def timezone_header_middleware(request: Request, call_next):
    """
    Eğer Authorization Bearer token ve X-User-Timezone header varsa:
    - header'daki IANA timezone'ı doğrular
    - doğrulursa USER_SUBSCRIPTIONS[uid]['timezone'] güncellenir
    - eğer DB'de kayıtlı timezone ile farklıysa DB'ye yazılır ve pending planlar yeniden schedule edilir
    Bu sayede istemci her istekinde cihaz timezone bilgisini header'a koyarsa backend otomatik kaydeder
    ve sunucu yeniden başlasa bile timezone kalıcı olur.
    """
    try:
        # header isimleri küçük/büyük farkı nedeniyle iki türlü dene
        auth_header = request.headers.get("authorization") or request.headers.get("Authorization")
        tz_header = request.headers.get("x-user-timezone") or request.headers.get("X-User-Timezone") or request.headers.get("X-Timezone")
        if auth_header and tz_header and auth_header.lower().startswith("bearer "):
            token = auth_header.split(" ", 1)[1].strip()
            uid = None
            # Prefer verified uid when firebase_admin is available
            if FIREBASE_ADMIN_AVAILABLE:
                try:
                    decoded = auth.verify_id_token(token, check_revoked=FIREBASE_CHECK_REVOKED)
                    uid = decoded.get("uid") or decoded.get("sub") or decoded.get("user_id") or decoded.get("email")
                except Exception:
                    # verification failed -> fallback to minimal parser (do not block request here)
                    uid = _parse_uid_from_token(token)
            else:
                uid = _parse_uid_from_token(token)

            # if we have a uid, validate tz_header and update in-memory store (best-effort)
            if uid:
                try:
                    # validate timezone string
                    ZoneInfo(tz_header)

                    # Update in-memory fallback first
                    info = USER_SUBSCRIPTIONS.get(uid)
                    if not info:
                        USER_SUBSCRIPTIONS[uid] = {
                            "level": "FREE",
                            "theme": "DARK",
                            "timezone": tz_header,
                            "country": None,
                            "city": None,
                            "notifications_enabled": True,
                        }
                    else:
                        info["timezone"] = tz_header
                        USER_SUBSCRIPTIONS[uid] = info

                    # Persist to DB if different from stored persistent timezone (best-effort, non-blocking)
                    try:
                        db = SessionLocal()
                        try:
                            settings = db.get(UserSettings, uid)
                            if settings:
                                stored_tz = (settings.timezone or "").strip()
                                if stored_tz != tz_header:
                                    settings.timezone = tz_header
                                    settings.updated_at = datetime.now(timezone.utc)
                                    db.add(settings)
                                    db.commit()
                                    db.refresh(settings)
                                    print(f"[TIMEZONE] middleware persisted timezone for uid={uid}: {stored_tz!r} -> {tz_header!r}")
                                    # reschedule pending plans in background thread (don't pass db across threads)
                                    try:
                                        threading.Thread(target=_reschedule_user_pending_plans_sync, args=(uid,), daemon=True).start()
                                    except Exception:
                                        pass
                            else:
                                # No DB row yet: create via get_or_create_user_settings to keep consistent logic
                                try:
                                    settings = get_or_create_user_settings(uid, db)
                                    if (settings.timezone or "").strip() != tz_header:
                                        settings.timezone = tz_header
                                        settings.updated_at = datetime.now(timezone.utc)
                                        db.add(settings)
                                        db.commit()
                                        db.refresh(settings)
                                        print(f"[TIMEZONE] middleware created settings and set timezone for uid={uid}: -> {tz_header!r}")
                                        try:
                                            threading.Thread(target=_reschedule_user_pending_plans_sync, args=(uid,), daemon=True).start()
                                        except Exception:
                                            pass
                                except Exception:
                                    # ignore creation errors (best-effort)
                                    pass
                        finally:
                            db.close()
                    except Exception:
                        # DB write failed; continue silently (middleware must not break requests)
                        pass

                except Exception:
                    # invalid timezone or other error: ignore silently
                    pass
    except Exception:
        # ensure middleware never crashes the request pipeline
        pass

    # Always proceed to the next handler and return response
    response = await call_next(request)
    return response

# --- NEW: Persistent timezone endpoint + reschedule helper ---
def _reschedule_user_pending_plans_sync(uid: str, db: Optional[Session] = None):
    """
    Synchronous helper to re-schedule (cancel + schedule) pending plans for a user.
    Intended to be run in a background thread (so it doesn't block request).
    """
    own_session = False
    try:
        if db is None:
            db = SessionLocal()
            own_session = True
        # fetch user's pending (notified==False) plans in a reasonable window
        now_utc = datetime.now(timezone.utc)
        start_date = (now_utc - timedelta(days=1)).date()
        end_date = (now_utc + timedelta(days=30)).date()  # reschedule for next 30 days
        plans = db.execute(select(PlanORM).where(
            PlanORM.user_id == uid,
            PlanORM.notified == False,
            PlanORM.date.between(start_date, end_date)
        )).scalars().all()

        # For each plan: cancel existing job (if any) then schedule anew
        for p in plans:
            try:
                cancel_scheduled_plan(p.id)
            except Exception:
                pass
            try:
                # only schedule if notify time is in the future
                user_zone = _get_user_zoneinfo(uid)
                try:
                    local_dt = datetime.combine(p.date, p.start_time).replace(tzinfo=user_zone)
                    notify_dt_utc = local_dt.astimezone(timezone.utc)
                except Exception:
                    notify_dt_utc = datetime.combine(p.date, p.start_time).replace(tzinfo=timezone.utc)
                if notify_dt_utc > now_utc:
                    schedule_notification_for_plan(p)
            except Exception:
                # continue with other plans even if one fails
                pass
    finally:
        if own_session and db is not None:
            try:
                db.close()
            except Exception:
                pass


@app.put("/user/timezone/", tags=["User"])
def update_user_timezone(
    payload: TimezoneUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Persist user's primary timezone (UserSettings.timezone) when `persist=True`.
    If the provided timezone differs from stored value, update DB and reschedule pending plans.
    If persist=False, just update in-memory/session timezone (USER_SUBSCRIPTIONS) without changing DB.
    """
    tz_str = payload.timezone
    persist = bool(payload.persist)
    ttl_hours = int(payload.ttl_hours or 168)

    # validate timezone string
    try:
        test_tz = ZoneInfo(tz_str)
    except Exception:
        raise HTTPException(status_code=400, detail="Geçersiz timezone string (IANA formatı bekleniyor).")

    uid = current_user.uid

    # If persist requested -> update DB-backed UserSettings.timezone if different
    if persist:
        try:
            settings = get_or_create_user_settings(uid, db)
        except Exception:
            raise HTTPException(status_code=500, detail="Kullanıcı ayarları yüklenemedi.")

        old_tz = (settings.timezone or "").strip()
        if old_tz != tz_str:
            settings.timezone = tz_str
            settings.updated_at = datetime.now(timezone.utc)
            db.add(settings)
            db.commit()
            db.refresh(settings)
            changed = True
            print(f"[TIMEZONE] persisted timezone for uid={uid}: {old_tz!r} -> {tz_str!r}")
            # Update in-memory fallback too
            info = USER_SUBSCRIPTIONS.get(uid) or {}
            info["timezone"] = tz_str
            USER_SUBSCRIPTIONS[uid] = info
            # Reschedule pending plans in background thread to avoid blocking request
            try:
                threading.Thread(target=_reschedule_user_pending_plans_sync, args=(uid,), daemon=True).start()
            except Exception:
                # best-effort; ignore failure to spawn thread
                pass
        else:
            changed = False
    else:
        # session-only update: store in-memory and optionally spawn reschedule for immediate effect
        info = USER_SUBSCRIPTIONS.get(uid)
        if not info:
            USER_SUBSCRIPTIONS[uid] = {
                "level": "FREE",
                "theme": "DARK",
                "timezone": tz_str,
                "country": None,
                "city": None,
                "notifications_enabled": True,
            }
        else:
            USER_SUBSCRIPTIONS[uid]["timezone"] = tz_str
        # track session expiry in memory if desired (not persisted)
        USER_SUBSCRIPTIONS[uid]["session_tz_set_at"] = datetime.now(timezone.utc).isoformat()
        USER_SUBSCRIPTIONS[uid]["session_ttl_hours"] = ttl_hours
        changed = True
        print(f"[TIMEZONE] session timezone updated for uid={uid}: {tz_str!r} (ttl_hours={ttl_hours})")

    return {"uid": uid, "timezone": tz_str, "persisted": persist, "changed": bool(changed)}