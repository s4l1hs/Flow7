from datetime import datetime, timedelta, timezone
import threading
import os
from typing import Optional

from flow7_core.db import SessionLocal
from flow7_core.models import PlanORM
from sqlalchemy import select
from sqlalchemy.orm import Session
from flow7_core.config import DATABASE_URL
from flow7_core.notifications import send_notification_to_user, _get_user_zoneinfo

# APScheduler imports
APScheduler_AVAILABLE = False
try:
    from apscheduler.schedulers.background import BackgroundScheduler
    from apscheduler.schedulers.blocking import BlockingScheduler
    from apscheduler.jobstores.sqlalchemy import SQLAlchemyJobStore
    APScheduler_AVAILABLE = True
except Exception:
    APScheduler_AVAILABLE = False

# internal scheduler handle
_scheduler = None

GRACE_WINDOW = timedelta(hours=24)  # how old a missed job can be to still run immediately


def _dispatch_notification_job(plan_id: str):
    # wrapper to be used by APScheduler; mirrors previous dispatch_notification_job
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

            # notifications enabled check
            try:
                s = db.get(plan.__class__.__module__ and None, plan.user_id)
            except Exception:
                s = None
            # Use best-effort: rely on send_notification_to_user to honor user prefs if needed

            payload = {
                "title": plan.title,
                "description": plan.description or "",
                "start_time": plan.start_time.strftime("%H:%M") if plan.start_time else "",
                "end_time": plan.end_time.strftime("%H:%M") if plan.end_time else "",
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
        import traceback
        traceback.print_exc()


def schedule_notification_for_plan(plan: PlanORM):
    """Schedule a single-run job and persist plan.notify_at (UTC)."""
    try:
        if not APScheduler_AVAILABLE:
            # compute and persist
            user_zone = _get_user_zoneinfo(plan.user_id)
            try:
                local_dt = datetime.combine(plan.date, plan.start_time).replace(tzinfo=user_zone)
                notify_dt_utc = local_dt.astimezone(timezone.utc)
            except Exception:
                notify_dt_utc = datetime.combine(plan.date, plan.start_time).replace(tzinfo=timezone.utc)
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
            print(f"[SCHEDULE-LOG] plan {plan.id} would be scheduled at utc={notify_dt_utc.isoformat()} (APScheduler not available)")
            return

        user_zone = _get_user_zoneinfo(plan.user_id)
        try:
            local_dt = datetime.combine(plan.date, plan.start_time).replace(tzinfo=user_zone)
            notify_dt_utc = local_dt.astimezone(timezone.utc)
        except Exception:
            notify_dt_utc = datetime.combine(plan.date, plan.start_time).replace(tzinfo=timezone.utc)

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
        global _scheduler
        if _scheduler is not None:
            try:
                _scheduler.add_job(
                    func=_dispatch_notification_job,
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

        print(f"[SCHEDULE-LOG] plan {plan.id} would be scheduled at utc={notify_dt_utc.isoformat()}")
    except Exception:
        import traceback
        traceback.print_exc()


def cancel_scheduled_plan(plan_id: str):
    job_id = f"plan_{plan_id}"
    global _scheduler
    if _scheduler is not None:
        try:
            _scheduler.remove_job(job_id)
            print(f"[CANCEL] removed job {job_id}")
            return
        except Exception:
            pass
    print(f"[CANCEL-LOG] would cancel job {job_id} (scheduler not available or job missing)")


def init_and_reschedule():
    """Initialize scheduler and reschedule pending plans. To be called from app startup."""
    global _scheduler
    if not APScheduler_AVAILABLE:
        print("[SCHEDULER] APScheduler not available; scheduler disabled")
        _scheduler = None
        return None

    if _scheduler is not None:
        return _scheduler

    jobstores = {"default": SQLAlchemyJobStore(url=DATABASE_URL)}
    sched = BackgroundScheduler(jobstores=jobstores, timezone=timezone.utc)
    _scheduler = sched
    try:
        sched.start()
        print("[SCHEDULER] background scheduler started")
    except Exception as e:
        print(f"[SCHEDULER] failed to start scheduler: {e}")

    def _ensure_aware_utc(dt):
        """Return a timezone-aware datetime in UTC. If dt is naive, assume UTC and attach tzinfo.
        If dt already has tzinfo, convert to UTC.
        """
        if dt is None:
            return None
        if dt.tzinfo is None:
            try:
                return dt.replace(tzinfo=timezone.utc)
            except Exception:
                return datetime.fromtimestamp(dt.timestamp(), tz=timezone.utc)
        return dt.astimezone(timezone.utc)

    # reschedule pending plans
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
                    na = getattr(p, "notify_at", None)
                    if na is not None:
                        na_utc = _ensure_aware_utc(na)
                        # persist normalized notify_at if it was naive
                        if na.tzinfo is None:
                            try:
                                p.notify_at = na_utc
                                db.add(p)
                                db.commit()
                            except Exception:
                                db.rollback()

                        # if notify_at is in the future, schedule directly
                        try:
                            if na_utc > now_utc:
                                job_id = f"plan_{p.id}"
                                _scheduler.add_job(
                                    func=_dispatch_notification_job,
                                    trigger="date",
                                    run_date=na_utc,
                                    id=job_id,
                                    args=[p.id],
                                    replace_existing=True,
                                    misfire_grace_time=60,
                                )
                                print(f"[SCHEDULE] scheduled job {job_id} from persisted notify_at {na_utc.isoformat()}")
                                continue
                        except Exception:
                            pass

                    # if notify_at in past -> decide: run immediately if within grace, else mark notified
                    if na is not None and na_utc <= now_utc:
                        age = now_utc - na_utc
                        if age <= GRACE_WINDOW:
                            immediate_run = now_utc + timedelta(seconds=5)
                            job_id = f"plan_{p.id}"
                            _scheduler.add_job(
                                func=_dispatch_notification_job,
                                trigger="date",
                                run_date=immediate_run,
                                id=job_id,
                                args=[p.id],
                                replace_existing=True,
                                misfire_grace_time=3600,
                            )
                            print(f"[SCHEDULE-RECOVER] job {job_id} missed by {age}, scheduled immediate run at {immediate_run.isoformat()}")
                            continue
                        else:
                            p.notified = True
                            db.add(p)
                            db.commit()
                            try:
                                print(f"[SCHEDULE-RECOVER] plan {p.id} notify_at {na_utc.isoformat()} too old (age={age}), marking notified to avoid late send")
                            except Exception:
                                print(f"[SCHEDULE-RECOVER] plan {p.id} notify_at too old, marking notified to avoid late send")
                            continue

                    # otherwise compute fresh schedule
                    schedule_notification_for_plan(p)
                except Exception:
                    import traceback
                    traceback.print_exc()
        finally:
            db.close()
    except Exception:
        import traceback
        traceback.print_exc()

    return _scheduler


def shutdown():
    global _scheduler
    if _scheduler is not None:
        try:
            _scheduler.shutdown(wait=False)
            print("[SCHEDULER] scheduler shutdown")
        except Exception:
            pass
    _scheduler = None


def _reschedule_user_pending_plans_sync(uid: str, db: Optional[Session] = None):
    own_session = False
    try:
        if db is None:
            db = SessionLocal()
            own_session = True
        now_utc = datetime.now(timezone.utc)
        start_date = (now_utc - timedelta(days=1)).date()
        end_date = (now_utc + timedelta(days=30)).date()
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
                user_zone = _get_user_zoneinfo(uid)
                try:
                    local_dt = datetime.combine(p.date, p.start_time).replace(tzinfo=user_zone)
                    notify_dt_utc = local_dt.astimezone(timezone.utc)
                except Exception:
                    notify_dt_utc = datetime.combine(p.date, p.start_time).replace(tzinfo=timezone.utc)
                if notify_dt_utc > now_utc:
                    schedule_notification_for_plan(p)
            except Exception:
                pass
    finally:
        if own_session and db is not None:
            try:
                db.close()
            except Exception:
                pass
