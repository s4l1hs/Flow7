import os
from datetime import datetime, date as PyDate, time as PyTime, timedelta, timezone
from typing import List, Optional
from uuid import uuid4
import base64
import json

import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Depends, Security, Request
import logging

# proper module logger (use Python logging, not fastapi.logger which lacks .exception)
logger = logging.getLogger(__name__)
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
# Firebase / firebase_admin initialization is handled in flow7_core.config

# --- Modularized config, DB and models ---
from flow7_core.config import DATABASE_URL, FIREBASE_ADMIN_AVAILABLE, FIREBASE_CHECK_REVOKED
from flow7_core.db import engine, SessionLocal, Base, get_db
from flow7_core.models import PlanORM, UserSettings, DeviceToken
from flow7_core.auth import get_current_user, token_auth_scheme
from flow7_core.state import USER_SUBSCRIPTIONS

# bring helpers from modularized modules
from flow7_core.notifications import get_time_obj_from_str, time_to_str, send_notification_to_user, _get_user_zoneinfo
from flow7_core.scheduler import schedule_notification_for_plan, cancel_scheduled_plan, init_and_reschedule, shutdown, _reschedule_user_pending_plans_sync

# Ensure DB tables exist (models imported above)
Base.metadata.create_all(bind=engine)

# Lazy import firebase messaging/auth symbols if firebase_admin is installed/configured
try:
    from firebase_admin import messaging, auth
except Exception:
    messaging = None
    auth = None


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

# Token doğrulama şeması provided by flow7_core.auth (imported above)

# get_current_user and get_db are provided by flow7_core modules (imported above)

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

# time helpers are provided by flow7_core.notifications and imported at module top

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


# _get_user_zoneinfo is implemented in flow7_core.notifications and imported at module top


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
        # Return conflict with the conflicting plan details to help the client show a helpful message
        conflict = {
            "id": existing_plan.id,
            "date": existing_plan.date.isoformat() if getattr(existing_plan, 'date', None) else None,
            "start_time": time_to_str(existing_plan.start_time),
            "end_time": time_to_str(existing_plan.end_time),
            "title": existing_plan.title,
        }
        raise HTTPException(status_code=409, detail={"message": "Belirtilen zaman aralığında mevcut bir planınız var (zaman çakışması).", "conflict": conflict})

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
    force: Optional[bool] = False,  # query param to allow forcing update by removing conflicts
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
    conflicts = db.execute(select(PlanORM).where(
        PlanORM.id != plan_id,
        PlanORM.user_id == current_user.uid,
        PlanORM.date == plan_data.date,
        PlanORM.start_time < end_time_obj,
        PlanORM.end_time > start_time_obj
    )).scalars().all()

    if conflicts:
        if force:
            # delete all conflicting plans (user asked to force the update)
            deleted = []
            try:
                for cp in conflicts:
                    deleted.append(cp.id)
                    try:
                        # cancel scheduled jobs if any
                        cancel_scheduled_plan(cp.id)
                    except Exception:
                        pass
                    db.delete(cp)
                db.commit()
                print(f"[FORCE-UPDATE] deleted conflicting plans for user {current_user.uid}: {deleted}")
            except Exception:
                db.rollback()
                raise HTTPException(status_code=500, detail="Failed to remove conflicting plans for force update")
        else:
            # return all conflicts so client can show them
            conflict_list = [
                {
                    "id": c.id,
                    "date": c.date.isoformat() if getattr(c, 'date', None) else None,
                    "start_time": time_to_str(c.start_time),
                    "end_time": time_to_str(c.end_time),
                    "title": c.title,
                }
                for c in conflicts
            ]
            raise HTTPException(status_code=409, detail={"message": "Güncellenen zaman aralığı başka bir planla çakışıyor.", "conflicts": conflict_list})

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


# send_notification_to_user is implemented in flow7_core.notifications and imported at module top


# schedule_notification_for_plan is implemented in flow7_core.scheduler and imported at module top


# Note: `cancel_scheduled_plan` is imported from `flow7_core.scheduler` at module top.
# Do NOT define a local function with the same name here — that would shadow the imported
# function and (if implemented incorrectly) can introduce recursion. Calls in this module
# (e.g. in update/delete flows) should resolve to the imported implementation.


# dispatch logic is implemented in flow7_core.scheduler as _dispatch_notification_job


@app.on_event("startup")
def _on_startup_init_scheduler():
    """App startup: initialize the modular scheduler and reschedule pending plans."""
    try:
        init_and_reschedule()
    except Exception:
        logger.exception("Error initializing scheduler on startup")


@app.on_event("shutdown")
def _on_shutdown_stop_scheduler():
    try:
        shutdown()
    except Exception:
        logger.exception("Error shutting down scheduler on stop")

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

# _reschedule_user_pending_plans_sync is implemented in flow7_core.scheduler and imported at module top


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