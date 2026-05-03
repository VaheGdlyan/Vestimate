"""
Vector Service — Query Vector Construction

Builds the 512-dim query vector by calling the FashionCLIP text encoder
on Modal. This vector is used for cosine similarity search against the
stored garment embeddings in pgvector.
"""

import httpx
import json
import redis
from app.core.config import settings

# Dedicated Redis client for vector cache — index 1 to avoid Celery collisions
_vector_cache = redis.Redis.from_url(
    settings.REDIS_URL.replace("/0", "/1"), decode_responses=False
)

VECTOR_CACHE_TTL = 3600  # 1 hour


async def get_query_vector(occasion_text: str) -> list[float]:
    """
    Returns a 512-dim query vector for the given occasion text.
    Cache key: vec:{hash of occasion_text}
    """
    import hashlib

    cache_key = f"vec:{hashlib.sha256(occasion_text.encode()).hexdigest()[:16]}"

    # Try cache first
    cached = _vector_cache.get(cache_key)
    if cached:
        return json.loads(cached)

    # Call Modal text encoder
    try:
        async with httpx.AsyncClient(timeout=25.0) as client:
            response = await client.post(
                settings.MODAL_ENDPOINT_TEXT_EMBED,
                json={"text": occasion_text},
            )
            response.raise_for_status()
            embedding = response.json()["embedding"]

        _vector_cache.setex(cache_key, VECTOR_CACHE_TTL, json.dumps(embedding))
        return embedding

    except Exception as e:
        import logging
        logging.getLogger(__name__).error(
            f"Vector encoding failed for '{occasion_text[:50]}': {e}"
        )
        return [0.0] * 512
