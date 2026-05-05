"""
Google Calendar OAuth Endpoints — Phase 5
POST /v1/users/me/google-oauth/callback  — exchange code for tokens, encrypt and store
GET  /v1/users/me/google-oauth/revoke    — revoke tokens and clear from DB
"""
import logging
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel
from cryptography.fernet import Fernet
import base64
import httpx
import asyncpg

from app.core.auth import CurrentUser
from app.core.config import settings

logger = logging.getLogger(__name__)
router = APIRouter()


# ── Encryption helpers (AES-128 via Fernet, key stored in TOKEN_ENCRYPTION_KEY) ──

def _get_fernet() -> Fernet:
    """Build Fernet cipher from TOKEN_ENCRYPTION_KEY (URL-safe base64, 32 bytes)."""
    raw = settings.TOKEN_ENCRYPTION_KEY.encode()
    # Pad or hash to exactly 32 bytes for Fernet
    padded = (raw * ((32 // len(raw)) + 1))[:32]
    key = base64.urlsafe_b64encode(padded)
    return Fernet(key)

def encrypt_token(token: str) -> str:
    return _get_fernet().encrypt(token.encode()).decode()

def decrypt_token(token: str) -> str:
    return _get_fernet().decrypt(token.encode()).decode()


# ── DB helper ──

async def _get_conn() -> asyncpg.Connection:
    url = settings.SUPABASE_DATABASE_URL.replace("postgresql+asyncpg://", "postgresql://")
    return await asyncpg.connect(url, statement_cache_size=0)


# ── Request / Response models ──

class OAuthCallbackRequest(BaseModel):
    code: str                            # Authorization code from Google
    redirect_uri: str                    # Must match the one used in auth flow


class OAuthCallbackResponse(BaseModel):
    message: str = "Google Calendar connected successfully"
    scopes: list[str] = []


# ── Google token exchange ──

GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"


async def _exchange_code_for_tokens(code: str, redirect_uri: str) -> dict:
    """Exchange auth code for access + refresh tokens via Google OAuth2."""
    async with httpx.AsyncClient() as client:
        resp = await client.post(GOOGLE_TOKEN_URL, data={
            "code": code,
            "client_id": settings.GOOGLE_CLIENT_ID,
            "client_secret": settings.GOOGLE_CLIENT_SECRET,
            "redirect_uri": redirect_uri,
            "grant_type": "authorization_code",
        })
        if resp.status_code != 200:
            raise HTTPException(
                status_code=400,
                detail=f"Google token exchange failed: {resp.text}"
            )
        return resp.json()


async def _revoke_google_token(access_token: str) -> None:
    """Notify Google to invalidate the token."""
    async with httpx.AsyncClient() as client:
        await client.post(
            "https://oauth2.googleapis.com/revoke",
            params={"token": access_token},
        )


# ── Endpoints ──

@router.post("/callback", response_model=OAuthCallbackResponse)
async def google_oauth_callback(
    current_user: CurrentUser,
    payload: OAuthCallbackRequest,
):
    """
    Exchange Google authorization code for OAuth tokens.
    Stores encrypted refresh_token in users.google_oauth_token.
    Encrypted with AES-128 Fernet using TOKEN_ENCRYPTION_KEY.
    """
    if not settings.GOOGLE_CLIENT_ID or not settings.GOOGLE_CLIENT_SECRET:
        raise HTTPException(
            status_code=503,
            detail="Google OAuth is not configured on this server"
        )

    token_data = await _exchange_code_for_tokens(payload.code, payload.redirect_uri)

    refresh_token = token_data.get("refresh_token")
    if not refresh_token:
        raise HTTPException(
            status_code=400,
            detail="No refresh_token returned — ensure access_type=offline in auth request"
        )

    # Encrypt before DB storage
    encrypted = encrypt_token(refresh_token)
    scopes = token_data.get("scope", "").split()

    conn = await _get_conn()
    try:
        await conn.execute(
            """UPDATE users
               SET google_oauth_token = $1, google_oauth_scopes = $2
               WHERE id = $3""",
            encrypted, scopes, str(current_user)
        )
    finally:
        await conn.close()

    logger.info(f"Google OAuth connected for user {current_user}, scopes: {scopes}")
    return OAuthCallbackResponse(scopes=scopes)


@router.get("/revoke", status_code=204)
async def google_oauth_revoke(current_user: CurrentUser):
    """
    Revokes the user's Google OAuth token with Google,
    then clears it from the database.
    """
    conn = await _get_conn()
    try:
        row = await conn.fetchrow(
            "SELECT google_oauth_token FROM users WHERE id = $1",
            str(current_user)
        )
        if not row or not row["google_oauth_token"]:
            raise HTTPException(status_code=404, detail="No Google OAuth token found")

        # Decrypt and revoke with Google
        try:
            refresh_token = decrypt_token(row["google_oauth_token"])
            await _revoke_google_token(refresh_token)
        except Exception as e:
            logger.warning(f"Google revocation call failed (continuing with DB clear): {e}")

        # Clear from DB regardless
        await conn.execute(
            "UPDATE users SET google_oauth_token = NULL, google_oauth_scopes = NULL WHERE id = $1",
            str(current_user)
        )
    finally:
        await conn.close()

    logger.info(f"Google OAuth revoked for user {current_user}")
