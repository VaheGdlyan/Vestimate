import uuid
from typing import List, Optional
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.core.auth import CurrentUser
from app.core.config import settings
import asyncpg
from datetime import datetime, timezone

router = APIRouter()

class OutfitCreate(BaseModel):
    label: str
    item_ids: List[uuid.UUID]
    stylist_note: Optional[str] = None
    source: str = "user_created"

class OutfitResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    label: Optional[str]
    item_ids: Optional[List[uuid.UUID]]
    stylist_note: Optional[str]
    source: str
    created_at: str
    worn_at: Optional[str]

async def _get_db_connection() -> asyncpg.Connection:
    dsn = settings.SUPABASE_DATABASE_URL.replace("postgresql+asyncpg://", "postgresql://")
    return await asyncpg.connect(dsn)

@router.post("", response_model=OutfitResponse, status_code=201)
async def create_outfit(current_user: CurrentUser, payload: OutfitCreate):
    conn = await _get_db_connection()
    try:
        row = await conn.fetchrow(
            """
            INSERT INTO outfits (user_id, label, item_ids, stylist_note, source, created_at)
            VALUES ($1, $2, $3, $4, $5, NOW())
            RETURNING id, user_id, label, item_ids, stylist_note, source, created_at, worn_at
            """,
            str(current_user),
            payload.label,
            [str(i) for i in payload.item_ids],
            payload.stylist_note,
            payload.source
        )
        return OutfitResponse(
            id=row["id"], user_id=row["user_id"], label=row["label"],
            item_ids=row["item_ids"], stylist_note=row["stylist_note"],
            source=row["source"], created_at=row["created_at"].isoformat(),
            worn_at=row["worn_at"].isoformat() if row["worn_at"] else None
        )
    finally:
        await conn.close()

@router.get("", response_model=List[OutfitResponse])
async def get_all_outfits(current_user: CurrentUser):
    conn = await _get_db_connection()
    try:
        rows = await conn.fetch(
            "SELECT * FROM outfits WHERE user_id = $1 ORDER BY created_at DESC",
            str(current_user)
        )
        return [OutfitResponse(
            id=row["id"], user_id=row["user_id"], label=row["label"],
            item_ids=row["item_ids"], stylist_note=row["stylist_note"],
            source=row["source"], created_at=row["created_at"].isoformat(),
            worn_at=row["worn_at"].isoformat() if row["worn_at"] else None
        ) for row in rows]
    finally:
        await conn.close()

@router.get("/{outfit_id}", response_model=OutfitResponse)
async def get_single_outfit(outfit_id: uuid.UUID, current_user: CurrentUser):
    conn = await _get_db_connection()
    try:
        row = await conn.fetchrow(
            "SELECT * FROM outfits WHERE id = $1 AND user_id = $2",
            str(outfit_id), str(current_user)
        )
        if not row:
            raise HTTPException(status_code=404, detail="Outfit not found")
        return OutfitResponse(
            id=row["id"], user_id=row["user_id"], label=row["label"],
            item_ids=row["item_ids"], stylist_note=row["stylist_note"],
            source=row["source"], created_at=row["created_at"].isoformat(),
            worn_at=row["worn_at"].isoformat() if row["worn_at"] else None
        )
    finally:
        await conn.close()

@router.delete("/{outfit_id}", status_code=204)
async def delete_outfit(outfit_id: uuid.UUID, current_user: CurrentUser):
    conn = await _get_db_connection()
    try:
        status = await conn.execute(
            "DELETE FROM outfits WHERE id = $1 AND user_id = $2",
            str(outfit_id), str(current_user)
        )
        if status == "DELETE 0":
            raise HTTPException(status_code=404, detail="Outfit not found or unauthorized")
    finally:
        await conn.close()
