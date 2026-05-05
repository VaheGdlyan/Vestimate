import uuid
from typing import Optional
from dataclasses import dataclass
import asyncpg
from app.core.config import settings

@dataclass
class WardrobeItem:
    id: uuid.UUID
    image_url: str
    category: Optional[str]
    material: Optional[str]
    fit: Optional[str]
    colors: list[str]
    item_name: Optional[str]
    needs_review: bool
    status: str
    last_worn_at: Optional[str]
    wear_count: int
    created_at: str

@dataclass
class WardrobeListResult:
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
    """Paginated wardrobe retrieval. Generates signed R2 URLs for each item."""
    url = settings.SUPABASE_DATABASE_URL.replace("postgresql+asyncpg://", "postgresql://")
    conn = await asyncpg.connect(url, statement_cache_size=0)
    try:
        offset = (page - 1) * limit
        where_clauses = ["user_id = $1", "status = $2"]
        params = [user_id, status]

        if category:
            where_clauses.append(f"category = ${len(params) + 1}")
            params.append(category)

        where_sql = " AND ".join(where_clauses)
        count_params = params[:len(params)]

        total = await conn.fetchval(
            f"SELECT COUNT(*) FROM wardrobe_items WHERE {where_sql}",
            *count_params
        )
        rows = await conn.fetch(
            f"""SELECT id, raw_image_key, category, material, fit, colors, item_name,
                       needs_review, status, last_worn_at, wear_count, created_at
                FROM wardrobe_items
                WHERE {where_sql}
                ORDER BY created_at DESC
                LIMIT ${len(params) + 1} OFFSET ${len(params) + 2}""",
            *params, limit, offset
        )
        from app.services.storage import generate_signed_url
        items = [
            WardrobeItem(
                id=row["id"],
                image_url=generate_signed_url(row["raw_image_key"], expiry_seconds=3600),
                category=row["category"],
                material=row["material"],
                fit=row["fit"],
                colors=list(row["colors"] or []),
                item_name=row["item_name"],
                needs_review=row["needs_review"],
                status=row["status"],
                last_worn_at=row["last_worn_at"].isoformat() if row["last_worn_at"] else None,
                wear_count=row["wear_count"] or 0,
                created_at=row["created_at"].isoformat()
            )
            for row in rows
        ]
        return WardrobeListResult(items=items, total=total, page=page, limit=limit)
    finally:
        await conn.close()

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
