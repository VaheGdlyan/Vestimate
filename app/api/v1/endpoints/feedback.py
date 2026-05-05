"""
Feedback Endpoint — POST /v1/feedback

Records user interaction with a recommendation.
On 'worn' action: updates last_worn_at for all outfit items
                  and busts the Redis recommendation cache.
"""

from datetime import datetime, timezone
from fastapi import APIRouter, HTTPException, Request
from supabase import create_client

from app.core.config import settings
from app.models.recommendation_schemas import FeedbackRequest
from app.services.recommendation_cache import invalidate_user_cache
from app.core.auth import CurrentUser
from app.core.rate_limit import limiter

router = APIRouter()
_supabase = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)


@router.post(
    "/",
    status_code=204,
    summary="Submit feedback on a recommendation",
)
@limiter.limit(settings.RATE_LIMIT_FEEDBACK)
async def submit_feedback(
    request: Request,
    current_user: CurrentUser,
    payload: FeedbackRequest,
):
    user_id = str(current_user)
    """
    Records feedback and updates wardrobe state.

    - worn:    Sets last_worn_at on all items. Busts Redis cache.
    - skipped: Records event only. No state change.
    - saved:   Records event only. No state change.
    """

    try:
        _supabase.table("feedback_events").insert({
            "user_id": user_id,
            "recommendation_id": payload.recommendation_id,
            "action": payload.action,
            "item_ids": payload.item_ids,
        }).execute()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to record feedback: {e}")

    if payload.action == "worn":
        try:
            now_iso = datetime.now(timezone.utc).isoformat()
            for item_id in payload.item_ids:
                _supabase.table("wardrobe_items").update({
                    "last_worn_at": now_iso,
                    "wear_count": _get_incremented_wear_count(item_id),
                }).eq("id", item_id).eq("user_id", user_id).execute()

            invalidate_user_cache(user_id)

        except Exception as e:
            import logging
            logging.getLogger(__name__).error(
                f"Failed to update wear state for user {user_id}: {e}"
            )

    return None  # 204 No Content


def _get_incremented_wear_count(item_id: str) -> int:
    """Fetches current wear_count and returns incremented value."""
    try:
        result = (
            _supabase.table("wardrobe_items")
            .select("wear_count")
            .eq("id", item_id)
            .limit(1)
            .execute()
        )
        if result.data:
            return (result.data[0].get("wear_count") or 0) + 1
    except Exception:
        pass
    return 1
