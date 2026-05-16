"""
Recommendation Cache Service

Redis cache for daily outfit recommendations.
Uses a SEPARATE Redis client on database index 1.
  - Index 0: Celery broker (do not touch)
  - Index 1: Application cache (this file)

Cache key format: rec:{user_id}:{date}:{weather_bucket}
TTL: 4 hours (14400 seconds)
"""

import json
import redis
from app.core.config import settings

# Dedicated client — index 1, not index 0 (Celery)
_cache = redis.Redis.from_url(
    settings.REDIS_URL.replace("/0", "/1"),
    decode_responses=True,
)

CACHE_TTL = 14400  # 4 hours
KEY_PREFIX = "rec"


def build_cache_key(user_id: str, date: str, weather_bucket: str) -> str:
    return f"{KEY_PREFIX}:{user_id}:{date}:{weather_bucket}"


def get_cached_recommendation(cache_key: str) -> dict | None:
    """Returns deserialized recommendation or None if not cached."""
    raw = _cache.get(cache_key)
    if raw is None:
        return None
    return json.loads(raw)


def set_cached_recommendation(cache_key: str, recommendation: dict) -> None:
    """Stores recommendation with 4h TTL."""
    _cache.setex(cache_key, CACHE_TTL, json.dumps(recommendation))


def invalidate_user_cache(user_id: str) -> int:
    """
    Deletes all recommendation cache entries for a user.
    Called when a user submits 'worn' feedback.
    Returns number of keys deleted.
    """
    pattern = f"{KEY_PREFIX}:{user_id}:*"
    keys = _cache.keys(pattern)
    if keys:
        return _cache.delete(*keys)
    return 0
