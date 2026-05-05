"""
Recommendation Endpoint — GET /v1/recommendations/today

Synchronous from the client's perspective.
Internally: cache check -> context -> vector -> retrieval -> LLM -> cache write.
Target latency: <100ms on cache hit, <4s on cold path.
"""

import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, HTTPException, Query, Request
from app.core.rate_limit import limiter
from supabase import create_client
import logfire

from app.core.config import settings
from app.core.auth import CurrentUser
from app.services.storage import generate_signed_url
from typing import List, Optional
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
@limiter.limit(settings.RATE_LIMIT_RECOMMENDATION)
async def get_todays_recommendation(
    request: Request,
    current_user: CurrentUser,
    city: str = Query(default="Yerevan", description="User's city for weather lookup"),
):
    with logfire.span("recommendation.get_today", user_id=str(current_user), city=city):
        user_id = str(current_user)

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
            logfire.info("recommendation.cache_hit", user_id=user_id)
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
        with logfire.span("recommendation.llm_selection", user_id=user_id):
            selection, fallback_used = select_outfit(context=context, candidates=candidates)

        # ── Step 7: Build response ────────────────────────────────────────────────
        top = _find_garment(selection.top_id, candidates)
        bottom = _find_garment(selection.bottom_id, candidates)
        shoes = _find_garment(selection.shoe_id, candidates)

        # Convert to OutfitItems and sign URLs
        top_outfit = _garment_to_outfit_item(top)
        if top.image_url:
            top_outfit.image_url = generate_signed_url(top.image_url)

        bottom_outfit = _garment_to_outfit_item(bottom)
        if bottom.image_url:
            bottom_outfit.image_url = generate_signed_url(bottom.image_url)

        shoes_outfit = _garment_to_outfit_item(shoes)
        if shoes.image_url:
            shoes_outfit.image_url = generate_signed_url(shoes.image_url)

        recommendation_id = str(uuid.uuid4())
        generated_at = datetime.now(timezone.utc).isoformat()

        response_data = OutfitRecommendationResponse(
            recommendation_id=recommendation_id,
            outfit={
                "top":    top_outfit,
                "bottom": bottom_outfit,
                "shoes":  shoes_outfit,
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

        logfire.info("recommendation.complete", user_id=user_id, fallback_used=fallback_used)
        return response_data

@router.get(
    "/history",
    response_model=List[OutfitRecommendationResponse],
    summary="Get recommendation history",
)
async def get_recommendation_history(
    current_user: CurrentUser,
    limit: int = Query(default=10, ge=1, le=50),
    offset: int = Query(default=0, ge=0),
):
    """
    Returns paginated historical recommendations for the user.
    Fetches from outfits joined with recommendation_cache.
    """
    user_id = str(current_user)
    
    # Query with join
    result = (
        _supabase
        .table("recommendation_cache")
        .select("*, outfits(*)")
        .eq("user_id", user_id)
        .order("generated_at", desc=True)
        .range(offset, offset + limit - 1)
        .execute()
    )
    
    history = []
    for row in result.data:
        outfit_data = row.get("outfits")
        if not outfit_data:
            continue
            
        # Ensure we have strings for IDs and timestamps
        rec_id = str(row.get("outfit_id", ""))
        gen_at = str(row.get("generated_at", ""))
        
        history.append(OutfitRecommendationResponse(
            recommendation_id=rec_id,
            outfit={
                "top":    OutfitItem(id=str(outfit_data.get("top_id", "")), image_url=None, category="top", material=None, fit=None, colors=[]),
                "bottom": OutfitItem(id=str(outfit_data.get("bottom_id", "")), image_url=None, category="bottom", material=None, fit=None, colors=[]),
                "shoes":  OutfitItem(id=str(outfit_data.get("shoe_id", "")), image_url=None, category="shoes", material=None, fit=None, colors=[]),
            },
            stylist_note=outfit_data.get("stylist_note", "No note available"),
            context_summary={
                "weather": "Historical",
                "top_event": "Historical",
            },
            generated_at=gen_at,
            cache_hit=True,
            fallback_used=bool(row.get("fallback_used", False))
        ))
    
    return history
