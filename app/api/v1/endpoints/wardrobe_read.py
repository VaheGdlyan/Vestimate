import uuid
from typing import Optional
from fastapi import APIRouter, HTTPException, Query
from app.core.auth import CurrentUser
from app.services.wardrobe_read import list_wardrobe_items, get_wardrobe_item, archive_wardrobe_item
from app.core.rate_limit import limiter
from fastapi import Request

from app.services.wardrobe_read import WardrobeItem, WardrobeListResult
from app.models.schemas import ErrorResponse

router = APIRouter(tags=["wardrobe"])

@router.get("/items", response_model=WardrobeListResult, summary="List wardrobe items", description="Returns paginated wardrobe items for the authenticated user. Each item includes a signed R2 image URL valid for 1 hour.")
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
    return result

@router.get("/items/{item_id}", response_model=WardrobeItem, summary="Get single wardrobe item", description="Returns a single wardrobe item. Returns 404 if not found or not owned by user.")
async def get_single_wardrobe_item(item_id: uuid.UUID, current_user: CurrentUser):
    """Returns a single wardrobe item. Returns 404 if not found or not owned by user."""
    item = await get_wardrobe_item(current_user, item_id)
    if not item:
        raise HTTPException(
            status_code=404, 
            detail=ErrorResponse(code="item_not_found", message="Item not found").model_dump()
        )
    return item

@router.delete("/items/{item_id}", status_code=204, summary="Archive wardrobe item", description="Soft-deletes a wardrobe item (sets status = 'archived'). Archived items are excluded from all recommendation queries.")
async def delete_wardrobe_item(item_id: uuid.UUID, current_user: CurrentUser):
    """Soft-deletes a wardrobe item (sets status = 'archived').
    Archived items are excluded from all recommendation queries."""
    success = await archive_wardrobe_item(current_user, item_id)
    if not success:
        raise HTTPException(
            status_code=404, 
            detail=ErrorResponse(code="item_not_found", message="Item not found or already archived").model_dump()
        )
