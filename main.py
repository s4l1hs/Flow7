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
)
import asyncio
from sqlalchemy.orm import declarative_base, sessionmaker, Session
from zoneinfo import ZoneInfo
import time
import threading
# Optional firebase-admin for sending FCM push messages from server
FIREBASE_ADMIN_AVAILABLE = False
try:
    import firebase_admin
    from firebase_admin import credentials, messaging
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


# --- NEW: persistent user settings ORM ---
class UserSettings(Base):
    __tablename__ = "user_settings"
    uid = Column(String, primary_key=True, index=True)
    language_code = Column(String(8), nullable=True)
    theme = Column(String(16), nullable=True)
    notifications_enabled = Column(Boolean, default=True, nullable=False)
    timezone = Column(String(64), nullable=True)
    # session_timezone: temporary timezone (e.g. while traveling). If set, it takes precedence
    # for a limited TTL stored in session_tz_expires_at.
    session_timezone = Column(String(64), nullable=True)
    session_tz_expires_at = Column(SA_DateTime(timezone=True), nullable=True)
    country = Column(String(64), nullable=True)
    city = Column(String(64), nullable=True)
    username = Column(String(128), nullable=True)
    last_seen_at = Column(SA_DateTime(timezone=True), nullable=True)
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

async def get_current_user(token: HTTPAuthorizationCredentials = Security(token_auth_scheme)) -> User:
    """
    Authorization başlığından gelen Bearer token'ı doğrular ve kullanıcıyı döndürür.
    Development: token ya doğrudan uid olabilir ya da Firebase idToken (JWT) olabilir.
    Eğer JWT gelirse payload'tan 'sub' / 'user_id' / 'uid' / 'email' alanlarını alarak uid elde etmeye çalışır.
    GERÇEK PROJEDE: Token'ı burada Firebase Admin SDK veya başka bir JWT kütüphanesi ile doğrulayın.
    """
    id_token = token.credentials
    if not id_token:
        raise HTTPException(status_code=401, detail="Kimlik doğrulama token'ı sağlanmadı.")
    try:
        uid = id_token  # default: token itself as uid (dev mode)

        # Eğer token JWT formatındaysa (header.payload.signature), payload'tan sub/user_id çıkarmaya çalış
        if isinstance(id_token, str) and '.' in id_token:
            try:
                parts = id_token.split('.')
                if len(parts) >= 2:
                    payload_b64 = parts[1]
                    # base64url padding
                    rem = len(payload_b64) % 4
                    if rem:
                        payload_b64 += '=' * (4 - rem)
                    payload_json = base64.urlsafe_b64decode(payload_b64.encode('utf-8')).decode('utf-8')
                    payload = json.loads(payload_json)
                    # common claim names
                    uid = payload.get('sub') or payload.get('user_id') or payload.get('uid') or payload.get('email') or uid
            except Exception:
                # parsing başarısızsa fallback olarak token'ı uid kabul et
                uid = id_token

        # Kullanıcının in-memory abonelik bilgisi varsa al
        sub_info = USER_SUBSCRIPTIONS.get(uid)
        subscription = sub_info["level"] if sub_info and "level" in sub_info else "FREE"
        theme_preference = sub_info["theme"] if sub_info and "theme" in sub_info else "LIGHT"

        # Ensure a default in-memory entry so user's timezone/city/country exist until user changes them.
        # Default: Turkey / Istanbul -> IANA "Europe/Istanbul"
        if uid not in USER_SUBSCRIPTIONS:
            USER_SUBSCRIPTIONS[uid] = {
                "level": subscription,
                "theme": theme_preference,
                "timezone": "Europe/Istanbul",
                
                "country": "Turkey",
                "city": "Istanbul",
                "notifications_enabled": True,
            }

        return User(uid=uid, subscription=subscription, theme_preference=theme_preference)
    except Exception as e:
        raise HTTPException(
            status_code=401,
            detail=f"Geçersiz kimlik doğrulama token'ı: {e}",
            headers={"WWW-Authenticate": "Bearer"},
        )


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
                # check session override
                if s.session_timezone and s.session_tz_expires_at:
                    if s.session_tz_expires_at.tzinfo is None:
                        # assume UTC stored
                        expires = s.session_tz_expires_at.replace(tzinfo=timezone.utc)
                    else:
                        expires = s.session_tz_expires_at
                    if datetime.now(timezone.utc) <= expires:
                        try:
                            return ZoneInfo(s.session_timezone)
                        except Exception:
                            pass
                # fallback to persistent timezone
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
    current_user: User = Depends(get_current_user),
):
    """
    Kullanıcının abonelik seviyesini günceller (development: in-memory).
    Body: { "level": "pro", "days": 30 }
    Döner: { "uid": "...", "level": "...", "expires_at": "YYYY-MM-DD" }
    """
    expires = datetime.now(timezone.utc).date() + timedelta(days=payload.days)
    USER_SUBSCRIPTIONS[current_user.uid] = {"level": payload.level, "expires": expires}
    return {"uid": current_user.uid, "level": payload.level, "expires_at": expires.isoformat()}


@app.get("/user/profile/", tags=["User"])
def user_profile(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """
    Basit profil endpoint'i: uid, subscriptionLevel, expires_at (varsa), theme_preference,
    language_code ve notifications_enabled.
    """
    uid = current_user.uid
    settings = get_or_create_user_settings(uid, db)
    expires = USER_SUBSCRIPTIONS.get(uid, {}).get("expires")
    return {
        "uid": uid,
        "subscriptionLevel": USER_SUBSCRIPTIONS.get(uid, {}).get("level", current_user.subscription),
        "expires_at": expires.isoformat() if expires else None,
        "theme_preference": settings.theme or current_user.theme_preference,
        "language_code": settings.language_code or "en",
        "notifications_enabled": bool(settings.notifications_enabled),
        "username": settings.username,
        "score": USER_SUBSCRIPTIONS.get(uid, {}).get("score", 0),
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

    # create a new settings row using in-memory defaults if present
    info = USER_SUBSCRIPTIONS.get(uid, {})
    settings = UserSettings(
        uid=uid,
        language_code=info.get("language_code"),
        theme=info.get("theme"),
        notifications_enabled=info.get("notifications_enabled", True),
        timezone=info.get("timezone"),
        country=info.get("country"),
        city=info.get("city"),
        username=info.get("username"),
        last_seen_at=datetime.now(timezone.utc),
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
        if FIREBASE_ADMIN_AVAILABLE:
            try:
                message = messaging.MulticastMessage(
                    notification=messaging.Notification(title=title, body=body),
                    data={"type": "plan_notification", "date": payload.get("date",""), "start_time": payload.get("start_time",""), "end_time": payload.get("end_time","")},
                    tokens=list(rows),
                )
                response = messaging.send_multicast(message)
                if response.failure_count > 0:
                    for idx, resp in enumerate(response.responses):
                        if not resp.success:
                            print(f"[NOTIFY] failed token: {rows[idx]} -> {resp.exception}")
                print(f"[NOTIFY] sent to uid={uid}: success={response.success_count}, fail={response.failure_count}")
                return
            except Exception as e:
                print(f"[NOTIFY] firebase-admin send error: {e} -- falling back to log")

        # fallback to logging (or other transports)
        print(f"[NOTIFY-LOG] uid={uid} tokens={len(rows)} title={title} body={body} payload={payload}")
    except Exception as e:
        print(f"[NOTIFY] send error for uid={uid}: {e}")


def schedule_notification_for_plan(plan: PlanORM):
    """
    Placeholder: plan için zamanlanmış bildirim oluşturur.
    Mevcut uygulamada arka plan worker DB'yi periyodik tarayıp notified==False olanları işlediği
    için burada no-op yapmak yeterlidir; daha gelişmiş bir sistemde burası gerçek scheduler entegrasyonu olur.
    """
    try:
        # compute notify datetime using user's timezone (correct for DST / region)
        user_zone = _get_user_zoneinfo(plan.user_id)
        try:
            local_dt = datetime.combine(plan.date, plan.start_time).replace(tzinfo=user_zone)
            notify_dt_utc = local_dt.astimezone(timezone.utc)
            print(f"[SCHEDULE] plan {plan.id} scheduled at utc={notify_dt_utc.isoformat()} (user_zone={user_zone})")
        except Exception:
            # fallback: log naive schedule in UTC
            notify_dt = datetime.combine(plan.date, plan.start_time).replace(tzinfo=timezone.utc)
            print(f"[SCHEDULE] plan {plan.id} scheduled (fallback) utc={notify_dt.isoformat()}")
    except Exception:
        pass


def cancel_scheduled_plan(plan_id: str):
    """
    Placeholder: daha gelişmiş scheduler'ı iptal etmek için kullanılır; şimdilik no-op.
    """
    try:
        print(f"[CANCEL] cancel schedule for plan {plan_id} (no-op)")
    except Exception:
        pass


async def _notification_worker_loop(poll_interval_seconds: int = 30):
    """Arka plan döngüsü: belirli aralıklarla DB'den bildirim bekleyen planları kontrol eder."""
    while True:
        try:
            now_utc = datetime.now(timezone.utc)
            # limit query window to yesterday..tomorrow to cover TZ shifts and late inserts
            start_date = (now_utc - timedelta(days=1)).date()
            end_date = (now_utc + timedelta(days=1)).date()
            db = SessionLocal()
            try:
                q = select(PlanORM).where(
                    PlanORM.date.between(start_date, end_date),
                    PlanORM.notified == False
                )
                candidates = db.execute(q).scalars().all()
                for plan in candidates:
                    user_zone = _get_user_zoneinfo(plan.user_id)
                    try:
                        plan_local_dt = datetime.combine(plan.date, plan.start_time).replace(tzinfo=user_zone)
                    except Exception:
                        continue
                    plan_start_utc = plan_local_dt.astimezone(timezone.utc)
                    plan_end_utc = None
                    if plan.end_time:
                        plan_end_local = datetime.combine(plan.date, plan.end_time).replace(tzinfo=user_zone)
                        plan_end_utc = plan_end_local.astimezone(timezone.utc)

                    # notify only if start <= now (allow small tolerance) and not already notified
                    if plan_start_utc <= now_utc and (plan_end_utc is None or now_utc <= plan_end_utc):
                        if not _user_notifications_enabled(plan.user_id):
                            plan.notified = True
                            db.add(plan)
                            continue
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
                            print(f"Failed to send notification for plan {plan.id}: {e}")
                        plan.notified = True
                        db.add(plan)
                db.commit()
            finally:
                db.close()
        except Exception as e:
            print("Notification worker error:", e)
        await asyncio.sleep(poll_interval_seconds)
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
    Bu sayede istemci her istekinde cihaz timezone bilgisini header'a koyarsa backend otomatik kaydeder.
    """
    try:
        # header isimleri küçük/büyük farkı nedeniyle iki türlü dene
        auth = request.headers.get("authorization") or request.headers.get("Authorization")
        tz_header = request.headers.get("x-user-timezone") or request.headers.get("X-User-Timezone") or request.headers.get("X-Timezone")
        if auth and tz_header and auth.lower().startswith("bearer "):
            token = auth.split(" ", 1)[1].strip()
            uid = _parse_uid_from_token(token)
            if uid:
                # validate timezone string
                try:
                    _ = ZoneInfo(tz_header)
                    # persist as session timezone with default TTL (7 days)
                    try:
                        db = SessionLocal()
                        try:
                            settings = get_or_create_user_settings(uid, db)
                            settings.session_timezone = tz_header
                            settings.session_tz_expires_at = datetime.now(timezone.utc) + timedelta(hours=168)
                            settings.last_seen_at = datetime.now(timezone.utc)
                            db.add(settings)
                            db.commit()
                        finally:
                            db.close()
                    except Exception:
                        # fallback to in-memory update if DB write fails
                        info = USER_SUBSCRIPTIONS.get(uid, {"level": "FREE", "theme": "LIGHT"})
                        info["timezone"] = tz_header
                        USER_SUBSCRIPTIONS[uid] = info
                    # kick off background reschedule of pending plans for this user
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
def update_user_timezone(payload: TimezoneUpdate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """
    Kullanıcının cihazdan elde edilen IANA timezone'ını backend'e kaydet.
    Body: { "timezone": "Europe/Istanbul", "persist": false, "ttl_hours": 168 }
    If persist=true -> save as persistent timezone. Otherwise save as session timezone with TTL.
    """
    try:
        # validate by constructing ZoneInfo
        _ = ZoneInfo(payload.timezone)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid IANA timezone identifier.")

    uid = current_user.uid
    settings = get_or_create_user_settings(uid, db)
    now = datetime.now(timezone.utc)
    if payload.persist:
        settings.timezone = payload.timezone
        settings.updated_at = now
    else:
        ttl = int(payload.ttl_hours or 168)
        settings.session_timezone = payload.timezone
        settings.session_tz_expires_at = now + timedelta(hours=ttl)
        settings.last_seen_at = now
    db.add(settings)
    db.commit()
    db.refresh(settings)
    # asynchronously reschedule pending plans for this user (best-effort)
    try:
        threading.Thread(target=_reschedule_user_pending_plans_sync, args=(uid,), daemon=True).start()
    except Exception:
        pass
    return {"uid": uid, "timezone": payload.timezone, "persist": bool(payload.persist)}


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
        print(f"[USER_TIME] uid={uid} timezone={tz_str} local_time={now_local.isoformat()}")
        return {"uid": uid, "timezone": tz_str, "local_time": now_local.isoformat()}
    except Exception:
        print(f"[USER_TIME] uid={uid} timezone={tz_str} could not convert, returning UTC {now_utc.isoformat()}")
        return {"uid": uid, "timezone": tz_str, "local_time": now_utc.isoformat()}

# --- 7. RUN THE APP ---
# Bu blok, dosyanın doğrudan `python main.py` ile çalıştırılmasını sağlar.
if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)