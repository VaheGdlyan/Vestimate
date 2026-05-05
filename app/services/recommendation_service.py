import uuid
from datetime import datetime, timezone
from typing import Optional
import asyncpg
import logfire
from app.core.config import settings
from app.models.recommendation_schemas import (
    OutfitRecommendationResponse,
    OutfitItem,
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
from app.services.storage import generate_signed_url

def _garment_to_outfit_item(garment) -> OutfitItem:
    return OutfitItem(
        id=garment.id,
        image_url=garment.image_url,
        category=garment.category,
        material=garment.material,
        fit=garment.fit,
        colors=garment.colors,
    )

def _find_garment(garment_id: str, candidates) -> Optional[any]:
    all_items = candidates.tops + candidates.bottoms + candidates.shoes
    return next((g for g in all_items if g.id == garment_id), None)

async def generate_recommendation_for_user(user_id: str, city: Optional[str] = None, force_refresh: bool = False) -> OutfitRecommendationResponse:
    """
    Core recommendation pipeline, extracted from endpoint for reuse in periodic tasks.
    """
    from supabase import create_client
    supabase = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)
    
    with logfire.span("recommendation.generate", user_id=user_id):
        # 1. Get user data
        user_result = supabase.table("users").select("*").eq("id", user_id).limit(1).execute()
        if not user_result.data:
            raise ValueError("User not found")
        
        user_data = user_result.data[0]
        user_city = user_data.get("city") or city or "Yerevan"
        oauth_token = user_data.get("google_oauth_token")

        # 2. Build context
        context = await build_context(city=user_city, oauth_token=oauth_token)
        weather_bucket = compute_weather_bucket(context)

        # 3. Cache check
        cache_key = build_cache_key(user_id, context.date, weather_bucket)
        if not force_refresh:
            cached = get_cached_recommendation(cache_key)
            if cached:
                cached["cache_hit"] = True
                return OutfitRecommendationResponse(**cached)

        # 4. Pipeline
        occasion_text = build_occasion_string(context)
        query_vector = await get_query_vector(occasion_text)
        candidates = await get_candidates(user_id=user_id, query_vector=query_vector)

        if not has_sufficient_candidates(candidates):
            raise ValueError("insufficient_wardrobe")

        with logfire.span("recommendation.llm_selection"):
            selection, fallback_used = select_outfit(context=context, candidates=candidates)

        # 5. Build response
        top = _find_garment(selection.top_id, candidates)
        bottom = _find_garment(selection.bottom_id, candidates)
        shoes = _find_garment(selection.shoe_id, candidates)

        top_outfit = _garment_to_outfit_item(top)
        if top.image_url: top_outfit.image_url = generate_signed_url(top.image_url)

        bottom_outfit = _garment_to_outfit_item(bottom)
        if bottom.image_url: bottom_outfit.image_url = generate_signed_url(bottom.image_url)

        shoes_outfit = _garment_to_outfit_item(shoes)
        if shoes.image_url: shoes_outfit.image_url = generate_signed_url(shoes.image_url)

        recommendation_id = str(uuid.uuid4())
        generated_at = datetime.now(timezone.utc).isoformat()

        response_data = OutfitRecommendationResponse(
            recommendation_id=recommendation_id,
            outfit={"top": top_outfit, "bottom": bottom_outfit, "shoes": shoes_outfit},
            stylist_note=selection.stylist_note,
            context_summary={
                "weather": f"{context.weather.temp_celsius}C, {context.weather.condition}",
                "top_event": context.schedule[0].title if context.schedule else "No events"
            },
            generated_at=generated_at,
            cache_hit=False,
            fallback_used=fallback_used,
        )

        # 6. Persistence
        supabase.table("outfits").insert({
            "id": recommendation_id, "user_id": user_id,
            "top_id": selection.top_id, "bottom_id": selection.bottom_id, "shoe_id": selection.shoe_id,
            "stylist_note": selection.stylist_note, "source": "llm" if not fallback_used else "fallback"
        }).execute()

        supabase.table("recommendation_cache").insert({
            "id": str(uuid.uuid4()), "user_id": user_id, "outfit_id": recommendation_id,
            "cache_key": cache_key, "weather_snapshot": context.weather.model_dump(),
            "was_cache_hit": False, "fallback_used": fallback_used
        }).execute()

        set_cached_recommendation(cache_key, response_data.model_dump())
        return response_data
