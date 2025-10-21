# main.py
# Flow7 Projesi için Geliştirilmiş FastAPI Arka Ucu
# Yenilikler:
# - Güvenli Token tabanlı kimlik doğrulama (JWT/Firebase uyumlu)
# - Plan güncelleme (PUT) endpoint'i
# - Daha temiz ve modüler kod yapısı
# - Gelişmiş hata yönetimi ve Pydantic modelleri

import os
from datetime import datetime, date as PyDate, time as PyTime, timedelta, timezone
from typing import List, Optional
from uuid import uuid4
import base64
import json

import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Depends, Header, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, validator
from sqlalchemy import (
    create_engine,
    Column,
    String,
    Text,
    select,
    and_,
    DateTime as SA_DateTime,
    Date as SA_Date,
    Time as SA_Time,
)
from sqlalchemy.orm import declarative_base, sessionmaker, Session

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
    user_id = Column(String, index=True, nullable=False)  # Firebase UID veya benzeri bir kimlik
    date = Column(SA_Date, index=True, nullable=False)
    start_time = Column(SA_Time, nullable=False)
    end_time = Column(SA_Time, nullable=False)
    title = Column(String, nullable=False)
    description = Column(Text, nullable=True)
    created_at = Column(SA_DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(SA_DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))


# Veritabanı ve tabloları oluştur
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
    theme_preference: str = "LIGHT"

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
        "date": plan.date.isoformat(),  # <-- string olarak döndür
        "start_time": time_to_str(plan.start_time),
        "end_time": time_to_str(plan.end_time),
        "title": plan.title,
        "description": plan.description or "",
    }


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
        start_time=start_time_obj,   # <-- time object
        end_time=end_time_obj,       # <-- time object
        title=plan_data.title,
        description=plan_data.description,
    )
    db.add(new_plan)
    db.commit()
    db.refresh(new_plan)
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

    db.commit()
    db.refresh(db_plan)
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
def user_profile(current_user: User = Depends(get_current_user)):
    """
    Basit profil endpoint'i: uid, subscriptionLevel, expires_at (varsa), theme_preference.
    """
    info = USER_SUBSCRIPTIONS.get(current_user.uid, {})
    expires = info.get("expires")
    return {
        "uid": current_user.uid,
        "subscriptionLevel": info.get("level", current_user.subscription),
        "expires_at": expires.isoformat() if expires else None,
        "theme_preference": info.get("theme", current_user.theme_preference) 
    }

class ThemePreferenceUpdate(BaseModel):
    """Kullanıcının tema tercihini güncellemek için kullanılan şema."""
    # Sadece 'LIGHT' veya 'DARK' kabul eder
    theme: str = Field(..., pattern=r"^(LIGHT|DARK)$", description="LIGHT veya DARK olmalı")

@app.put("/user/theme/", tags=["User"])
def update_user_theme(
    payload: ThemePreferenceUpdate,
    current_user: User = Depends(get_current_user),
):
    """
    Kullanıcının tema (dark/light mode) tercihini günceller.
    """
    uid = current_user.uid
    
    # In-memory sözlüğü güncelleyelim.
    # Eğer kullanıcı daha önce abonelik bilgisi kaydetmediyse varsayılanları atarız.
    user_info = USER_SUBSCRIPTIONS.get(uid, {"level": current_user.subscription, "theme": current_user.theme_preference})
    
    # Tema bilgisini güncelleyin
    user_info["theme"] = payload.theme
    USER_SUBSCRIPTIONS[uid] = user_info
    
    return {"uid": uid, "theme_preference": payload.theme}
# --- 7. RUN THE APP ---
# Bu blok, dosyanın doğrudan `python main.py` ile çalıştırılmasını sağlar.
if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)