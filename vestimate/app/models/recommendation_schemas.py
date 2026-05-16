from pydantic import BaseModel, Field, field_validator
from typing import Literal
import uuid


# ── Context Models ────────────────────────────────────────────────────────────

class WeatherData(BaseModel):
    temp_celsius: float
    condition: Literal["rain", "clear", "snow", "cloudy", "unknown"]
    wind_kmh: float = 0.0
    temp_band: Literal["cold", "mild", "warm"] = "mild"

    @field_validator("temp_band", mode="before")
    @classmethod
    def compute_temp_band(cls, v, values):
        # Allow explicit override; compute from temp if not set
        if v and v != "mild":
            return v
        temp = values.data.get("temp_celsius", 15)
        if temp < 10:
            return "cold"
        elif temp > 20:
            return "warm"
        return "mild"


class ScheduleEvent(BaseModel):
    title: str
    start_time: str  # HH:MM format
    formality: Literal[
        "casual", "business_casual", "formal", "athletic", "unknown"
    ] = "unknown"


class RecommendationContext(BaseModel):
    weather: WeatherData
    schedule: list[ScheduleEvent] = []
    date: str          # YYYY-MM-DD
    day_of_week: str   # e.g. "Tuesday"
    time_of_day: Literal["morning", "afternoon", "evening"]
    primary_formality: Literal[
        "casual", "business_casual", "formal", "athletic", "unknown"
    ] = "casual"


# ── Candidate Models ──────────────────────────────────────────────────────────

class GarmentCandidate(BaseModel):
    id: str
    image_url: str | None = None
    category: str
    material: str | None = None
    fit: str | None = None
    colors: list[str] = []


class CandidateSet(BaseModel):
    tops: list[GarmentCandidate] = []
    bottoms: list[GarmentCandidate] = []
    shoes: list[GarmentCandidate] = []


# ── LLM Output Schema ─────────────────────────────────────────────────────────

class OutfitSelection(BaseModel):
    top_id: str
    bottom_id: str
    shoe_id: str
    stylist_note: str = Field(..., max_length=120)

    def validate_against_candidates(self, candidates: CandidateSet) -> bool:
        """
        Verify all selected IDs actually exist in the candidate set
        passed to the LLM. Prevents hallucinated IDs from reaching DB.
        """
        top_ids = {g.id for g in candidates.tops}
        bottom_ids = {g.id for g in candidates.bottoms}
        shoe_ids = {g.id for g in candidates.shoes}
        return (
            self.top_id in top_ids
            and self.bottom_id in bottom_ids
            and self.shoe_id in shoe_ids
        )


# ── API Response Schema ───────────────────────────────────────────────────────

class OutfitItem(BaseModel):
    id: str
    image_url: str | None
    category: str
    material: str | None
    fit: str | None
    colors: list[str]


class OutfitRecommendationResponse(BaseModel):
    recommendation_id: str
    outfit: dict[str, OutfitItem]  # keys: "top", "bottom", "shoes"
    stylist_note: str
    context_summary: dict[str, str]
    generated_at: str
    cache_hit: bool
    fallback_used: bool = False


# ── Feedback Schema ───────────────────────────────────────────────────────────

class FeedbackRequest(BaseModel):
    recommendation_id: str
    action: Literal["worn", "skipped", "saved"]
    item_ids: list[str]
