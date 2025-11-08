from datetime import datetime, date as PyDate, time as PyTime, timezone
from zoneinfo import ZoneInfo
from typing import Optional
import os
import time as time_module
from flow7_core.db import SessionLocal
from flow7_core.models import UserSettings, DeviceToken
from sqlalchemy import select
from flow7_core.state import USER_SUBSCRIPTIONS
from flow7_core.config import FIREBASE_ADMIN_AVAILABLE

# lazy import firebase messaging if available
try:
    from firebase_admin import messaging
except Exception:
    messaging = None


TIME_FORMAT = "%H:%M"


def get_time_obj_from_str(time_str: str) -> PyTime:
    return PyTime.fromisoformat(time_str)


def time_to_str(t: Optional[PyTime]) -> Optional[str]:
    if t is None:
        return None
    return t.strftime(TIME_FORMAT)


def _get_user_zoneinfo(uid: str) -> ZoneInfo:
    """Resolve user's effective ZoneInfo: DB -> in-memory fallback -> default"""
    try:
        db = SessionLocal()
        try:
            s = db.get(UserSettings, uid)
            if s and s.timezone:
                try:
                    return ZoneInfo(s.timezone)
                except Exception:
                    pass
        finally:
            db.close()
    except Exception:
        pass
    info = USER_SUBSCRIPTIONS.get(uid, {})
    tz_str = info.get("timezone", "Europe/Istanbul")
    try:
        return ZoneInfo(tz_str)
    except Exception:
        return ZoneInfo("Europe/Istanbul")


def send_notification_to_user(uid: str, payload: dict):
    """Format notification body and send via firebase-admin when available; otherwise log."""
    try:
        db = SessionLocal()
        try:
            rows = db.execute(select(DeviceToken.token).where(DeviceToken.uid == uid)).scalars().all()
        finally:
            db.close()

        if not rows:
            print(f"[NOTIFY] no device tokens for uid={uid}, payload={payload}")
            return

        try:
            tz = _get_user_zoneinfo(uid)
        except Exception:
            tz = ZoneInfo("UTC")

        title = payload.get("title", "Flow7")
        description = payload.get("description", "") or ""

        start_display = payload.get("start_time", "")
        end_display = payload.get("end_time", "")
        try:
            date_str = payload.get("date")
            if date_str and start_display:
                d = PyDate.fromisoformat(date_str)
                st = PyTime.fromisoformat(start_display)
                local_dt = datetime.combine(d, st).replace(tzinfo=tz)
                start_display = local_dt.strftime(TIME_FORMAT)
            if date_str and end_display:
                et = PyTime.fromisoformat(end_display)
                end_local = datetime.combine(PyDate.fromisoformat(date_str), et).replace(tzinfo=tz)
                end_display = end_local.strftime(TIME_FORMAT)
        except Exception:
            pass

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

        FIREBASE_RETRIES = int(os.getenv("FIREBASE_SEND_RETRIES", "3"))
        FIREBASE_BACKOFF = float(os.getenv("FIREBASE_SEND_BACKOFF", "0.5"))

        if FIREBASE_ADMIN_AVAILABLE and messaging is not None:
            try:
                tokens = list(rows)
                data_payload = {"type": "plan_notification", "date": payload.get("date", ""), "start_time": payload.get("start_time", ""), "end_time": payload.get("end_time", "")}

                if hasattr(messaging, "send_multicast") and hasattr(messaging, "MulticastMessage"):
                    try:
                        message = messaging.MulticastMessage(
                            notification=messaging.Notification(title=title, body=body),
                            data=data_payload,
                            tokens=tokens,
                        )
                        response = messaging.send_multicast(message)
                        succ = getattr(response, "success_count", None)
                        fail = getattr(response, "failure_count", None)
                        print(f"[NOTIFY] multicast result uid={uid}: success={succ} fail={fail}")
                        return
                    except Exception as e:
                        print(f"[NOTIFY] multicast send failed: {e} -- falling back to per-token send")

                for token in tokens:
                    sent = False
                    last_exc = None
                    for attempt in range(1, FIREBASE_RETRIES + 1):
                        try:
                            if hasattr(messaging, "Message"):
                                msg = messaging.Message(notification=messaging.Notification(title=title, body=body), data=data_payload, token=token)
                                res = messaging.send(msg)
                            else:
                                res = messaging.send(messaging.Notification(title=title, body=body), token=token)
                            sent = True
                            break
                        except Exception as e:
                            last_exc = e
                            sleep_time = FIREBASE_BACKOFF * (2 ** (attempt - 1))
                            print(f"[NOTIFY] token send attempt {attempt}/{FIREBASE_RETRIES} failed for token={token}: {e}; retrying in {sleep_time}s")
                            time_module.sleep(sleep_time)
                    if not sent:
                        print(f"[NOTIFY] failed to send to token {token} after {FIREBASE_RETRIES} attempts: {last_exc}")
                return
            except Exception as e:
                print(f"[NOTIFY] firebase-admin send error (outer): {e} -- falling back to log")

        print(f"[NOTIFY-LOG] uid={uid} tokens={len(rows)} title={title} body={body} payload={payload}")
    except Exception as e:
        print(f"[NOTIFY] send error for uid={uid}: {e}")
