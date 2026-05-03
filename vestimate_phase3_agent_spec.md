# Vestimate — Phase 3 Agent Instruction File
# Service 3: Recommendation Engine

**Issued to:** Antigravity IDE Agent  
**Issued by:** System Architect — Vestimate  
**Prerequisite:** Phase 2 is COMPLETE. Do not verify Phase 2. Assume it works.  
**Your deliverable:** A fully working `GET /v1/recommendations/today` endpoint.

---

## Prime Directive

You are a senior backend engineer executing Phase 3 of the Vestimate backend.
You write code. You run it. You verify it passes its gate. Then you move to the
next step. You do not skip steps. You do not reorder steps. You do not add
features not listed here.

Every step ends with a GATE. The gate is a shell command with an expected output.
You do not proceed to the next step until the gate passes.

If a gate fails, you fix the code in the current step and re-run the gate.
You do not move forward on a broken gate.

---

## System Context (Read Once, Do Not Re-Analyze)

**What Phase 2 built (already exists, do not touch):**
- `POST /v1/wardrobe/upload` — uploads image to R2, enqueues Celery task
- `GET /v1/tasks/{task_id}` — polls Celery task status
- `app/worker/tasks.py` — ingest_garment pipeline (rembg → FashionCLIP → Supabase)
- `app/services/storage.py` — Cloudflare R2 (boto3) integration
- `app/core/config.py` — Pydantic BaseSettings (DO add new keys, do NOT remove existing)
- `app/worker/celery_app.py` — Celery + Redis broker on redis://localhost:6379/0
- Supabase schema with `wardrobe_items` (512-dim `embedding` via pgvector)
- Tables ready but empty: `outfits`, `recommendation_cache`, `prompt_versions`,
  `feedback_events`

**What Phase 3 must build (your task):**
- Context aggregator (weather + calendar)
- Query vector construction (FashionCLIP text encoder via Modal)
- pgvector category-split retrieval
- GPT-4o-mini outfit selection with Pydantic validation
- Redis recommendation cache (separate from Celery broker)
- `GET /v1/recommendations/today` endpoint
- `POST /v1/feedback` endpoint
- Database seed for `prompt_versions`

**Critical architectural decision already made:**
The query vector is built using the FashionCLIP text encoder (same 512-dim latent
space as stored garment embeddings). Do NOT use OpenAI embeddings for the query
vector. The stored `embedding` column was produced by FashionCLIP's image encoder.
The query vector must come from FashionCLIP's text encoder to ensure cosine
similarity is geometrically valid.

---

## File Creation Map

You will create exactly these new files. No others.

```
app/
├── api/v1/endpoints/
│   ├── recommendations.py        ← NEW: recommendation endpoint
│   └── feedback.py               ← NEW: feedback endpoint
├── core/
│   └── config.py                 ← MODIFY: add 3 new env vars only
├── models/
│   └── recommendation_schemas.py ← NEW: all Pydantic schemas for Phase 3
├── services/
│   ├── context_aggregator.py     ← NEW: weather + calendar logic
│   ├── retrieval.py              ← NEW: pgvector query logic
│   ├── llm_service.py            ← NEW: GPT-4o-mini call + validation
│   └── recommendation_cache.py  ← NEW: Redis cache logic (separate client)
└── worker/
    └── modal_inference.py        ← MODIFY: add text_embed endpoint only

migrations/
└── 003_phase3_indexes_and_seed.sql ← NEW: pgvector index + prompt seed

app/api/v1/__init__.py            ← MODIFY: register 2 new routers only
```

Files you must NOT touch:
- `app/worker/tasks.py`
- `app/worker/celery_app.py`
- `app/services/storage.py`
- `app/api/v1/endpoints/wardrobe.py`
- `app/api/v1/endpoints/tasks.py`
- `main.py`
- `docker-compose.yml`
- `Dockerfile`
- Any existing migration file

---

## Step 0 — Environment Preparation

### 0.1 Add new packages to requirements.txt

Add these lines. Do not remove existing lines.

```
openai==1.35.0
httpx==0.27.0
```

Verify `redis`, `supabase`, `asyncpg`, and `sqlalchemy` are already present.
If any are missing, add them.

Then run:
```bash
pip install -r requirements.txt
```

### 0.2 Add new environment variables to .env

Add these three keys to your `.env` file (do not delete existing keys):

```env
OPENAI_API_KEY=your_openai_api_key_here
OPENWEATHERMAP_API_KEY=your_openweathermap_api_key_here
SUPABASE_DATABASE_URL=postgresql+asyncpg://postgres:[PASSWORD]@[HOST]:5432/postgres
```

Also add them to `.env.example` with placeholder values.

### 0.3 Modify app/core/config.py

Add exactly these three fields to the existing `Settings` class.
Do not change any existing field.

```python
# Add inside the Settings class body:
OPENAI_API_KEY: str
OPENWEATHERMAP_API_KEY: str
SUPABASE_DATABASE_URL: str
```

**GATE 0:**
```bash
python -c "from app.core.config import settings; print(settings.OPENAI_API_KEY[:6])"
```
Expected: First 6 characters of your OpenAI key printed. No ImportError.

---

## Step 1 — Database Migration

Create `migrations/003_phase3_indexes_and_seed.sql` with exactly this content:

```sql
-- ============================================================
-- PHASE 3 MIGRATION: Indexes + Prompt Seed
-- Run this against your Supabase project via the SQL editor.
-- ============================================================

-- 1. IVFFlat index for cosine similarity on wardrobe embeddings
--    NOTE: Only run after wardrobe_items has at least 1 row with
--    a non-null embedding. If table is empty, run after first
--    garment is ingested.
CREATE INDEX IF NOT EXISTS idx_wardrobe_embedding
ON wardrobe_items
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

-- 2. Composite index for the category-split retrieval query pattern
CREATE INDEX IF NOT EXISTS idx_wardrobe_active_user_category
ON wardrobe_items (user_id, category)
WHERE status = 'active';

-- 3. Index for recency filter
CREATE INDEX IF NOT EXISTS idx_wardrobe_last_worn
ON wardrobe_items (user_id, last_worn_at DESC);

-- 4. Seed the initial prompt version (required for Phase 3 to run)
INSERT INTO prompt_versions (version, system_prompt, user_prompt_template, is_active, notes)
VALUES (
  'v1.0.0',
  'You are a professional stylist assistant. Your task is to select one complete outfit from the provided candidate garments that is appropriate for the given context. You must return ONLY a valid JSON object matching the exact schema provided. Do not add commentary, explanation, or text outside the JSON object.',
  '{"context": {{context}}, "candidates": {{candidates}}}',
  true,
  'Phase 3 initial launch prompt'
)
ON CONFLICT DO NOTHING;
```

Run this SQL in your Supabase SQL editor.

**GATE 1:**
```bash
python -c "
from supabase import create_client
import os
from dotenv import load_dotenv
load_dotenv()
client = create_client(os.getenv('SUPABASE_URL'), os.getenv('SUPABASE_SERVICE_KEY'))
result = client.table('prompt_versions').select('version,is_active').eq('is_active', True).execute()
print(result.data)
"
```
Expected: `[{'version': 'v1.0.0', 'is_active': True}]`

---

## Step 2 — Pydantic Schemas

Create `app/models/recommendation_schemas.py`:

```python
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
```

**GATE 2:**
```bash
python -c "
from app.models.recommendation_schemas import (
    OutfitSelection, RecommendationContext, CandidateSet,
    OutfitRecommendationResponse, FeedbackRequest
)
print('All schemas import cleanly')
"
```
Expected: `All schemas import cleanly`

---

## Step 3 — Modal Text Embedding Endpoint

Open `app/worker/modal_inference.py`. 
Find the existing Modal app definition.
Add ONE new function to the existing app. Do not modify any existing function.

Add this function after your existing functions:

```python
@app.function(image=image, gpu="T4", timeout=20)
@modal.web_endpoint(method="POST")
def text_embed(payload: dict) -> dict:
    """
    Encodes a text string using FashionCLIP's text encoder.
    Uses the SAME latent space as the image encoder (embed_and_tag).
    This ensures cosine similarity between query vectors and stored
    garment embeddings is geometrically valid.

    Input:  { "text": "business casual outfit for rain at 14°C" }
    Output: { "embedding": [0.023, -0.114, ...] }  # float[512]
    """
    import torch
    from fashion_clip.fashion_clip import FashionCLIP

    text = payload.get("text", "")
    if not text:
        return {"embedding": [0.0] * 512}

    # FashionCLIP is already loaded in the container image
    # Use the text encoder branch only — no image required
    fclip = FashionCLIP("patrickjohncyh/fashion-clip")

    with torch.no_grad():
        text_embedding = fclip.encode_text([text], batch_size=1)

    # L2-normalize and convert to Python list
    embedding = text_embedding[0]
    norm = embedding.norm()
    if norm > 0:
        embedding = embedding / norm

    return {"embedding": embedding.tolist()}
```

Deploy the updated Modal app:
```bash
modal deploy app/worker/modal_inference.py
```

After deployment, Modal will print the URL of the new endpoint.
Copy the URL and add it to your `.env` file:
```env
MODAL_ENDPOINT_TEXT_EMBED=https://your-modal-org--vestimate-inference-text-embed.modal.run
```

Add `MODAL_ENDPOINT_TEXT_EMBED: str` to `app/core/config.py` Settings class.

**GATE 3:**
```bash
python -c "
import httpx, os, json
from dotenv import load_dotenv
load_dotenv()
url = os.getenv('MODAL_ENDPOINT_TEXT_EMBED')
r = httpx.post(url, json={'text': 'business casual outfit for rain'}, timeout=30)
data = r.json()
emb = data['embedding']
print(f'Status: {r.status_code}')
print(f'Embedding length: {len(emb)}')
print(f'First 3 values: {emb[:3]}')
"
```
Expected:
```
Status: 200
Embedding length: 512
First 3 values: [<float>, <float>, <float>]
```

---

## Step 4 — Context Aggregator

Create `app/services/context_aggregator.py`:

```python
"""
Context Aggregator for the Recommendation Engine.

Fetches external signals (weather, calendar) and normalizes them
into a RecommendationContext object. All external calls are wrapped
in try/except so a failure in one signal never blocks the whole request.
"""

import httpx
import os
from datetime import datetime, timezone
from app.models.recommendation_schemas import (
    RecommendationContext,
    WeatherData,
    ScheduleEvent,
)
from app.core.config import settings

# ── Formality keyword classifier ──────────────────────────────────────────────
# Maps keywords in event titles to formality levels.
# Order matters — more specific keywords first.
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

            # Map OpenWeatherMap condition codes to our 5-category system
            if condition_id < 600:      # 2xx thunderstorm, 3xx drizzle, 5xx rain
                condition = "rain"
            elif condition_id < 700:    # 6xx snow
                condition = "snow"
            elif condition_id < 800:    # 7xx atmosphere (fog, mist, etc.)
                condition = "cloudy"
            elif condition_id == 800:   # exactly 800 = clear
                condition = "clear"
            else:                       # 80x clouds
                condition = "cloudy"

            return WeatherData(
                temp_celsius=round(temp, 1),
                condition=condition,
                wind_kmh=round(wind * 3.6, 1),  # m/s → km/h
                temp_band="cold" if temp < 10 else "warm" if temp > 20 else "mild",
            )

    except Exception:
        return default


# ── Calendar fetch ────────────────────────────────────────────────────────────

async def get_calendar_events(oauth_token: str | None) -> list[ScheduleEvent]:
    """
    Fetches today's Google Calendar events via OAuth token.
    Returns empty list if no token or any failure — never raises.
    Calendar is optional; its absence degrades gracefully.
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
                if start:
                    time_str = start[11:16]  # extract HH:MM
                else:
                    time_str = "09:00"

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
    """
    Entry point for the context aggregation step.
    Runs weather and calendar fetches and composes the context object.
    """
    weather = await get_weather(city)
    events = await get_calendar_events(oauth_token)

    now = datetime.now()
    date_str = now.strftime("%Y-%m-%d")
    day_of_week = now.strftime("%A")
    time_of_day = _get_time_of_day(now.hour)

    # Derive primary formality from the most formal upcoming event
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
    """
    Converts the RecommendationContext into a natural language string
    suitable for the FashionCLIP text encoder.
    This string is what gets embedded into the 512-dim query vector.
    """
    top_event = context.schedule[0].title if context.schedule else "daily activities"
    return (
        f"{context.primary_formality.replace('_', ' ')} outfit for "
        f"{context.weather.condition} weather at {context.weather.temp_celsius}°C, "
        f"{context.day_of_week} {context.time_of_day}, "
        f"event: {top_event}"
    )


def compute_weather_bucket(context: RecommendationContext) -> str:
    """
    Produces a short, deterministic string used as part of the Redis
    cache key. Two requests with the same date + temp_band + condition
    will hit the same cache entry.
    """
    return f"{context.weather.temp_band}_{context.weather.condition}"
```

**GATE 4:**
```bash
python -c "
import asyncio
from app.services.context_aggregator import (
    classify_formality, build_occasion_string, compute_weather_bucket
)
from app.models.recommendation_schemas import (
    RecommendationContext, WeatherData
)
ctx = RecommendationContext(
    weather=WeatherData(temp_celsius=14, condition='rain', temp_band='mild'),
    schedule=[],
    date='2025-07-15',
    day_of_week='Tuesday',
    time_of_day='morning',
    primary_formality='casual'
)
print(classify_formality('Business Lunch'))
print(build_occasion_string(ctx))
print(compute_weather_bucket(ctx))
"
```
Expected:
```
business_casual
casual outfit for rain weather at 14.0°C, Tuesday morning, event: daily activities
mild_rain
```

---

## Step 5 — Vector Service

Create `app/services/vector_service.py`:

```python
"""
Vector Service — Query Vector Construction

Builds the 512-dim query vector by calling the FashionCLIP text encoder
on Modal. This vector is used for cosine similarity search against the
stored garment embeddings in pgvector.

Design note:
  Stored embeddings → FashionCLIP IMAGE encoder (in worker/tasks.py)
  Query vector      → FashionCLIP TEXT encoder (this file, via Modal)
  Both produce 512-dim L2-normalized vectors in the same latent space.
  Cosine similarity between them is therefore semantically valid.
"""

import httpx
import json
import redis
from app.core.config import settings

# ── Dedicated Redis client for vector cache ───────────────────────────────────
# Separate from the Celery broker client in celery_app.py.
# Uses database index 1 to avoid key collisions with Celery (index 0).
_vector_cache = redis.Redis.from_url(
    settings.REDIS_URL.replace("/0", "/1"), decode_responses=False
)

VECTOR_CACHE_TTL = 3600  # 1 hour


async def get_query_vector(occasion_text: str) -> list[float]:
    """
    Returns a 512-dim query vector for the given occasion text.

    Cache strategy: The same occasion string (same context) within
    a 1-hour window returns the cached vector. This avoids redundant
    Modal calls when multiple users have similar contexts.

    Cache key: vec:{hash of occasion_text}
    """
    import hashlib

    cache_key = f"vec:{hashlib.sha256(occasion_text.encode()).hexdigest()[:16]}"

    # Try cache first
    cached = _vector_cache.get(cache_key)
    if cached:
        return json.loads(cached)

    # Call Modal text encoder
    try:
        async with httpx.AsyncClient(timeout=25.0) as client:
            response = await client.post(
                settings.MODAL_ENDPOINT_TEXT_EMBED,
                json={"text": occasion_text},
            )
            response.raise_for_status()
            embedding = response.json()["embedding"]

        # Cache the result
        _vector_cache.setex(cache_key, VECTOR_CACHE_TTL, json.dumps(embedding))
        return embedding

    except Exception as e:
        # On failure: return zero vector — retrieval will fall back to
        # recency-based ordering (Step 6 handles this gracefully)
        import logging
        logging.getLogger(__name__).error(
            f"Vector encoding failed for '{occasion_text[:50]}...': {e}"
        )
        return [0.0] * 512
```

**GATE 5:**
```bash
python -c "
import asyncio
from app.services.vector_service import get_query_vector
vec = asyncio.run(get_query_vector('business casual outfit for rain at 14C Tuesday morning'))
print(f'Vector length: {len(vec)}')
print(f'Is non-zero: {any(v != 0.0 for v in vec)}')
print(f'Sample values: {vec[:3]}')
"
```
Expected:
```
Vector length: 512
Is non-zero: True
Sample values: [<float>, <float>, <float>]
```

---

## Step 6 — Retrieval Service

Create `app/services/retrieval.py`:

```python
"""
Retrieval Service — Category-Split pgvector Candidate Retrieval

Executes three parallel cosine similarity queries against the
wardrobe_items table — one per required outfit category (top,
bottom, shoes). Returns up to 5 candidates per category.

Uses raw SQL via asyncpg for the vector similarity operator (<=>).
The supabase-py REST client does not support this operator.
"""

import asyncpg
from app.core.config import settings
from app.models.recommendation_schemas import GarmentCandidate, CandidateSet

CATEGORIES = ["top", "bottom", "shoes"]
CANDIDATES_PER_CATEGORY = 5
RECENCY_DAYS = 7


async def _get_db_connection() -> asyncpg.Connection:
    """Creates a single-use asyncpg connection for a query."""
    return await asyncpg.connect(settings.SUPABASE_DATABASE_URL)


async def get_candidates(
    user_id: str,
    query_vector: list[float],
) -> CandidateSet:
    """
    Retrieves outfit candidates from pgvector for all three categories.

    For each category:
      1. Run cosine similarity search filtered by user + category + recency
      2. If 0 results (user has nothing in that category), fall back to
         top-5 by last_worn_at DESC (no vector filter)

    The query_vector may be a zero vector (if text encoding failed).
    In that case, the ORDER BY embedding <=> :vec still executes but
    returns arbitrary ordering — which is acceptable, the LLM still
    gets valid candidates.
    """

    # Build pgvector-compatible array string: '[0.023, -0.114, ...]'
    vec_str = "[" + ",".join(str(v) for v in query_vector) + "]"

    results: dict[str, list[GarmentCandidate]] = {
        "top": [], "bottom": [], "shoes": []
    }

    conn = await _get_db_connection()
    try:
        for category in CATEGORIES:
            # Primary query: vector similarity + recency filter
            rows = await conn.fetch(
                f"""
                SELECT id, image_url, category, material, fit, colors
                FROM wardrobe_items
                WHERE user_id = $1
                  AND status = 'active'
                  AND category = $2
                  AND (
                    last_worn_at IS NULL
                    OR last_worn_at < NOW() - INTERVAL '{RECENCY_DAYS} days'
                  )
                ORDER BY embedding <=> $3::vector
                LIMIT {CANDIDATES_PER_CATEGORY}
                """,
                user_id,
                category,
                vec_str,
            )

            # Fallback: if no results, relax recency filter
            if not rows:
                rows = await conn.fetch(
                    f"""
                    SELECT id, image_url, category, material, fit, colors
                    FROM wardrobe_items
                    WHERE user_id = $1
                      AND status = 'active'
                      AND category = $2
                    ORDER BY last_worn_at DESC NULLS LAST
                    LIMIT {CANDIDATES_PER_CATEGORY}
                    """,
                    user_id,
                    category,
                )

            for row in rows:
                results[category].append(
                    GarmentCandidate(
                        id=str(row["id"]),
                        image_url=row["image_url"],
                        category=row["category"],
                        material=row["material"],
                        fit=row["fit"],
                        colors=list(row["colors"]) if row["colors"] else [],
                    )
                )

    finally:
        await conn.close()

    return CandidateSet(
        tops=results["top"],
        bottoms=results["bottom"],
        shoes=results["shoes"],
    )


def has_sufficient_candidates(candidates: CandidateSet) -> bool:
    """
    Returns True only if all three categories have at least 1 candidate.
    If False, the endpoint returns 404 with code: insufficient_wardrobe.
    """
    return (
        len(candidates.tops) > 0
        and len(candidates.bottoms) > 0
        and len(candidates.shoes) > 0
    )
```

**GATE 6:**
```bash
python -c "
import asyncio
from app.services.retrieval import get_candidates, has_sufficient_candidates
# Use a real user_id that has garments in your Supabase DB.
# If none exist yet, this will return empty sets — that is expected
# and has_sufficient_candidates will return False (correct behavior).
candidates = asyncio.run(get_candidates('test-user-id', [0.0] * 512))
print(f'Tops: {len(candidates.tops)}')
print(f'Bottoms: {len(candidates.bottoms)}')
print(f'Shoes: {len(candidates.shoes)}')
print(f'Sufficient: {has_sufficient_candidates(candidates)}')
"
```
Expected: No exception. Prints counts (may be 0 if DB is empty — that is correct).

---

## Step 7 — LLM Service

Create `app/services/llm_service.py`:

```python
"""
LLM Service — GPT-4o-mini Outfit Selection

Fetches the active prompt from Supabase prompt_versions table,
calls GPT-4o-mini with structured output (JSON Schema mode),
validates the response with Pydantic, and returns either a valid
OutfitSelection or falls back to heuristic selection.

Structured outputs are enforced at the OpenAI API level —
the model cannot return malformed JSON when response_format
is set to json_schema.
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
    Returns (system_prompt, user_prompt_template).
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
    a hallucinated item ID. Selects the first candidate in each category
    (already ranked by vector similarity from the retrieval step).
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

    Returns:
        (OutfitSelection, fallback_used: bool)

    The fallback flag is stored in the DB and used for analytics —
    high fallback rate signals prompt or retrieval quality issues.
    """
    try:
        system_prompt, _ = _get_active_prompt()
        candidates_payload = _build_candidates_payload(candidates)

        user_message = json.dumps({
            "context": {
                "weather": f"{context.weather.condition} at {context.weather.temp_celsius}°C",
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

        # Cross-reference: all IDs must exist in the candidate set we sent
        if not parsed.validate_against_candidates(candidates):
            logger.error(
                f"GPT returned hallucinated item IDs: "
                f"top={parsed.top_id}, bottom={parsed.bottom_id}, "
                f"shoe={parsed.shoe_id}"
            )
            return _heuristic_fallback(candidates), True

        return parsed, False

    except Exception as e:
        logger.error(f"LLM selection failed: {e}")
        return _heuristic_fallback(candidates), True
```

**GATE 7:**
```bash
python -c "
from app.services.llm_service import _get_active_prompt, _heuristic_fallback
from app.models.recommendation_schemas import (
    GarmentCandidate, CandidateSet
)

# Test 1: prompt loads from DB
system_prompt, template = _get_active_prompt()
print(f'Prompt loaded: {system_prompt[:60]}...')

# Test 2: heuristic fallback works
candidates = CandidateSet(
    tops=[GarmentCandidate(id='top-1', category='top')],
    bottoms=[GarmentCandidate(id='bot-1', category='bottom')],
    shoes=[GarmentCandidate(id='shoe-1', category='shoes')],
)
result = _heuristic_fallback(candidates)
print(f'Fallback top_id: {result.top_id}')
print(f'Fallback note: {result.stylist_note}')
"
```
Expected: Prompt text prints, fallback returns `top-1`, `bot-1`, `shoe-1`.

---

## Step 8 — Recommendation Cache Service

Create `app/services/recommendation_cache.py`:

```python
"""
Recommendation Cache Service

Redis cache for daily outfit recommendations.
Uses a SEPARATE Redis client on database index 1.
  - Index 0: Celery broker (do not touch)
  - Index 1: Application cache (this file)

Cache key format: rec:{user_id}:{date}:{weather_bucket}
TTL: 4 hours (14400 seconds)

Eviction policy must be set in docker-compose.yml:
  command: redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru
"""

import json
import redis
from datetime import datetime
from app.core.config import settings

# Dedicated client — index 1, not index 0 (Celery)
_cache = redis.Redis.from_url(
    settings.REDIS_URL.replace("/0", "/1"),
    decode_responses=True,
)

CACHE_TTL = 14400  # 4 hours
KEY_PREFIX = "rec"


def build_cache_key(user_id: str, date: str, weather_bucket: str) -> str:
    return f"{KEY_PREFIX}:{user_id}:{date}:{weather_bucket}"


def get_cached_recommendation(cache_key: str) -> dict | None:
    """Returns deserialized recommendation or None if not cached."""
    raw = _cache.get(cache_key)
    if raw is None:
        return None
    return json.loads(raw)


def set_cached_recommendation(cache_key: str, recommendation: dict) -> None:
    """Stores recommendation with 4h TTL."""
    _cache.setex(cache_key, CACHE_TTL, json.dumps(recommendation))


def invalidate_user_cache(user_id: str) -> int:
    """
    Deletes all recommendation cache entries for a user.
    Called when a user submits 'worn' feedback — next app open
    generates a fresh recommendation that excludes worn items.
    Returns number of keys deleted.
    """
    pattern = f"{KEY_PREFIX}:{user_id}:*"
    keys = _cache.keys(pattern)
    if keys:
        return _cache.delete(*keys)
    return 0
```

**GATE 8:**
```bash
python -c "
from app.services.recommendation_cache import (
    build_cache_key, set_cached_recommendation,
    get_cached_recommendation, invalidate_user_cache
)
key = build_cache_key('user-123', '2025-07-15', 'mild_rain')
set_cached_recommendation(key, {'test': 'data', 'outfit': {}})
result = get_cached_recommendation(key)
print(f'Cache hit: {result}')
count = invalidate_user_cache('user-123')
print(f'Keys deleted: {count}')
result2 = get_cached_recommendation(key)
print(f'After invalidation: {result2}')
"
```
Expected:
```
Cache hit: {'test': 'data', 'outfit': {}}
Keys deleted: 1
After invalidation: None
```

---

## Step 9 — Recommendation Endpoint

Create `app/api/v1/endpoints/recommendations.py`:

```python
"""
Recommendation Endpoint — GET /v1/recommendations/today

Synchronous from the client's perspective.
Internally: cache check → context → vector → retrieval → LLM → cache write.
Target latency: < 100ms on cache hit, < 4s on cold path.
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
      1. Check Redis cache → return immediately on hit
      2. Aggregate context (weather + calendar)
      3. Build query vector via FashionCLIP text encoder
      4. Retrieve candidates from pgvector
      5. Call GPT-4o-mini to select outfit
      6. Validate, cache, and return

    The user's Google OAuth token is fetched from Supabase users table.
    If not present, calendar context is skipped gracefully.
    """

    # ── Step 1: Fetch user data (city override + oauth token) ─────────────────
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

    # ── Step 2: Build context (lightweight — only weather for bucket) ─────────
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
            "weather": f"{context.weather.temp_celsius}°C, {context.weather.condition}",
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
        # Insert into outfits table
        outfit_insert = _supabase.table("outfits").insert({
            "id": recommendation_id,
            "user_id": user_id,
            "top_id": selection.top_id,
            "bottom_id": selection.bottom_id,
            "shoe_id": selection.shoe_id,
            "stylist_note": selection.stylist_note,
            "source": "fallback" if fallback_used else "llm",
        }).execute()

        # Insert into recommendation_cache table (durable record)
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
        # DB write failure does not fail the request — user still gets recommendation
        import logging
        logging.getLogger(__name__).error(f"DB write failed for recommendation: {e}")

    # Write to Redis cache
    set_cached_recommendation(cache_key, response_data.model_dump())

    return response_data
```

---

## Step 10 — Feedback Endpoint

Create `app/api/v1/endpoints/feedback.py`:

```python
"""
Feedback Endpoint — POST /v1/feedback

Records user interaction with a recommendation.
On 'worn' action: updates last_worn_at for all outfit items
                  and busts the Redis recommendation cache.
"""

from datetime import datetime, timezone
from fastapi import APIRouter, HTTPException
from supabase import create_client

from app.core.config import settings
from app.models.recommendation_schemas import FeedbackRequest
from app.services.recommendation_cache import invalidate_user_cache

router = APIRouter()
_supabase = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)


@router.post(
    "/",
    status_code=204,
    summary="Submit feedback on a recommendation",
)
async def submit_feedback(
    user_id: str,
    payload: FeedbackRequest,
):
    """
    Records feedback and updates wardrobe state.

    - worn:   Sets last_worn_at on all items. Busts Redis cache so
              next recommendation excludes recently worn items.
    - skipped: Records event only. No state change.
    - saved:   Records event only. No state change.
    """

    # Write feedback event
    try:
        _supabase.table("feedback_events").insert({
            "user_id": user_id,
            "recommendation_id": payload.recommendation_id,
            "action": payload.action,
            "item_ids": payload.item_ids,
        }).execute()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to record feedback: {e}")

    # On 'worn': update last_worn_at and bust cache
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
            # Log but don't fail — feedback was already recorded
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
```

---

## Step 11 — Wire Routers

Open `app/api/v1/__init__.py`.
Add the two new routers. Do not remove existing routers.

```python
from fastapi import APIRouter
from app.api.v1.endpoints import wardrobe, tasks, recommendations, feedback

api_router = APIRouter()

# Existing routers — do not modify
api_router.include_router(wardrobe.router, prefix="/wardrobe", tags=["wardrobe"])
api_router.include_router(tasks.router, prefix="/tasks", tags=["tasks"])

# Phase 3 routers
api_router.include_router(
    recommendations.router,
    prefix="/recommendations",
    tags=["recommendations"],
)
api_router.include_router(
    feedback.router,
    prefix="/feedback",
    tags=["feedback"],
)
```

---

## Step 12 — Final Verification

Run the full test sequence in order. Every command must pass before the next.

**Test 1 — Server starts cleanly:**
```bash
uvicorn main:app --reload
```
Expected: No ImportError. Server starts on port 8000.

**Test 2 — New routes appear in OpenAPI:**
```bash
curl http://localhost:8000/docs
```
Expected: `/v1/recommendations/today` and `/v1/feedback/` appear in the docs page.

**Test 3 — Existing endpoints still work:**
```bash
curl http://localhost:8000/health
curl http://localhost:8000/v1/tasks/nonexistent-id
```
Expected: `{"status":"ok"}` and `404` respectively.

**Test 4 — Insufficient wardrobe returns correct error:**
```bash
curl "http://localhost:8000/v1/recommendations/today?user_id=test-empty-user&city=Yerevan"
```
Expected:
```json
{
  "detail": {
    "code": "insufficient_wardrobe",
    "message": "Add at least 1 top, 1 bottom, and 1 pair of shoes to receive a recommendation."
  }
}
```

**Test 5 — Full recommendation flow (requires user with garments in DB):**
```bash
curl "http://localhost:8000/v1/recommendations/today?user_id=YOUR_REAL_USER_ID&city=Yerevan"
```
Expected: HTTP 200 with outfit JSON containing `top`, `bottom`, `shoes` objects.

**Test 6 — Second request hits cache:**
Run Test 5 again immediately.
Expected: Same response with `"cache_hit": true`.

**Test 7 — Feedback endpoint works:**
```bash
curl -X POST "http://localhost:8000/v1/feedback/?user_id=YOUR_REAL_USER_ID" \
  -H "Content-Type: application/json" \
  -d '{
    "recommendation_id": "RECOMMENDATION_ID_FROM_TEST_5",
    "action": "worn",
    "item_ids": ["TOP_ID", "BOTTOM_ID", "SHOE_ID"]
  }'
```
Expected: HTTP 204 No Content.

**Test 8 — Cache busted after worn feedback:**
Run Test 5 again after Test 7.
Expected: `"cache_hit": false` (new recommendation generated).

**Test 9 — Verify DB records:**
```bash
python -c "
from supabase import create_client
import os
from dotenv import load_dotenv
load_dotenv()
client = create_client(os.getenv('SUPABASE_URL'), os.getenv('SUPABASE_SERVICE_KEY'))
outfits = client.table('outfits').select('id,source').limit(3).execute()
feedback = client.table('feedback_events').select('action').limit(3).execute()
cache = client.table('recommendation_cache').select('cache_key,fallback_used').limit(3).execute()
print('Outfits:', outfits.data)
print('Feedback:', feedback.data)
print('Cache records:', cache.data)
"
```
Expected: Records in all three tables.

---

## Definition of Done — Phase 3

Do not mark Phase 3 complete until every box below is checked.

```
═══════════════════════════════════════════════════════════════
PHASE 3 — DONE WHEN ALL OF THE FOLLOWING ARE TRUE:
═══════════════════════════════════════════════════════════════

[ ] Server starts with no ImportError or startup exception
[ ] GET /v1/recommendations/today returns 404 for user with
    no garments (code: insufficient_wardrobe)
[ ] GET /v1/recommendations/today returns 200 with valid outfit
    JSON for a user with at least 1 item per category
[ ] Response contains: recommendation_id, outfit.top, outfit.bottom,
    outfit.shoes, stylist_note, cache_hit, fallback_used
[ ] Second identical request returns cache_hit: true
[ ] POST /v1/feedback with action: "worn" returns 204
[ ] After worn feedback, next recommendation returns cache_hit: false
[ ] outfits table has at least 1 row after a successful recommendation
[ ] recommendation_cache table has at least 1 row
[ ] feedback_events table has at least 1 row after feedback call
[ ] wardrobe_items.last_worn_at updated after worn feedback
[ ] All Phase 2 endpoints still work (wardrobe upload, task poll)

═══════════════════════════════════════════════════════════════
PHASE 3 IS COMPLETE ONLY WHEN ALL 12 BOXES ARE CHECKED.
DO NOT BEGIN PHASE 4 UNTIL EVERY BOX IS CHECKED.
═══════════════════════════════════════════════════════════════
```

---

## What Phase 4 Will Add (Do Not Build Now)

```
Phase 4:
- JWT middleware (Supabase Auth) protecting all routes
- Replace raw user_id query param with JWT-extracted user_id
- GET /v1/wardrobe/items (paginated wardrobe read endpoint)
- DELETE /v1/wardrobe/items/{item_id}
- SHA-256 deduplication check on upload
- Async R2 upload (move out of sync FastAPI handler)
- Sentry error tracking
- Structured logging (Logfire)
- Prometheus metrics endpoint
```

---

**"Phase 3 implementation is ready.**
**All files written. All gates defined.**
**Run: uvicorn main:app --reload"**
