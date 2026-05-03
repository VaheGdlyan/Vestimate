"""
Recommendation Endpoint — GET /v1/recommendations/today

Synchronous from the client's perspective.
Internally: cache check -> context -> vector -> retrieval -> LLM -> cache write.
Target latency: <100ms on cache hit, <4s on cold path.
"""

import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, HTTPException, Query
from supabase import create_client

from app.core.config import settings
from app.models.recommendation_schemas import (
    OutfitRecommendationResponse,
    OutfitItem,
    GarmentCandidate,
)
from app.services.context_aggregator import (
    build_context,
    build_occasion_string,
    compute_weather_bucket,
)
from app.services.vector_service import get_query_vector
from app.services.retrieval import get_candidates, has_sufficient_candidates
from app.services.llm_service import select_outfit
from app.services.recommendation_cache import (
    build_cache_key,
    get_cached_recommendation,
    set_cached_recommendation,
)

router = APIRouter()
_supabase = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)


def _garment_to_outfit_item(garment: GarmentCandidate) -> OutfitItem:
    return OutfitItem(
        id=garment.id,
        image_url=garment.image_url,
        category=garment.category,
        material=garment.material,
        fit=garment.fit,
        colors=garment.colors,
    )


def _find_garment(garment_id: str, candidates) -> GarmentCandidate | None:
    all_items = candidates.tops + candidates.bottoms + candidates.shoes
    return next((g for g in all_items if g.id == garment_id), None)


@router.get(
    "/today",
    response_model=OutfitRecommendationResponse,
    summary="Get today's outfit recommendation",
)
async def get_todays_recommendation(
    user_id: str = Query(..., description="The authenticated user's ID"),
    city: str = Query(default="Yerevan", description="User's city for weather lookup"),
):
    """
    Returns the outfit recommendation for the current user session.

    Flow:
      1. Check Redis cache -> return immediately on hit
      2. Aggregate context (weather + calendar)
      3. Build query vector via FashionCLIP text encoder
      4. Retrieve candidates from pgvector
      5. Call GPT-4o-mini to select outfit
      6. Validate, cache, and return
    """

    # ── Step 1: Fetch user data ───────────────────────────────────────────────
    user_result = (
        _supabase
        .table("users")
        .select("city,google_oauth_token,timezone")
        .eq("id", user_id)
        .limit(1)
        .execute()
    )
    if not user_result.data:
        raise HTTPException(status_code=404, detail="User not found.")

    user_data = user_result.data[0]
    user_city = user_data.get("city") or city
    oauth_token = user_data.get("google_oauth_token")

    # ── Step 2: Build context ─────────────────────────────────────────────────
    context = await build_context(city=user_city, oauth_token=oauth_token)
    weather_bucket = compute_weather_bucket(context)

    # ── Step 3: Check Redis cache ─────────────────────────────────────────────
    cache_key = build_cache_key(user_id, context.date, weather_bucket)
    cached = get_cached_recommendation(cache_key)

    if cached:
        cached["cache_hit"] = True
        return OutfitRecommendationResponse(**cached)

    # ── Step 4: Build query vector ────────────────────────────────────────────
    occasion_text = build_occasion_string(context)
    query_vector = await get_query_vector(occasion_text)

    # ── Step 5: Retrieve candidates ───────────────────────────────────────────
    candidates = await get_candidates(user_id=user_id, query_vector=query_vector)

    if not has_sufficient_candidates(candidates):
        raise HTTPException(
            status_code=404,
            detail={
                "code": "insufficient_wardrobe",
                "message": (
                    "Add at least 1 top, 1 bottom, and 1 pair of shoes "
                    "to receive a recommendation."
                ),
            },
        )

    # ── Step 6: GPT outfit selection ──────────────────────────────────────────
    selection, fallback_used = select_outfit(context=context, candidates=candidates)

    # ── Step 7: Build response ────────────────────────────────────────────────
    top = _find_garment(selection.top_id, candidates)
    bottom = _find_garment(selection.bottom_id, candidates)
    shoes = _find_garment(selection.shoe_id, candidates)

    recommendation_id = str(uuid.uuid4())
    generated_at = datetime.now(timezone.utc).isoformat()

    response_data = OutfitRecommendationResponse(
        recommendation_id=recommendation_id,
        outfit={
            "top":    _garment_to_outfit_item(top),
            "bottom": _garment_to_outfit_item(bottom),
            "shoes":  _garment_to_outfit_item(shoes),
        },
        stylist_note=selection.stylist_note,
        context_summary={
            "weather": f"{context.weather.temp_celsius}C, {context.weather.condition}",
            "top_event": (
                context.schedule[0].title if context.schedule
                else "No events scheduled"
            ),
        },
        generated_at=generated_at,
        cache_hit=False,
        fallback_used=fallback_used,
    )

    # ── Step 8: Write to DB and cache ─────────────────────────────────────────
    try:
        _supabase.table("outfits").insert({
            "id": recommendation_id,
            "user_id": user_id,
            "top_id": selection.top_id,
            "bottom_id": selection.bottom_id,
            "shoe_id": selection.shoe_id,
            "stylist_note": selection.stylist_note,
            "source": "fallback" if fallback_used else "llm",
        }).execute()

        _supabase.table("recommendation_cache").insert({
            "id": str(uuid.uuid4()),
            "user_id": user_id,
            "outfit_id": recommendation_id,
            "cache_key": cache_key,
            "weather_snapshot": context.weather.model_dump(),
            "schedule_snapshot": [e.model_dump() for e in context.schedule],
            "was_cache_hit": False,
            "fallback_used": fallback_used,
        }).execute()

    except Exception as e:
        import logging
        logging.getLogger(__name__).error(f"DB write failed for recommendation: {e}")

    set_cached_recommendation(cache_key, response_data.model_dump())

    return response_data
