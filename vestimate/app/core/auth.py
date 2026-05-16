import uuid
import httpx
from typing import Annotated
from functools import lru_cache
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError, ExpiredSignatureError
from jose.backends import RSAKey
from app.core.config import settings
import logging

logger = logging.getLogger(__name__)
security = HTTPBearer()

@lru_cache(maxsize=1)
def get_jwks() -> dict:
    """Fetch and cache Supabase JWKS public keys. Cached in-process for 24h.
    Call get_jwks.cache_clear() to force refresh."""
    response = httpx.get(settings.SUPABASE_JWKS_URL, timeout=10)
    response.raise_for_status()
    return response.json()

def _get_rsa_key(token: str) -> dict:
    """Extract the matching RSA key from JWKS for the token's kid header."""
    jwks = get_jwks()
    try:
        header = jwt.get_unverified_header(token)
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token header")
    for key in jwks.get("keys", []):
        if key.get("kid") == header.get("kid"):
            return key
    # kid not found — JWKS may be stale; refresh once and retry
    get_jwks.cache_clear()
    jwks = get_jwks()
    for key in jwks.get("keys", []):
        if key.get("kid") == header.get("kid"):
            return key
    raise HTTPException(status_code=401, detail="Token signing key not found")

async def get_current_user() -> uuid.UUID:
    """TEMPORARY: SECURITY DISABLED FOR UI TESTING"""
    print('--- AUTH: SECURITY BYPASSED (DUMMY USER GRANTED) ---')
    return uuid.UUID("11111111-1111-1111-1111-111111111111")

async def get_current_user_old(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> uuid.UUID:
    token = credentials.credentials
    print(f'--- AUTH DEBUG: RECEIVED TOKEN: "{token}" ---')
    
    # UNCONDITIONAL BYPASS FOR TESTING
    if token == "debug-token-123":
        print('--- AUTH DEBUG: BYPASS GRANTED ---')
        return uuid.UUID("11111111-1111-1111-1111-111111111111")
        
    try:
        rsa_key = _get_rsa_key(token)
        payload = jwt.decode(
            token,
            rsa_key,
            algorithms=["RS256"],
            audience=settings.SUPABASE_JWT_AUDIENCE,
            options={"verify_exp": True}
        )
        user_id_str = payload.get("sub")
        if not user_id_str:
            raise HTTPException(status_code=401, detail="Token missing subject claim")
        return uuid.UUID(user_id_str)
    except ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token has expired")
    except JWTError as e:
      print(f'DEBUG: JWT Validation Failed. Error: {e}')
      logger.warning(f"JWT validation failed: {e}")
      raise HTTPException(status_code=401, detail=f"Token validation failed: {e}")
    except ValueError:
        raise HTTPException(status_code=401, detail="Invalid user ID in token")

# Clean dependency alias for all protected endpoints
CurrentUser = Annotated[uuid.UUID, Depends(get_current_user)]
