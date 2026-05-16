"""
LLM Service — GPT-4o-mini Outfit Selection

Fetches the active prompt from Supabase prompt_versions table,
calls GPT-4o-mini with structured output (JSON Schema mode),
validates the response with Pydantic, and returns either a valid
OutfitSelection or falls back to heuristic selection.
"""

import json
import logging
from openai import OpenAI
from supabase import create_client
from app.core.config import settings
from app.models.recommendation_schemas import (
    OutfitSelection,
    CandidateSet,
    RecommendationContext,
)

logger = logging.getLogger(__name__)

_openai_client = OpenAI(api_key=settings.OPENAI_API_KEY)
_supabase_client = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)

# ── JSON Schema for OpenAI structured outputs ─────────────────────────────────
OUTFIT_SELECTION_SCHEMA = {
    "name": "outfit_selection",
    "strict": True,
    "schema": {
        "type": "object",
        "properties": {
            "top_id":      {"type": "string"},
            "bottom_id":   {"type": "string"},
            "shoe_id":     {"type": "string"},
            "stylist_note": {
                "type": "string",
                "description": "One sentence style tip, max 120 characters."
            },
        },
        "required": ["top_id", "bottom_id", "shoe_id", "stylist_note"],
        "additionalProperties": False,
    },
}


def _get_active_prompt() -> tuple[str, str]:
    """
    Fetches the active system prompt and user template from Supabase.
    Raises RuntimeError if no active prompt is found (migration not run).
    """
    result = (
        _supabase_client
        .table("prompt_versions")
        .select("system_prompt,user_prompt_template")
        .eq("is_active", True)
        .limit(1)
        .execute()
    )
    if not result.data:
        raise RuntimeError(
            "No active prompt found in prompt_versions table. "
            "Run migration 003_phase3_indexes_and_seed.sql first."
        )
    row = result.data[0]
    return row["system_prompt"], row["user_prompt_template"]


def _build_candidates_payload(candidates: CandidateSet) -> dict:
    """Serializes CandidateSet to a dict suitable for the LLM prompt."""
    return {
        "tops":    [c.model_dump(exclude={"image_url"}) for c in candidates.tops],
        "bottoms": [c.model_dump(exclude={"image_url"}) for c in candidates.bottoms],
        "shoes":   [c.model_dump(exclude={"image_url"}) for c in candidates.shoes],
    }


def _heuristic_fallback(candidates: CandidateSet) -> OutfitSelection:
    """
    Called when GPT response fails Pydantic validation or returns
    a hallucinated item ID. Selects the first candidate in each category.
    """
    logger.warning("Using heuristic fallback for outfit selection.")
    return OutfitSelection(
        top_id=candidates.tops[0].id,
        bottom_id=candidates.bottoms[0].id,
        shoe_id=candidates.shoes[0].id,
        stylist_note="A classic combination for any occasion.",
    )


def select_outfit(
    context: RecommendationContext,
    candidates: CandidateSet,
) -> tuple[OutfitSelection, bool]:
    """
    Calls GPT-4o-mini to select an outfit from the candidate set.
    Returns: (OutfitSelection, fallback_used: bool)
    """
    try:
        system_prompt, _ = _get_active_prompt()
        candidates_payload = _build_candidates_payload(candidates)

        user_message = json.dumps({
            "context": {
                "weather": f"{context.weather.condition} at {context.weather.temp_celsius}C",
                "temp_band": context.weather.temp_band,
                "day": context.day_of_week,
                "time_of_day": context.time_of_day,
                "formality": context.primary_formality,
                "top_event": (
                    context.schedule[0].title
                    if context.schedule else "general daily activities"
                ),
            },
            "candidates": candidates_payload,
        })

        response = _openai_client.chat.completions.create(
            model="gpt-4o-mini",
            temperature=0.3,
            max_tokens=200,
            timeout=8.0,
            response_format={
                "type": "json_schema",
                "json_schema": OUTFIT_SELECTION_SCHEMA,
            },
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_message},
            ],
        )

        raw_json = response.choices[0].message.content
        parsed = OutfitSelection.model_validate_json(raw_json)

        if not parsed.validate_against_candidates(candidates):
            logger.error(
                f"GPT returned hallucinated item IDs: "
                f"top={parsed.top_id}, bottom={parsed.bottom_id}, shoe={parsed.shoe_id}"
            )
            return _heuristic_fallback(candidates), True

        return parsed, False

    except Exception as e:
        logger.error(f"LLM selection failed: {e}")
        return _heuristic_fallback(candidates), True
