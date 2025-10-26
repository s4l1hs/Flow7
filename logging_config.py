import logging
from logging.config import dictConfig
import os
import sentry_sdk
from sentry_sdk.integrations.logging import LoggingIntegration
from pythonjsonlogger import jsonlogger


def configure_logging(level: str = None):
    level = level or "INFO"
    use_json = os.getenv('LOG_JSON', '0') == '1'
    if use_json:
        fmt = jsonlogger.JsonFormatter('%(asctime)s %(levelname)s %(name)s %(message)s')
        dictConfig({
            "version": 1,
            "disable_existing_loggers": False,
            "formatters": {"json": {"()": jsonlogger.JsonFormatter}},
            "handlers": {
                "default": {
                    "class": "logging.StreamHandler",
                    "formatter": "json",
                    "level": level,
                }
            },
            "root": {"handlers": ["default"], "level": level},
        })
    else:
        dictConfig({
            "version": 1,
            "disable_existing_loggers": False,
            "formatters": {
                "standard": {
                    "format": "%(asctime)s %(levelname)s [%(name)s] %(message)s"
                }
            },
            "handlers": {
                "default": {
                    "class": "logging.StreamHandler",
                    "formatter": "standard",
                    "level": level,
                }
            },
            "root": {
                "handlers": ["default"],
                "level": level,
            }
        })

    # optional Sentry initialization
    sentry_dsn = os.getenv('SENTRY_DSN')
    if sentry_dsn:
        sentry_logging = LoggingIntegration(level=logging.INFO, event_level=logging.ERROR)
        sentry_sdk.init(dsn=sentry_dsn, integrations=[sentry_logging])
