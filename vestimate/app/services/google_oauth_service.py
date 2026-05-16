import base64
import hashlib
from cryptography.fernet import Fernet
import httpx
from app.core.config import settings

GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"

def _get_fernet() -> Fernet:
    """Build Fernet cipher from TOKEN_ENCRYPTION_KEY using a secure hash.
    The key is derived by SHA-256 hashing the raw key bytes, ensuring a constant 32-byte output.
    """
    raw = settings.TOKEN_ENCRYPTION_KEY.encode()
    derived = hashlib.sha256(raw).digest()  # 32 bytes
    key = base64.urlsafe_b64encode(derived)
    return Fernet(key)

def encrypt_token(token: str) -> str:
    return _get_fernet().encrypt(token.encode()).decode()

def decrypt_token(token: str) -> str:
    return _get_fernet().decrypt(token.encode()).decode()

import redis

_cache = redis.Redis.from_url(settings.REDIS_URL, decode_responses=True)

async def get_valid_access_token(user_id: str, encrypted_refresh_token: str) -> str:
    """Decrypt stored refresh token and exchange it for a fresh access token.
    Uses Redis caching to avoid hitting the Google API on every request.
    Returns the access token string. Raises HTTPException on failure.
    """
    cache_key = f"gtoken:{user_id}"
    cached_token = _cache.get(cache_key)
    if cached_token:
        return cached_token

    refresh_token = decrypt_token(encrypted_refresh_token)
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            GOOGLE_TOKEN_URL,
            data={
                "refresh_token": refresh_token,
                "client_id": settings.GOOGLE_CLIENT_ID,
                "client_secret": settings.GOOGLE_CLIENT_SECRET,
                "grant_type": "refresh_token",
            },
        )
        resp.raise_for_status()
        data = resp.json()
        access_token = data["access_token"]
        expires_in = data.get("expires_in", 3600)
        
        # Cache the token, subtracting 60s from TTL as a safety buffer
        ttl = max(60, expires_in - 60)
        _cache.setex(cache_key, ttl, access_token)
        
        return access_token
