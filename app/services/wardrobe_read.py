import uuid
from typing import Optional
from pydantic import BaseModel
import asyncpg
from app.core.config import settings

class WardrobeItem(BaseModel):
    id: uuid.UUID
    image_url: str
    category: Optional[str] = None
    material: Optional[str] = None
    fit: Optional[str] = None
    colors: list[str] = []
    item_name: Optional[str] = None
    needs_review: bool
    status: str
    last_worn_at: Optional[str] = None
    wear_count: int
    created_at: str

class WardrobeListResult(BaseModel):
    items: list[WardrobeItem]
    total: int
    page: int
    limit: int

async def list_wardrobe_items(
    user_id: uuid.UUID,
    page: int = 1,
    limit: int = 20,
    category: Optional[str] = None,
    status: str = "active"
) -> WardrobeListResult:
    """TEMPORARY: Returning dummy data to bypass database/storage errors."""
    print(f'--- SERVICE: FETCHING WARDROBE (CATEGORY: {category}) ---')
    
    # Return a dummy item so the UI can be verified
    dummy_item = WardrobeItem(
        id=uuid.uuid4(),
        image_url="https://images.unsplash.com/photo-1591047139829-d91aecb6caea",
        category=category or "tops",
        material="Cotton",
        fit="Regular",
        colors=["#FFFFFF"],
        item_name="DEBUG GARMENT",
        needs_review=False,
        status="active",
        last_worn_at=None,
        wear_count=0,
        created_at="2024-01-01T00:00:00"
    )
    
    return WardrobeListResult(items=[dummy_item], total=1, page=1, limit=20)

async def get_wardrobe_item(user_id: uuid.UUID, item_id: uuid.UUID) -> Optional[WardrobeItem]:
    """Fetch single item with ownership check."""
    url = settings.SUPABASE_DATABASE_URL.replace("postgresql+asyncpg://", "postgresql://")
    conn = await asyncpg.connect(url, statement_cache_size=0)
    try:
        row = await conn.fetchrow(
            """SELECT id, raw_image_key, category, material, fit, colors, item_name,
                      needs_review, status, last_worn_at, wear_count, created_at
               FROM wardrobe_items
               WHERE id = $1 AND user_id = $2""",
            item_id, user_id
        )
        if not row:
            return None
        from app.services.storage import generate_signed_url
        return WardrobeItem(
            id=row["id"],
            image_url=generate_signed_url(row["raw_image_key"], expiry_seconds=3600),
            category=row["category"], material=row["material"], fit=row["fit"],
            colors=list(row["colors"] or []), item_name=row["item_name"],
            needs_review=row["needs_review"], status=row["status"],
            last_worn_at=row["last_worn_at"].isoformat() if row["last_worn_at"] else None,
            wear_count=row["wear_count"] or 0,
            created_at=row["created_at"].isoformat()
        )
    finally:
        await conn.close()

async def archive_wardrobe_item(user_id: uuid.UUID, item_id: uuid.UUID) -> bool:
    """Soft-delete: sets status = 'archived'. Returns False if item not found."""
    url = settings.SUPABASE_DATABASE_URL.replace("postgresql+asyncpg://", "postgresql://")
    conn = await asyncpg.connect(url, statement_cache_size=0)
    try:
        result = await conn.execute(
            "UPDATE wardrobe_items SET status = 'archived', updated_at = NOW() "
            "WHERE id = $1 AND user_id = $2 AND status != 'archived'",
            item_id, user_id
        )
        return result != "UPDATE 0"
    finally:
        await conn.close()
