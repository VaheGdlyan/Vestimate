import uuid
from typing import Optional
from fastapi import APIRouter, HTTPException, Query
from app.core.auth import CurrentUser
from app.services.wardrobe_read import list_wardrobe_items, get_wardrobe_item, archive_wardrobe_item
from app.core.rate_limit import limiter
from fastapi import Request

router = APIRouter()

@router.get("/items")
@limiter.limit("60/minute")
async def get_wardrobe_items(
    request: Request,
    current_user: CurrentUser,
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=20, ge=1, le=100),
    category: Optional[str] = Query(default=None),
    status: str = Query(default="active")
):
    """Returns paginated wardrobe items for the authenticated user.
    Each item includes a signed R2 image URL valid for 1 hour."""
    result = await list_wardrobe_items(current_user, page, limit, category, status)
    return {
        "items": [item.__dict__ for item in result.items],
        "total": result.total,
        "page": result.page,
        "limit": result.limit
    }

@router.get("/items/{item_id}")
async def get_single_wardrobe_item(item_id: uuid.UUID, current_user: CurrentUser):
    """Returns a single wardrobe item. Returns 404 if not found or not owned by user."""
    item = await get_wardrobe_item(current_user, item_id)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return item.__dict__

@router.delete("/items/{item_id}", status_code=204)
async def delete_wardrobe_item(item_id: uuid.UUID, current_user: CurrentUser):
    """Soft-deletes a wardrobe item (sets status = 'archived').
    Archived items are excluded from all recommendation queries."""
    success = await archive_wardrobe_item(current_user, item_id)
    if not success:
        raise HTTPException(status_code=404, detail="Item not found or already archived")
