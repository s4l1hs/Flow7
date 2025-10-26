"""Dedicated scheduler worker.

This script starts only APScheduler with the same jobstore as the web app.
Use in production as a single scheduler process.
"""
import os
import signal
import time
import logging
from datetime import timezone
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.jobstores.sqlalchemy import SQLAlchemyJobStore
from apscheduler.executors.pool import ThreadPoolExecutor
from apscheduler.events import EVENT_JOB_EXECUTED, EVENT_JOB_ERROR

from logging_config import configure_logging
configure_logging(os.getenv('LOG_LEVEL', 'INFO'))
logger = logging.getLogger('flow7.scheduler')

_APSCHEDULER_DB_URL = os.getenv('APSCHEDULER_DB_URL', os.getenv('DATABASE_URL'))

SCHEDULER = None


def start_scheduler():
    global SCHEDULER
    jobstores = {'default': SQLAlchemyJobStore(url=_APSCHEDULER_DB_URL)}
    executors = {'default': ThreadPoolExecutor(10)}
    SCHEDULER = BackgroundScheduler(jobstores=jobstores, executors=executors, timezone=timezone.utc)

    def _job_listener(event):
        if event.code == EVENT_JOB_ERROR:
            logger.error('APScheduler job error: %s', event)

    SCHEDULER.add_listener(_job_listener, EVENT_JOB_EXECUTED | EVENT_JOB_ERROR)
    SCHEDULER.start()
    logger.info('Scheduler started (worker) using %s', _APSCHEDULER_DB_URL)


def shutdown(signum=None, frame=None):
    global SCHEDULER
    logger.info('Scheduler worker shutting down (signal=%s)', signum)
    try:
        if SCHEDULER:
            SCHEDULER.shutdown(wait=True)
    except Exception:
        logger.exception('Error shutting down scheduler')
    finally:
        # allow process to exit
        os._exit(0)


if __name__ == '__main__':
    start_scheduler()
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    # block forever
    while True:
        time.sleep(1)
