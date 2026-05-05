from celery.schedules import crontab
from app.worker.celery_app import celery_app

celery_app.conf.beat_schedule = {
    # Evict expired recommendation cache keys from Supabase (Redis expires itself)
    "evict-expired-recommendation-cache": {
        "task": "app.worker.tasks.evict_expired_recommendations",
        "schedule": crontab(minute=0, hour="*/6"),  # every 6 hours
    },
    # Pre-warm recommendations for users active in last 7 days
    "prewarm-recommendations": {
        "task": "app.worker.tasks.prewarm_recommendations",
        "schedule": crontab(minute=0, hour=23),  # 23:00 UTC daily
    },
}
celery_app.conf.timezone = "UTC"
