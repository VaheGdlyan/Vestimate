import sentry_sdk
import logfire
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.celery import CeleryIntegration
from sentry_sdk.integrations.asyncpg import AsyncPGIntegration
from prometheus_fastapi_instrumentator import Instrumentator
from fastapi import FastAPI
from app.core.config import settings
import logging

logger = logging.getLogger(__name__)

def init_sentry():
    if not settings.SENTRY_DSN or settings.SENTRY_DSN == "your-sentry-dsn":
        logger.warning("SENTRY_DSN not set — exception tracking disabled")
        return
    sentry_sdk.init(
        dsn=settings.SENTRY_DSN,
        environment=settings.ENV,
        integrations=[
            FastApiIntegration(transaction_style="endpoint"),
            CeleryIntegration(monitor_beat_tasks=True),
            AsyncPGIntegration(),
        ],
        traces_sample_rate=0.1,    # 10% of requests traced (cost control)
        profiles_sample_rate=0.05, # 5% profiling
        send_default_pii=False,    # GDPR: no PII in Sentry payloads
    )
    logger.info(f"Sentry initialised — env={settings.ENV}")

def init_logfire(app: FastAPI):
    if not settings.LOGFIRE_TOKEN or settings.LOGFIRE_TOKEN == "your-logfire-token":
        logger.warning("LOGFIRE_TOKEN not set — structured logging disabled")
        return
    logfire.configure(token=settings.LOGFIRE_TOKEN, service_name="vestimate-api")
    logfire.instrument_fastapi(app)
    logger.info("Logfire instrumentation active")

def init_prometheus(app: FastAPI):
    instrumentator = Instrumentator(
        should_group_status_codes=False,
        should_ignore_untemplated=True,
        should_instrument_requests_inprogress=True,
        excluded_handlers=["/health", "/metrics"],
    )
    instrumentator.instrument(app)
    instrumentator.expose(
        app,
        endpoint="/metrics",
        include_in_schema=False,
        # Secure /metrics behind a bearer token to prevent public scraping
        dependencies=[]  # Add token check dependency if needed
    )
    logger.info("Prometheus metrics exposed at /metrics")

def init_all(app: FastAPI):
    """Call once at application startup."""
    init_sentry()
    init_logfire(app)
    init_prometheus(app)
