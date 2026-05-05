import uuid
import httpx
from typing import Optional
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel
from app.core.auth import CurrentUser
from app.core.config import settings
import asyncpg

router = APIRouter()

class UserProfile(BaseModel):
    id: uuid.UUID
    email: str
    display_name: Optional[str]
    city: Optional[str]
    timezone: Optional[str]
    onboarding_complete: bool
    created_at: str

class UserUpdate(BaseModel):
    display_name: Optional[str] = None
    city: Optional[str] = None
    timezone: Optional[str] = None
    onboarding_complete: Optional[bool] = None

class UserOnboard(BaseModel):
    email: str
    display_name: Optional[str] = None
    city: str
    timezone: str

async def _get_db_connection() -> asyncpg.Connection:
    url = settings.SUPABASE_DATABASE_URL.replace("postgresql+asyncpg://", "postgresql://")
    return await asyncpg.connect(url, statement_cache_size=0)

async def _validate_city(city: str):
    if not settings.OPENWEATHERMAP_API_KEY:
        return # Skip validation if no key
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"https://api.openweathermap.org/data/2.5/weather?q={city}&appid={settings.OPENWEATHERMAP_API_KEY}"
        )
        if resp.status_code == 404:
            raise HTTPException(status_code=422, detail="City not found by OpenWeatherMap")

@router.get("/me", response_model=UserProfile)
async def get_current_user_profile(current_user: CurrentUser):
    conn = await _get_db_connection()
    try:
        row = await conn.fetchrow(
            "SELECT id, email, display_name, city, timezone, onboarding_complete, created_at FROM users WHERE id = $1",
            str(current_user)
        )
        if not row:
            raise HTTPException(status_code=404, detail="User not found")
        return UserProfile(
            id=row["id"], email=row["email"], display_name=row["display_name"],
            city=row["city"], timezone=row["timezone"], onboarding_complete=row["onboarding_complete"],
            created_at=row["created_at"].isoformat()
        )
    finally:
        await conn.close()

@router.put("/me", response_model=UserProfile)
async def update_current_user_profile(current_user: CurrentUser, payload: UserUpdate):
    if payload.city:
        await _validate_city(payload.city)
    
    conn = await _get_db_connection()
    try:
        updates = []
        params = [str(current_user)]
        if payload.display_name is not None:
            updates.append(f"display_name = ${len(params)+1}")
            params.append(payload.display_name)
        if payload.city is not None:
            updates.append(f"city = ${len(params)+1}")
            params.append(payload.city)
        if payload.timezone is not None:
            updates.append(f"timezone = ${len(params)+1}")
            params.append(payload.timezone)
        if payload.onboarding_complete is not None:
            updates.append(f"onboarding_complete = ${len(params)+1}")
            params.append(payload.onboarding_complete)
            
        if not updates:
            return await get_current_user_profile(current_user)
            
        set_clause = ", ".join(updates)
        row = await conn.fetchrow(
            f"UPDATE users SET {set_clause} WHERE id = $1 RETURNING id, email, display_name, city, timezone, onboarding_complete, created_at",
            *params
        )
        return UserProfile(
            id=row["id"], email=row["email"], display_name=row["display_name"],
            city=row["city"], timezone=row["timezone"], onboarding_complete=row["onboarding_complete"],
            created_at=row["created_at"].isoformat()
        )
    finally:
        await conn.close()

@router.post("/me/onboard", status_code=201, response_model=UserProfile)
async def onboard_user(current_user: CurrentUser, payload: UserOnboard):
    await _validate_city(payload.city)
    conn = await _get_db_connection()
    try:
        row = await conn.fetchrow(
            """INSERT INTO users (id, email, display_name, city, timezone, onboarding_complete, created_at)
               VALUES ($1, $2, $3, $4, $5, true, NOW())
               ON CONFLICT (id) DO UPDATE SET 
                 email = EXCLUDED.email,
                 display_name = EXCLUDED.display_name,
                 city = EXCLUDED.city,
                 timezone = EXCLUDED.timezone,
                 onboarding_complete = true
               RETURNING id, email, display_name, city, timezone, onboarding_complete, created_at""",
            str(current_user), payload.email, payload.display_name, payload.city, payload.timezone
        )
        return UserProfile(
            id=row["id"], email=row["email"], display_name=row["display_name"],
            city=row["city"], timezone=row["timezone"], onboarding_complete=row["onboarding_complete"],
            created_at=row["created_at"].isoformat()
        )
    finally:
        await conn.close()
