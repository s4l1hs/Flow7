from datetime import datetime, date as Date, time as Time, timedelta, timezone
from typing import List, Optional
from uuid import uuid4
import os
from pathlib import Path
from dotenv import load_dotenv

from fastapi import FastAPI, HTTPException, Depends, Header
from pydantic import BaseModel, Field, validator
from sqlalchemy import (
    Column,
    String,
    Date,
    Time,
    Text,
    create_engine,
    select,
    and_,
    func,
)
from sqlalchemy.orm import declarative_base, sessionmaker, Session

# ----------------------------------------------------------------------
# KyroTech Flow7 Backend (FastAPI)
# Geliştirilmiş: SQLite (SQLAlchemy), auth header, zaman doğrulama,
# çakışma kontrolü, okuma/yazma abonelik limitleri, thread-safe DB.
# ----------------------------------------------------------------------

# --- CONFIG / DB SETUP ---
# load .env from project folder (falls back to defaults if missing)
env_path = Path(__file__).resolve().parent / ".env"
if env_path.exists():
    load_dotenv(env_path)
else:
    load_dotenv()  # will still read from environment if provided

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./flow7.db")

engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
Base = declarative_base()


# --- ORM MODEL ---
class PlanORM(Base):
    __tablename__ = "plans"
    id = Column(String, primary_key=True, index=True)
    user_id = Column(String, index=True, nullable=False)
    date = Column(Date, index=True, nullable=False)
    start_time = Column(Time, nullable=False)
    end_time = Column(Time, nullable=False)
    title = Column(String, nullable=False)
    description = Column(Text, nullable=True)
    created_at = Column(Date, nullable=False)
    updated_at = Column(Date, nullable=False)


Base.metadata.create_all(bind=engine)


# --- Pydantic Schemas ---
TIME_PATTERN = r"^\d{2}:\d{2}$"


class PlanBase(BaseModel):
    date: Date
    start_time: str = Field(..., pattern=TIME_PATTERN)
    end_time: str = Field(..., pattern=TIME_PATTERN)
    title: str = Field(..., min_length=1)
    description: Optional[str] = None

    @validator("start_time", "end_time")
    def validate_time_format(cls, v):
        try:
            hh, mm = v.split(":")
            hh_i = int(hh)
            mm_i = int(mm)
        except Exception:
            raise ValueError("Zaman HH:MM formatında olmalıdır.")
        if not (0 <= hh_i < 24 and 0 <= mm_i < 60):
            raise ValueError("Geçersiz saat/dakika.")
        return v

    @validator("end_time")
    def end_after_start(cls, v, values):
        st = values.get("start_time")
        if st:
            sh, sm = map(int, st.split(":"))
            eh, em = map(int, v.split(":"))
            if (eh, em) <= (sh, sm):
                raise ValueError("end_time, start_time'dan sonra olmalıdır.")
        return v


class PlanCreate(PlanBase):
    pass


class PlanUpdate(PlanBase):
    pass


class PlanOut(PlanBase):
    id: str
    user_id: str


# --- MOCK SUBSCRIPTIONS (should be in DB/service in prod) ---
MOCK_SUBSCRIPTIONS = {
    "user_free_123": "FREE",
    "user_pro_456": "PRO",
    "user_ultra_789": "ULTRA",
    "user_default": "FREE",
}

SUBSCRIPTION_LIMITS = {"FREE": 14, "PRO": 30, "ULTRA": 60}


# --- UTILITIES ---
def utc_today() -> Date:
    return datetime.now(timezone.utc).date()


def parse_time_str(t: str) -> Time:
    hh, mm = map(int, t.split(":"))
    return Time(hour=hh, minute=mm)


def get_user_subscription(user_id: str) -> str:
    return MOCK_SUBSCRIPTIONS.get(user_id, "FREE")


def get_planning_limit(subscription_level: str) -> Date:
    days = SUBSCRIPTION_LIMITS.get(subscription_level, 14)
    return utc_today() + timedelta(days=days)


def check_planning_limit(user_id: str, target_date: Date):
    sub_level = get_user_subscription(user_id)
    limit_date = get_planning_limit(sub_level)
    if target_date > limit_date:
        raise HTTPException(
            status_code=403,
            detail=f"Erişim Reddedildi. {sub_level} planı ile maksimum planlama tarihi: {limit_date.isoformat()}",
        )


# --- DEPENDENCIES ---
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def get_current_user_id(x_user_id: Optional[str] = Header(None)) -> str:
    """
    Basit auth: X-User-Id header okunur. Prod: JWT/OpenID entegrasyonu kullanılmalı.
    """
    return x_user_id or "user_default"


# --- APP ---
app = FastAPI(
    title="KyroTech Flow7 API",
    description="Haftalık Akış (Flow7) planlama uygulamasının API servisi.",
    version="1.1.0",
)


@app.get("/api/status")
def get_status():
    return {"status": "ok", "app": "Flow7 Backend", "utc_today": utc_today().isoformat()}


# --- CRUD UÇ NOKTALARI ---

@app.post("/api/plans", response_model=PlanOut)
def create_plan(
    plan_data: PlanCreate,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """Yeni plan oluştur. Çakışma ve abonelik limitleri kontrol edilir."""
    # limit kontrolü
    check_planning_limit(user_id, plan_data.date)

    # zaman nesneleri
    st = parse_time_str(plan_data.start_time)
    et = parse_time_str(plan_data.end_time)

    # çakışma kontrolü: aynı kullanıcı aynı tarihte, zaman aralıkları kesişiyor mu?
    overlap_q = (
        select(PlanORM)
        .where(
            PlanORM.user_id == user_id,
            PlanORM.date == plan_data.date,
            and_(
                PlanORM.start_time < et,
                PlanORM.end_time > st,
            ),
        )
        .limit(1)
    )
    res = db.execute(overlap_q).scalars().first()
    if res:
        raise HTTPException(status_code=409, detail="Zaman çakışması: başka bir plan ile çakışıyor.")

    now_date = utc_today()
    new_id = str(uuid4())
    orm = PlanORM(
        id=new_id,
        user_id=user_id,
        date=plan_data.date,
        start_time=st,
        end_time=et,
        title=plan_data.title,
        description=plan_data.description,
        created_at=now_date,
        updated_at=now_date,
    )
    db.add(orm)
    db.commit()
    db.refresh(orm)
    return PlanOut(
        id=orm.id,
        user_id=orm.user_id,
        date=orm.date,
        start_time=plan_data.start_time,
        end_time=plan_data.end_time,
        title=orm.title,
        description=orm.description,
    )


@app.get("/api/plans", response_model=List[PlanOut])
def get_plans_by_range(
    start_date: Date,
    end_date: Date,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Belirli bir tarih aralığındaki planları getirir.
    Okuma için abonelik limiti kontrolü uygulanır (gelecek tarihleri sınırla).
    """
    limit_date = get_planning_limit(get_user_subscription(user_id))
    # Eğer istemci geleceğe doğru veri istiyorsa limit'i aşamaz
    if end_date > limit_date and end_date > utc_today():
        raise HTTPException(
            status_code=403,
            detail=f"Okuma Aralığı Reddedildi. {get_user_subscription(user_id)} planı, {limit_date.isoformat()} tarihini aşan veriye erişemez.",
        )

    q = (
        select(PlanORM)
        .where(
            PlanORM.user_id == user_id,
            PlanORM.date >= start_date,
            PlanORM.date <= end_date,
        )
        .order_by(PlanORM.date, PlanORM.start_time)
    )
    results = db.execute(q).scalars().all()

    out = []
    for r in results:
        out.append(
            PlanOut(
                id=r.id,
                user_id=r.user_id,
                date=r.date,
                start_time=r.start_time.strftime("%H:%M"),
                end_time=r.end_time.strftime("%H:%M"),
                title=r.title,
                description=r.description,
            )
        )
    return out


@app.get("/api/plans/{plan_id}", response_model=PlanOut)
def get_plan(plan_id: str, user_id: str = Depends(get_current_user_id), db: Session = Depends(get_db)):
    p = db.get(PlanORM, plan_id)
    if not p or p.user_id != user_id:
        raise HTTPException(status_code=404, detail="Plan bulunamadı.")
    return PlanOut(
        id=p.id,
        user_id=p.user_id,
        date=p.date,
        start_time=p.start_time.strftime("%H:%M"),
        end_time=p.end_time.strftime("%H:%M"),
        title=p.title,
        description=p.description,
    )


@app.put("/api/plans/{plan_id}", response_model=PlanOut)
def update_plan(
    plan_id: str,
    plan_data: PlanUpdate,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """Plan güncelle. Limit ve çakışma kontrolü yapılır."""
    p: Optional[PlanORM] = db.get(PlanORM, plan_id)
    if not p or p.user_id != user_id:
        raise HTTPException(status_code=404, detail="Plan bulunamadı.")

    # limit kontrolü
    check_planning_limit(user_id, plan_data.date)

    st = parse_time_str(plan_data.start_time)
    et = parse_time_str(plan_data.end_time)

    # çakışma kontrolü (kendi kaydı hariç)
    overlap_q = (
        select(PlanORM)
        .where(
            PlanORM.user_id == user_id,
            PlanORM.date == plan_data.date,
            PlanORM.id != plan_id,
            and_(
                PlanORM.start_time < et,
                PlanORM.end_time > st,
            ),
        )
        .limit(1)
    )
    res = db.execute(overlap_q).scalars().first()
    if res:
        raise HTTPException(status_code=409, detail="Zaman çakışması: başka bir plan ile çakışıyor.")

    p.date = plan_data.date
    p.start_time = st
    p.end_time = et
    p.title = plan_data.title
    p.description = plan_data.description
    p.updated_at = utc_today()
    db.add(p)
    db.commit()
    db.refresh(p)

    return PlanOut(
        id=p.id,
        user_id=p.user_id,
        date=p.date,
        start_time=p.start_time.strftime("%H:%M"),
        end_time=p.end_time.strftime("%H:%M"),
        title=p.title,
        description=p.description,
    )


@app.delete("/api/plans/{plan_id}", status_code=204)
def delete_plan(plan_id: str, user_id: str = Depends(get_current_user_id), db: Session = Depends(get_db)):
    p: Optional[PlanORM] = db.get(PlanORM, plan_id)
    if not p or p.user_id != user_id:
        raise HTTPException(status_code=404, detail="Plan bulunamadı.")
    db.delete(p)
    db.commit()
    return