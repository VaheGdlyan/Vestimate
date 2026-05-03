"""
Context Aggregator for the Recommendation Engine.

Fetches external signals (weather, calendar) and normalizes them
into a RecommendationContext object. All external calls are wrapped
in try/except so a failure in one signal never blocks the whole request.
"""

import httpx
from datetime import datetime, timezone
from app.models.recommendation_schemas import (
    RecommendationContext,
    WeatherData,
    ScheduleEvent,
)
from app.core.config import settings

# ── Formality keyword classifier ──────────────────────────────────────────────
FORMALITY_KEYWORDS: dict[str, list[str]] = {
    "formal":          ["interview", "court", "ceremony", "gala", "wedding", "funeral"],
    "business_casual": ["meeting", "lunch", "conference", "client", "presentation",
                        "office", "work", "call", "zoom", "standup"],
    "athletic":        ["gym", "yoga", "run", "workout", "sport", "training",
                        "crossfit", "swim", "tennis", "hike"],
    "casual":          ["dinner", "coffee", "date", "party", "friend", "birthday",
                        "brunch", "walk", "movie"],
}


def classify_formality(title: str) -> str:
    title_lower = title.lower()
    for formality, keywords in FORMALITY_KEYWORDS.items():
        if any(kw in title_lower for kw in keywords):
            return formality
    return "unknown"


def _get_time_of_day(hour: int) -> str:
    if hour < 12:
        return "morning"
    elif hour < 17:
        return "afternoon"
    return "evening"


# ── Weather fetch ─────────────────────────────────────────────────────────────

async def get_weather(city: str) -> WeatherData:
    """
    Fetches current weather from OpenWeatherMap.
    Returns a safe default on failure — never raises.
    """
    default = WeatherData(
        temp_celsius=18.0,
        condition="unknown",
        wind_kmh=0.0,
        temp_band="mild",
    )

    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(
                "https://api.openweathermap.org/data/2.5/weather",
                params={
                    "q": city,
                    "appid": settings.OPENWEATHERMAP_API_KEY,
                    "units": "metric",
                },
            )
            if response.status_code != 200:
                return default

            data = response.json()
            temp = data["main"]["temp"]
            condition_id = data["weather"][0]["id"]
            wind = data.get("wind", {}).get("speed", 0.0)

            if condition_id < 600:
                condition = "rain"
            elif condition_id < 700:
                condition = "snow"
            elif condition_id < 800:
                condition = "cloudy"
            elif condition_id == 800:
                condition = "clear"
            else:
                condition = "cloudy"

            return WeatherData(
                temp_celsius=round(temp, 1),
                condition=condition,
                wind_kmh=round(wind * 3.6, 1),
                temp_band="cold" if temp < 10 else "warm" if temp > 20 else "mild",
            )

    except Exception:
        return default


# ── Calendar fetch ────────────────────────────────────────────────────────────

async def get_calendar_events(oauth_token: str | None) -> list[ScheduleEvent]:
    """
    Fetches today's Google Calendar events via OAuth token.
    Returns empty list if no token or any failure — never raises.
    """
    if not oauth_token:
        return []

    try:
        now = datetime.now(timezone.utc)
        time_min = now.isoformat()
        time_max = now.replace(hour=23, minute=59, second=59).isoformat()

        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(
                "https://www.googleapis.com/calendar/v3/calendars/primary/events",
                headers={"Authorization": f"Bearer {oauth_token}"},
                params={
                    "timeMin": time_min,
                    "timeMax": time_max,
                    "maxResults": 3,
                    "singleEvents": "true",
                    "orderBy": "startTime",
                },
            )
            if response.status_code != 200:
                return []

            items = response.json().get("items", [])
            events = []
            for item in items:
                title = item.get("summary", "")
                start = item.get("start", {}).get("dateTime", "")
                time_str = start[11:16] if start else "09:00"
                events.append(ScheduleEvent(
                    title=title,
                    start_time=time_str,
                    formality=classify_formality(title),
                ))
            return events

    except Exception:
        return []


# ── Primary context builder ───────────────────────────────────────────────────

async def build_context(city: str, oauth_token: str | None) -> RecommendationContext:
    """Entry point for the context aggregation step."""
    weather = await get_weather(city)
    events = await get_calendar_events(oauth_token)

    now = datetime.now()
    date_str = now.strftime("%Y-%m-%d")
    day_of_week = now.strftime("%A")
    time_of_day = _get_time_of_day(now.hour)

    formality_rank = ["formal", "business_casual", "athletic", "casual", "unknown"]
    detected = [e.formality for e in events if e.formality != "unknown"]
    primary = "casual"
    for level in formality_rank:
        if level in detected:
            primary = level
            break

    return RecommendationContext(
        weather=weather,
        schedule=events,
        date=date_str,
        day_of_week=day_of_week,
        time_of_day=time_of_day,
        primary_formality=primary,
    )


def build_occasion_string(context: RecommendationContext) -> str:
    """Converts context into a natural language string for FashionCLIP text encoder."""
    top_event = context.schedule[0].title if context.schedule else "daily activities"
    return (
        f"{context.primary_formality.replace('_', ' ')} outfit for "
        f"{context.weather.condition} weather at {context.weather.temp_celsius}C, "
        f"{context.day_of_week} {context.time_of_day}, "
        f"event: {top_event}"
    )


def compute_weather_bucket(context: RecommendationContext) -> str:
    """Produces a deterministic string for Redis cache key."""
    return f"{context.weather.temp_band}_{context.weather.condition}"
