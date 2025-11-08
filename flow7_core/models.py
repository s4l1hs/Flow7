from datetime import datetime
from sqlalchemy import Column, Integer, String, Date, Time, Boolean, DateTime, Text
from sqlalchemy.dialects.sqlite import DATETIME
from .db import Base


class PlanORM(Base):
    __tablename__ = "plans"
    id = Column(String, primary_key=True)
    user_id = Column(String, index=True, nullable=False)
    date = Column(Date, nullable=False)
    start_time = Column(Time, nullable=False)
    end_time = Column(Time, nullable=True)
    title = Column(String, nullable=False)
    description = Column(Text, nullable=True)
    notified = Column(Boolean, default=False, nullable=False)
    notify_at = Column(DateTime, nullable=True)  # UTC
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class UserSettings(Base):
    __tablename__ = "user_settings"
    uid = Column(String, primary_key=True)
    language_code = Column(String, default="tr")
    theme = Column(String, default="system")
    notifications_enabled = Column(Boolean, default=True)
    timezone = Column(String, default="UTC")
    country = Column(String, nullable=True)
    city = Column(String, nullable=True)
    username = Column(String, nullable=True)
    # Subscription persistence
    subscription_level = Column(String, default="FREE")
    subscription_expires_at = Column(DateTime, nullable=True)
    subscription_score = Column(Integer, default=0)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class DeviceToken(Base):
    __tablename__ = "device_tokens"
    id = Column(String, primary_key=True)
    uid = Column(String, index=True, nullable=False)
    token = Column(String, nullable=False, unique=True)
    platform = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
