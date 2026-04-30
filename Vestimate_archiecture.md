# VESTIMATE — Production System Architecture
**Document Type:** Internal Engineering Architecture Reference  
**Version:** 1.0.0  
**Status:** Finalized  
**Audience:** Engineering Team  

---

## Table of Contents

1. [Overview](#1-overview)
2. [High-Level Architecture](#2-high-level-architecture)
3. [Architecture Diagram](#3-architecture-diagram)
4. [Detailed Data Flow](#4-detailed-data-flow)
5. [Tech Stack](#5-tech-stack)
6. [APIs & Service Contracts](#6-apis--service-contracts)
7. [Data Model](#7-data-model)
8. [Infrastructure & Deployment](#8-infrastructure--deployment)
9. [Security](#9-security)
10. [Scalability & Reliability](#10-scalability--reliability)
11. [Assumptions & Edge Cases](#11-assumptions--edge-cases)

---

## 1. Overview

### 1.1 System Purpose

VESTIMATE is a mobile-first AI wardrobe assistant. Users photograph their clothing, and the system automatically digitizes, categorizes, and stores it. On each app session, the system assembles a contextually-aware outfit recommendation by synthesizing the user's closet state, real-time weather, and calendar schedule — presenting it as a visual outfit card with a one-sentence stylist rationale. The user never interacts with a chatbot; the AI operates invisibly as a background reasoning layer.

### 1.2 Goals

| Priority | Goal | Metric |
|---|---|---|
| P0 | Outfit recommendation latency < 1.5s (cache hit) | p95 response time |
| P0 | Wardrobe item ingestion completes < 10s per item (async) | Celery task duration |
| P0 | FashionCLIP tagging accuracy ≥ 85% on real-world wardrobe photos | Offline eval set |
| P1 | System handles 150 concurrent users in Alpha without degradation | Load test |
| P1 | OpenAI API call rate < 20% of total recommendation requests (cache absorbs 80%) | Cache hit ratio |
| P2 | Full observability: every request traceable end-to-end | Trace coverage |

### 1.3 Constraints

- **Team size:** Small (2–4 engineers). Architecture must minimize operational overhead.
- **Alpha budget:** ≤ $200/month for 150 users.
- **Mobile clients:** iOS and Android. Backend is the source of truth for all logic.
- **No real-time streaming:** Recommendations are pull-based (triggered on app open). Push notifications are deferred.
- **Data residency:** No strict constraint for Alpha. GDPR-awareness required for EU expansion (deferred).
- **LLM dependency:** GPT-4o-mini is the designated model. No self-hosting in Alpha.
- **No GPU on primary API server.** ML inference runs on ephemeral on-demand GPU workers (Modal.com).

---

## 2. High-Level Architecture

### 2.1 Service Decomposition

The system is composed of six logical services. In Alpha, services 1–3 run as a monorepo on a single Railway deployment. Services are separated by code module boundaries, not network boundaries, to reduce infra overhead. They are designed to be extracted into independent microservices post-PMF.

---

#### Service 1: API Gateway (FastAPI)

**Responsibility:** The single entry point for all mobile client traffic. Handles authentication verification, request validation, rate limiting, and routing to downstream handlers.

**Does NOT contain:**
- Business logic
- ML inference
- Direct DB writes outside of fast-path operations

**Exposes:**
- `POST /v1/wardrobe/upload` → routes to Ingestion Worker via task queue
- `GET /v1/recommendations/today` → routes to Recommendation Engine
- `POST /v1/feedback` → direct write to Supabase
- `GET /v1/wardrobe/items` → direct read from Supabase
- `GET /v1/tasks/{task_id}` → polls Celery task status from Redis

---

#### Service 2: Ingestion Worker (Celery + Modal)

**Responsibility:** All asynchronous processing triggered by a wardrobe item upload. This is the ML pipeline. It runs as a Celery worker process, with the heavy inference steps (rembg, FashionCLIP) offloaded to Modal.com GPU functions via HTTP.

**Pipeline steps (in order):**
1. Download image from Cloudflare R2 using the `object_key` from the task payload
2. Call Modal function: rembg background removal → receive PNG with alpha channel
3. Call Modal function: FashionCLIP embed + tag → receive embedding vector + tag dict
4. Confidence gate: if max tag confidence < 0.70, set `needs_review = true` and enqueue in `manual_review_queue`
5. Map colors to canonical 32-color palette (deterministic, no GPU needed)
6. Upsert embedding into pgvector (Supabase)
7. Write metadata record into `wardrobe_items` table (Supabase)
8. Set task status to `COMPLETE` in Redis
9. Emit a `wardrobe.item.ingested` event to the event log table

---

#### Service 3: Recommendation Engine

**Responsibility:** Assembles and returns the outfit recommendation for the current user session. This is the core product logic. It is synchronous from the client's perspective (request → response), but internally calls multiple services.

**Steps (detailed in Section 4):**
1. Check Redis recommendation cache (key: `rec:{user_id}:{date}:{weather_bucket}`)
2. On cache miss: aggregate context (weather + calendar)
3. Build structured query vector from context
4. Retrieve candidates from pgvector (category-split retrieval)
5. Apply SQL-layer recency filter
6. Call GPT-4o-mini with structured prompt
7. Validate LLM response with Pydantic schema
8. Cache result and return

---

#### Service 4: ML Inference Layer (Modal.com)

**Responsibility:** Stateless, on-demand GPU functions. Invoked via HTTP from the Celery worker. Each function loads its model from a cached container image (Modal persists the model weights in the container, eliminating cold-start model download).

**Functions:**
- `POST /inference/segment` — rembg (U-2-Net). Input: raw image bytes. Output: PNG bytes (background removed).
- `POST /inference/embed_and_tag` — FashionCLIP. Input: PNG bytes. Output: `{ embedding: float[512], tags: {category, material, fit, confidence_scores} }`.

**Why Modal and not a persistent GPU server:** At Alpha scale, garment uploads are sporadic. A persistent GPU VM running 24/7 at $0.50–1.00/hr would cost $360–720/month for ~5% utilization. Modal bills per-second of actual execution. At 150 users uploading an average of 100 items total during Alpha, the GPU inference cost is negligible (<$5).

---

#### Service 5: Context Aggregator (internal module, called by Recommendation Engine)

**Responsibility:** Fetches and normalizes external context signals.

**Inputs:**
- OpenWeatherMap API: current conditions for user's stored city
- Google Calendar API (OAuth): next 3 events within 24 hours, with title and time

**Output:** A normalized `RecommendationContext` object:
```json
{
  "weather": {
    "temp_celsius": 14,
    "condition": "rain",
    "wind_kmh": 12
  },
  "schedule": [
    { "title": "Business Lunch", "start_time": "13:00", "formality": "business_casual" }
  ],
  "date": "2025-07-15",
  "day_of_week": "Tuesday",
  "time_of_day": "morning"
}
```

The `formality` field is derived by the Context Aggregator itself using a simple keyword classifier (not an LLM call) that maps event titles to one of: `casual`, `business_casual`, `formal`, `athletic`, `unknown`.

---

#### Service 6: Observability Stack

**Responsibility:** Cross-cutting concern. Every service emits structured logs, metrics, and traces.

**Components:**
- **Sentry:** Exception capture and error tracking across FastAPI and Celery workers
- **Logfire (Pydantic):** Structured JSON logs with automatic FastAPI + Celery instrumentation
- **OpenTelemetry:** Distributed trace context propagated via HTTP headers across all internal service calls, including Modal invocations
- **Prometheus + Grafana Cloud:** Metrics scraping from FastAPI (via `prometheus-fastapi-instrumentator`) and Celery (via `celery-prometheus-exporter`)

---

## 3. Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                                 MOBILE CLIENT                                        │
│                         (React Native — iOS & Android)                               │
└───────────────────────────────────────┬──────────────────────────────────────────────┘
                                        │ HTTPS / REST
                                        ▼
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                              API GATEWAY  [Railway]                                  │
│                                 (FastAPI)                                            │
│                                                                                      │
│   ┌─────────────┐   ┌──────────────────┐   ┌───────────────┐   ┌─────────────────┐  │
│   │  JWT Auth   │   │  Rate Limiter    │   │  Pydantic     │   │  OpenTelemetry  │  │
│   │  Middleware │   │  (slowapi/Redis) │   │  Validation   │   │  Instrumentation│  │
│   └─────────────┘   └──────────────────┘   └───────────────┘   └─────────────────┘  │
└──────┬──────────────────────────┬─────────────────────────────────────────────────────┘
       │                          │
       │ Async (task enqueue)     │ Sync (HTTP)
       ▼                          ▼
┌─────────────────┐    ┌─────────────────────────────────────────────────────────────┐
│  REDIS          │    │              RECOMMENDATION ENGINE  [Railway]               │
│  [Upstash]      │◄───│                    (Python module)                          │
│                 │    │                                                             │
│  - Task queue   │    │  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐    │
│  - Task status  │    │  │   Cache     │  │   Context    │  │  LLM Selector  │    │
│  - Rec cache    │    │  │   Check     │  │   Aggregator │  │  (GPT-4o-mini) │    │
│  - Rate limit   │    │  │  (Redis)    │  │              │  │                │    │
│  - Session state│    │  └──────┬──────┘  └──────┬───────┘  └───────┬────────┘    │
└────────┬────────┘    │         │                 │                  │             │
         │             │         ▼                 ▼                  ▼             │
         │             │  ┌───────────────────────────────────────────────────┐    │
         │             │  │             pgvector Query Layer                  │    │
         │             │  │     (category-split retrieval + recency filter)   │    │
         │             │  └───────────────────────────────────────────────────┘    │
         │             └──────────────────────────────────────────────────────────-┘
         │                                         │
         ▼                                         │ SQL + pgvector
┌────────────────────────────────────────┐         ▼
│   INGESTION WORKER  [Railway]          │  ┌───────────────────────────────────────┐
│   (Celery)                             │  │          SUPABASE (PostgreSQL)        │
│                                        │  │                                       │
│   1. Download image from R2            │  │  Tables:                              │
│   2. → Modal: rembg segment            │  │  - users                              │
│   3. → Modal: FashionCLIP embed+tag    │◄─│  - wardrobe_items                     │
│   4. Confidence gate (< 0.70 → review) │  │  - outfits                            │
│   5. Color palette mapping             │  │  - feedback_events                    │
│   6. Upsert pgvector embedding         │  │  - recommendation_cache               │
│   7. Write metadata to Supabase        │  │  - prompt_versions                    │
│   8. Emit ingestion event              │  │  - manual_review_queue                │
└───────────────┬────────────────────────┘  │                                       │
                │ HTTP (per task)            │  Extensions:                          │
                ▼                            │  - pgvector (embeddings)              │
┌───────────────────────────────────────┐   │  - pg_cron (cache eviction jobs)      │
│        MODAL.COM  (GPU Workers)       │   └───────────────────────────────────────┘
│                                       │
│  ┌─────────────────────────────────┐  │   ┌───────────────────────────────────────┐
│  │  Function: /inference/segment   │  │   │        CLOUDFLARE R2                  │
│  │  Model: rembg (U-2-Net)         │  │   │  - Raw upload images                  │
│  │  Runtime: Python, GPU T4        │  │   │  - Segmented PNGs                     │
│  └─────────────────────────────────┘  │   │  - Served via Cloudflare CDN          │
│  ┌─────────────────────────────────┐  │   │    (zero egress cost)                 │
│  │  Function: /inference/embed_tag │  │   └───────────────────────────────────────┘
│  │  Model: FashionCLIP (ViT-B/16)  │  │
│  │  Runtime: Python, GPU T4        │  │   ┌───────────────────────────────────────┐
│  └─────────────────────────────────┘  │   │     EXTERNAL APIs                     │
└───────────────────────────────────────┘   │  - OpenWeatherMap                     │
                                            │  - Google Calendar (OAuth 2.0)        │
                                            │  - OpenAI (GPT-4o-mini)               │
                                            └───────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────────────┐
│                          OBSERVABILITY PLANE (Cross-cutting)                         │
│   Sentry (errors) │ Logfire (structured logs) │ Prometheus+Grafana (metrics)         │
│   OpenTelemetry distributed traces across: API Gateway → Celery → Modal → Supabase  │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Detailed Data Flow

### Flow A: Wardrobe Item Ingestion (Async)

This flow is triggered when a user uploads a photo of a garment from the mobile app.

```
Step 1: Client Upload
  - Mobile client: captures photo, compresses to max 1920px (client-side)
  - Client sends: POST /v1/wardrobe/upload
    Payload: { image: base64_string, user_id: UUID }
  - API Gateway:
      - Validates JWT → extracts user_id
      - Validates payload schema (Pydantic)
      - Generates object_key = f"raw/{user_id}/{uuid4()}.jpg"
      - Uploads image bytes directly to Cloudflare R2 using presigned URL
        (API server streams bytes to R2 — does NOT hold in memory beyond this)
      - Enqueues Celery task: ingest_garment(user_id, object_key, item_id)
      - Writes stub record to wardrobe_items:
          { id: item_id, user_id, status: "processing", created_at }
      - Returns 202 Accepted: { task_id, item_id }

Step 2: Client Polling
  - Client polls: GET /v1/tasks/{task_id} every 3 seconds
  - API Gateway reads task status from Redis (set by Celery worker)
  - Returns: { status: "pending" | "processing" | "complete" | "failed", item_id }

Step 3: Celery Worker — Background Removal
  - Worker picks up task from Redis queue
  - Sets task status → "processing" in Redis
  - Downloads image from R2 (signed GET, valid 60s)
  - HTTP POST to Modal function /inference/segment:
      Body: raw image bytes (multipart)
      Returns: PNG bytes (alpha-masked, background removed)
  - Uploads segmented PNG to R2: f"segmented/{user_id}/{item_id}.png"

Step 4: Celery Worker — Embedding & Tagging
  - HTTP POST to Modal function /inference/embed_and_tag:
      Body: segmented PNG bytes
      Returns:
      {
        "embedding": [0.023, -0.114, ...],  // float[512], L2-normalized
        "tags": {
          "category": { "value": "outerwear", "confidence": 0.91 },
          "material": { "value": "wool", "confidence": 0.74 },
          "fit": { "value": "relaxed", "confidence": 0.68 },
          "colors": ["navy", "charcoal"]  // mapped to 32-color palette
        }
      }

Step 5: Confidence Gate
  - Compute min_confidence = min(category.confidence, material.confidence, fit.confidence)
  - If min_confidence < 0.70:
      - Set wardrobe_items.needs_review = true
      - Insert into manual_review_queue table: { item_id, user_id, tags_raw }
      - Item is still stored and usable; low-confidence tags are flagged
  - Continue regardless — system never blocks on review

Step 6: Data Persistence
  - pgvector upsert (Supabase):
      UPDATE wardrobe_items
      SET embedding = '[0.023, -0.114, ...]'::vector(512)
      WHERE id = item_id
  - Supabase metadata update:
      UPDATE wardrobe_items SET
        status = 'active',
        category = 'outerwear',
        material = 'wool',
        fit = 'relaxed',
        colors = ['navy', 'charcoal'],
        confidence_min = 0.68,
        needs_review = false,
        image_url = 'https://cdn.vestimate.app/segmented/{user_id}/{item_id}.png',
        processed_at = NOW()
      WHERE id = item_id

Step 7: Completion
  - Redis task status → "complete"
  - Insert into event_log: { event_type: "wardrobe.item.ingested", user_id, item_id }
  - Client poll returns "complete" → app fetches updated item and displays it
```

---

### Flow B: Outfit Recommendation (Sync, Cache-First)

This flow is triggered every time the user opens the app. Target latency: < 1.5s on cache hit, < 4s on cache miss.

```
Step 1: Client Request
  - GET /v1/recommendations/today
  - Headers: Authorization: Bearer <jwt>

Step 2: Cache Check
  - API Gateway extracts user_id from JWT
  - Calls Context Aggregator (lightweight): fetch weather for user's city
  - Compute weather_bucket from current conditions:
      weather_bucket = hash(date + temp_band + condition_category)
      // temp_band: "cold"(<10°C), "mild"(10-20°C), "warm"(>20°C)
      // condition_category: "rain", "clear", "snow", "cloudy"
  - Cache key = f"rec:{user_id}:{date}:{weather_bucket}"
  - Redis GET cache_key
  - If HIT and TTL > 0:
      → Return cached recommendation immediately
      → Log cache hit metric
      → DONE (sub-100ms response)

Step 3: Context Aggregation (on cache miss)
  - Fetch full weather object from OpenWeatherMap API
  - Fetch Google Calendar events (next 24h) via OAuth token from Supabase
  - Apply keyword classifier to event titles → derive formality score
  - Build RecommendationContext object (see Section 2.5)

Step 4: Query Vector Construction
  - This is the resolved design decision from the architectural review:
    The query vector is NOT a garment embedding.
    It is a TEXT embedding of a natural-language occasion description.
  - Construct occasion string:
      occasion_text = f"{formality} outfit for {condition} weather at {temp_celsius}°C,
                       {day_of_week} {time_of_day}, event: {event_title}"
      // Example: "business casual outfit for rain at 14°C, Tuesday morning,
      //           event: Business Lunch"
  - Embed occasion_text using OpenAI text-embedding-3-small (1536 dims, truncated to 512)
    NOTE: FashionCLIP embeddings are 512-dim. OpenAI embeddings are truncated to match.
    This is architecturally acceptable because the pgvector cosine similarity search
    operates in the same 512-dim space, and the semantic alignment of "occasion description"
    to "garment style" is the core retrieval signal we want.
  - Cache this query vector in Redis with 1h TTL keyed on occasion_text hash
    (avoids re-embedding the same occasion multiple times per day)

Step 5: Category-Split pgvector Retrieval
  - Execute 3 parallel queries against Supabase pgvector, one per required category:
    For each category in ['top', 'bottom', 'shoes']:
      SELECT id, image_url, category, material, fit, colors, last_worn_at
      FROM wardrobe_items
      WHERE user_id = :user_id
        AND status = 'active'
        AND category = :category
        AND (last_worn_at IS NULL OR last_worn_at < NOW() - INTERVAL '7 days')
      ORDER BY embedding <=> :query_vector  -- cosine distance
      LIMIT 5
  - Result: up to 15 candidate items (5 per category)
  - If any category returns 0 items (e.g. user has no shoes scanned):
      → Fill that slot with top-5 by last_worn_at DESC (recency fallback, no vector filter)

Step 6: LLM Outfit Selection
  - Build GPT-4o-mini prompt from versioned template:
      System: "You are a professional stylist. Select one complete outfit.
               Return ONLY valid JSON matching the provided schema.
               Do not explain or add commentary outside the JSON."
      User: {
        "context": <RecommendationContext>,
        "candidates": {
          "tops": [{ id, category, material, fit, colors }, ...],
          "bottoms": [...],
          "shoes": [...]
        }
      }
  - OpenAI call parameters:
      model: "gpt-4o-mini"
      temperature: 0.3  // low for consistency, slight variation for novelty
      max_tokens: 200
      response_format: { type: "json_schema", json_schema: OutfitSelectionSchema }
      // Structured outputs enforced at the API level — model cannot return malformed JSON

  - Expected response:
      {
        "top_id": "uuid",
        "bottom_id": "uuid",
        "shoe_id": "uuid",
        "stylist_note": "string (max 120 chars)"
      }

Step 7: Response Validation
  - Validate response with Pydantic OutfitSelection model:
      - All three IDs must exist in the candidates list passed in the prompt
        (cross-reference in Python — this is NOT left to the LLM)
      - stylist_note must be non-empty, ≤ 120 characters
  - If validation fails (e.g. hallucinated ID):
      - Log Sentry error with full prompt + response
      - Execute FALLBACK: select top-1 per category by vector similarity score
        (no LLM, pure retrieval result)
      - Mark recommendation as fallback=true in cache record

Step 8: Cache Write & Response
  - Write to Redis:
      Key: f"rec:{user_id}:{date}:{weather_bucket}"
      Value: serialized OutfitRecommendation JSON
      TTL: 4 hours (14400s)
  - Write to recommendation_cache table in Supabase (for feedback join, analytics)
  - Return to client:
      {
        "recommendation_id": "uuid",
        "outfit": {
          "top": { "id", "image_url", "category", "material", "fit", "colors" },
          "bottom": { ... },
          "shoes": { ... }
        },
        "stylist_note": "Chose the trench coat for rain protection...",
        "generated_at": "ISO8601",
        "cache_hit": false
      }
```

---

### Flow C: Implicit Feedback Collection

```
Step 1: User action on outfit card
  - User taps "Worn Today" OR dismisses/skips the outfit
  - Client sends: POST /v1/feedback
    {
      "recommendation_id": "uuid",
      "action": "worn" | "skipped" | "saved",
      "item_ids": ["uuid", "uuid", "uuid"]  // the outfit item IDs
    }

Step 2: Write to Supabase
  - Insert into feedback_events:
    { id, user_id, recommendation_id, action, item_ids, created_at }
  - If action == "worn":
      UPDATE wardrobe_items SET last_worn_at = NOW()
      WHERE id IN (item_ids)

Step 3: Cache Invalidation
  - If action == "worn":
      Redis DEL f"rec:{user_id}:{today}:*"  // bust today's cache → fresh pick tomorrow
```

---

## 5. Tech Stack

### Backend

| Technology | Version | Role | Justification |
|---|---|---|---|
| **Python** | 3.12 | Primary language | ML ecosystem, FastAPI, Celery all Python-native |
| **FastAPI** | 0.111+ | API Gateway | Async-first, Pydantic-native, OpenAPI auto-gen |
| **Celery** | 5.3+ | Task queue worker | Production-proven, Redis broker, retry/DLQ built-in |
| **Pydantic v2** | 2.7+ | Schema validation | Rust-backed, used for all I/O validation and LLM response validation |
| **httpx** | 0.27+ | Async HTTP client | Used for Modal API calls and external API calls from worker |
| **SQLAlchemy** | 2.0 | ORM (async) | Type-safe DB access with async support via asyncpg driver |

### ML Inference

| Technology | Role | Justification |
|---|---|---|
| **Modal.com** | On-demand GPU function hosting | Per-second billing, no cold-start model download (container caching), zero infra management |
| **rembg 2.0** | Background removal (U-2-Net model) | Best open-source segmentation for objects-on-background; no fine-tuning required |
| **FashionCLIP (ViT-B/16)** | Style embedding + tag extraction | CLIP fine-tuned on fashion data; produces both embeddings and zero-shot tags in one forward pass |
| **OpenAI text-embedding-3-small** | Occasion query vector | Small, cheap ($0.02/1M tokens), 1536-dim truncatable to 512 for pgvector alignment |

### LLM

| Technology | Role | Justification |
|---|---|---|
| **GPT-4o-mini** | Outfit selection and style note | Supports JSON Schema structured outputs (eliminates hallucinated format), low latency (~800ms), $0.15/1M input tokens |
| **instructor (Python lib)** | Pydantic integration for OpenAI calls | Wraps OpenAI client to auto-retry on validation failure, cleaner than raw structured outputs |

### Database

| Technology | Role | Justification |
|---|---|---|
| **Supabase (PostgreSQL 15)** | Primary relational DB + vector store | pgvector extension handles embeddings at Alpha scale; eliminates Pinecone cost ($70/mo saved); Supabase adds auth, REST, and realtime on top |
| **pgvector** | Vector similarity search | Cosine similarity on 512-dim vectors; ivfflat index handles 500k vectors comfortably; no external service needed |
| **Redis (Upstash)** | Cache, task queue, rate limiting, session | Upstash is serverless Redis with per-request pricing — no idle cost, $0 for Alpha traffic levels |

### Storage

| Technology | Role | Justification |
|---|---|---|
| **Cloudflare R2** | Image object storage | S3-compatible API, zero egress fees (critical — images are fetched on every outfit card load), 10GB free tier |
| **Cloudflare CDN** | Image delivery to mobile clients | Automatic via R2 public bucket configuration; global edge caching; no extra cost |

### Mobile

| Technology | Role | Justification |
|---|---|---|
| **React Native (Expo)** | iOS + Android client | Single codebase, Expo managed workflow reduces native build complexity, OTA updates via Expo EAS |

### Infrastructure

| Technology | Role | Justification |
|---|---|---|
| **Railway** | API server + Celery worker hosting | Git-push deploys, built-in env management, $5/mo hobby tier sufficient for Alpha, upgradeable |
| **Modal.com** | ML inference hosting | See ML Inference section |
| **Upstash Redis** | Managed Redis | Serverless, no idle cost, built-in REST API for Railway-to-Redis connectivity |
| **Supabase** | Managed PostgreSQL | Free tier ($0, 500MB) sufficient for Alpha; Pro tier ($25/mo) for scaling |

### Observability

| Technology | Role | Justification |
|---|---|---|
| **Sentry** | Exception tracking | 5-minute setup, automatic FastAPI + Celery integration, free tier sufficient |
| **Logfire (Pydantic)** | Structured logging + tracing | Native FastAPI/Pydantic instrumentation, OpenTelemetry compatible |
| **Grafana Cloud** | Metrics dashboards | Free tier, works with Prometheus remote write from Railway |
| **OpenTelemetry SDK** | Distributed tracing | Trace context propagated from API Gateway → Celery → Modal → DB |

---

## 6. APIs & Service Contracts

### 6.1 Authentication

All endpoints require `Authorization: Bearer <jwt>` header. JWTs are issued by Supabase Auth (RS256). The API Gateway validates the JWT signature using the Supabase public key (fetched at startup, cached in memory). No database lookup on every request.

---

### 6.2 Endpoint Definitions

#### `POST /v1/wardrobe/upload`
Initiates async garment ingestion.

**Request:**
```json
{
  "image": "base64_encoded_string",
  "item_name": "string (optional, user-provided label)"
}
```

**Response 202:**
```json
{
  "task_id": "uuid",
  "item_id": "uuid",
  "status": "processing"
}
```

**Response 422:** Pydantic validation error (image too large, invalid base64)  
**Response 429:** Rate limit exceeded (10 uploads/minute per user)

---

#### `GET /v1/tasks/{task_id}`
Polls the status of an async ingestion task.

**Response 200:**
```json
{
  "task_id": "uuid",
  "status": "pending | processing | complete | failed",
  "item_id": "uuid",
  "error": "string | null"
}
```

---

#### `GET /v1/recommendations/today`
Returns the outfit recommendation for the current session.

**Response 200:**
```json
{
  "recommendation_id": "uuid",
  "outfit": {
    "top": {
      "id": "uuid",
      "image_url": "https://cdn.vestimate.app/segmented/{user_id}/{item_id}.png",
      "category": "shirt",
      "material": "cotton",
      "fit": "slim",
      "colors": ["white"]
    },
    "bottom": { "...same shape..." },
    "shoes": { "...same shape..." }
  },
  "stylist_note": "string (max 120 chars)",
  "context_summary": {
    "weather": "14°C, rain",
    "top_event": "Business Lunch at 13:00"
  },
  "generated_at": "2025-07-15T08:02:11Z",
  "cache_hit": true
}
```

**Response 404:** Returned when user has < 1 item per required category (outfit impossible). Client shows onboarding prompt.

---

#### `GET /v1/wardrobe/items`
Returns paginated list of user's wardrobe items.

**Query params:** `?page=1&limit=20&category=outerwear&status=active`

**Response 200:**
```json
{
  "items": [
    {
      "id": "uuid",
      "image_url": "string",
      "category": "string",
      "material": "string",
      "fit": "string",
      "colors": ["string"],
      "needs_review": false,
      "last_worn_at": "ISO8601 | null",
      "created_at": "ISO8601"
    }
  ],
  "total": 47,
  "page": 1,
  "limit": 20
}
```

---

#### `POST /v1/feedback`
Records user interaction with a recommendation.

**Request:**
```json
{
  "recommendation_id": "uuid",
  "action": "worn | skipped | saved",
  "item_ids": ["uuid", "uuid", "uuid"]
}
```

**Response 204:** No content on success.

---

### 6.3 Internal Service Contracts (Modal Functions)

#### `POST /inference/segment`
**Content-Type:** `multipart/form-data`  
**Body:** `image` field = raw image bytes  
**Response 200:** PNG bytes (Content-Type: image/png)  
**Response 422:** Image cannot be parsed  
**Timeout:** 30s  

---

#### `POST /inference/embed_and_tag`
**Content-Type:** `multipart/form-data`  
**Body:** `image` field = PNG bytes (segmented)  
**Response 200:**
```json
{
  "embedding": [0.023, -0.114, "..."],
  "tags": {
    "category": { "value": "outerwear", "confidence": 0.91 },
    "material": { "value": "wool", "confidence": 0.74 },
    "fit": { "value": "relaxed", "confidence": 0.68 },
    "colors": ["navy", "charcoal"]
  }
}
```
**Timeout:** 20s  

---

## 7. Data Model

### 7.1 Core Entities

#### `users`
```sql
CREATE TABLE users (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email           TEXT UNIQUE NOT NULL,
  display_name    TEXT,
  city            TEXT NOT NULL,          -- used for weather API calls
  timezone        TEXT NOT NULL DEFAULT 'UTC',
  google_oauth_token  JSONB,              -- encrypted at rest; stores access+refresh token
  onboarding_complete BOOLEAN DEFAULT false,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);
```

**Notes:**  
- `city` is stored as a free-text string mapped to OpenWeatherMap city IDs at query time. Validated on write.  
- `google_oauth_token` is a JSONB blob containing `{ access_token, refresh_token, expires_at }`. Encrypted using Supabase's column-level encryption (pgcrypto). The application layer decrypts on read.

---

#### `wardrobe_items`
```sql
CREATE TABLE wardrobe_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  
  -- Status lifecycle: processing → active | failed | archived
  status          TEXT NOT NULL DEFAULT 'processing'
                  CHECK (status IN ('processing', 'active', 'failed', 'archived')),
  
  -- User-provided
  item_name       TEXT,
  
  -- ML-derived tags
  category        TEXT CHECK (category IN (
                    'top', 'bottom', 'outerwear', 'shoes', 'accessory', 'dress', 'unknown'
                  )),
  material        TEXT,
  fit             TEXT,
  colors          TEXT[],                 -- array of color names from 32-color palette
  confidence_min  FLOAT,                  -- min confidence across all tags; < 0.70 = needs_review
  needs_review    BOOLEAN DEFAULT false,
  
  -- Storage references
  raw_image_key   TEXT,                   -- R2 object key for original upload
  image_url       TEXT,                   -- CDN URL of segmented image (public)
  
  -- Vector embedding (populated after ML processing)
  embedding       vector(512),
  
  -- Lifecycle tracking
  last_worn_at    TIMESTAMPTZ,
  wear_count      INTEGER DEFAULT 0,
  processed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_wardrobe_items_user_id ON wardrobe_items(user_id);
CREATE INDEX idx_wardrobe_items_user_category ON wardrobe_items(user_id, category) 
  WHERE status = 'active';
CREATE INDEX idx_wardrobe_items_last_worn ON wardrobe_items(user_id, last_worn_at);

-- pgvector index (IVFFlat, 100 lists; tune at 500k+ vectors)
CREATE INDEX idx_wardrobe_embedding ON wardrobe_items 
  USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
```

**Notes on `embedding` field:**  
The `vector(512)` type stores a 512-dimensional float array. IVFFlat (Inverted File Index) is an approximate nearest-neighbor index that partitions the vector space into `lists` clusters. At query time, pgvector searches `probes` clusters (default 1; set `SET ivfflat.probes = 5` for better recall at slight latency cost). This is sufficient for a single user's 50–500 item closet searched with exact-match user_id filter. We do NOT need Pinecone at this scale.

---

#### `outfits`
```sql
CREATE TABLE outfits (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  top_id          UUID REFERENCES wardrobe_items(id),
  bottom_id       UUID REFERENCES wardrobe_items(id),
  shoe_id         UUID REFERENCES wardrobe_items(id),
  stylist_note    TEXT,
  source          TEXT NOT NULL CHECK (source IN ('llm', 'fallback', 'user_created')),
  created_at      TIMESTAMPTZ DEFAULT NOW()
);
```

---

#### `recommendation_cache`
```sql
CREATE TABLE recommendation_cache (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  outfit_id         UUID REFERENCES outfits(id),
  cache_key         TEXT NOT NULL,       -- mirrors Redis key for correlation
  weather_snapshot  JSONB,
  schedule_snapshot JSONB,
  was_cache_hit     BOOLEAN,
  fallback_used     BOOLEAN DEFAULT false,
  generated_at      TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(user_id, cache_key)
);
```

**Why this table exists:** Redis cache is ephemeral. This table provides a durable record of what was recommended, when, and under what context. It is the join table between recommendations and feedback events. Without it, you cannot analyze "what fraction of rainy-day recommendations were worn?"

---

#### `feedback_events`
```sql
CREATE TABLE feedback_events (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recommendation_id     UUID REFERENCES recommendation_cache(id),
  action                TEXT NOT NULL CHECK (action IN ('worn', 'skipped', 'saved')),
  item_ids              UUID[],
  created_at            TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_feedback_user ON feedback_events(user_id, created_at DESC);
```

---

#### `prompt_versions`
```sql
CREATE TABLE prompt_versions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  version         TEXT NOT NULL UNIQUE,  -- e.g. "v1.2.0"
  system_prompt   TEXT NOT NULL,
  user_prompt_template TEXT NOT NULL,
  is_active       BOOLEAN DEFAULT false,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  notes           TEXT                   -- changelog entry
  
  -- Only one row may have is_active = true; enforced by partial unique index
);

CREATE UNIQUE INDEX idx_prompt_active ON prompt_versions(is_active) WHERE is_active = true;
```

**Why this table exists:** The prompt is the core product logic. Every recommendation is tagged with the `prompt_version_id` that produced it. This allows regression analysis: "Did v1.2 produce more worn outfits than v1.1?"

---

#### `manual_review_queue`
```sql
CREATE TABLE manual_review_queue (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id         UUID NOT NULL REFERENCES wardrobe_items(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES users(id),
  tags_raw        JSONB,                 -- full FashionCLIP output for review
  reviewed        BOOLEAN DEFAULT false,
  reviewed_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);
```

---

#### `event_log`
```sql
CREATE TABLE event_log (
  id          BIGSERIAL PRIMARY KEY,     -- BIGSERIAL for append-only efficiency
  event_type  TEXT NOT NULL,             -- e.g. "wardrobe.item.ingested"
  user_id     UUID REFERENCES users(id),
  payload     JSONB,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_event_log_user_type ON event_log(user_id, event_type, created_at DESC);
```

---

## 8. Infrastructure & Deployment

### 8.1 Environments

| Environment | Purpose | Data |
|---|---|---|
| **local** | Individual dev, unit tests | SQLite + local Redis + mocked Modal calls |
| **staging** | Integration tests, QA, feature validation | Separate Supabase project, separate R2 bucket, real Modal (small images only) |
| **production** | Live Alpha users | Full production Supabase, R2, Modal, Railway |

Environment variables are managed via Railway's environment variable UI (production) and `.env` files (local). Secrets are never committed to source. A `secrets.example.env` documents all required keys without values.

---

### 8.2 Railway Deployment

**Service 1: API Server**
```
Build: Dockerfile (Python 3.12-slim, uvicorn, gunicorn)
Start command: gunicorn app.main:app -w 2 -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:$PORT
Resources: 512MB RAM, 0.5 vCPU (Railway Starter)
Health check: GET /health → 200
Auto-deploy: on push to main branch
```

**Service 2: Celery Worker**
```
Build: Same Dockerfile, different start command
Start command: celery -A app.worker worker --loglevel=info --concurrency=4
Resources: 1GB RAM, 1 vCPU (Celery loads httpx + serialization libs)
No health check endpoint (Railway monitors process liveliness)
Auto-deploy: on push to main branch
```

**Service 3: Celery Beat (optional, for scheduled tasks)**
```
Start command: celery -A app.worker beat --loglevel=info
Resources: 256MB RAM (beat is lightweight)
Scheduled tasks:
  - Evict expired Redis cache keys: every 6 hours
  - Generate next-day outfit pre-warm for users with active sessions: 23:00 daily
```

---

### 8.3 Modal.com Deployment

```python
# modal_app.py — deployed independently via `modal deploy modal_app.py`

import modal

app = modal.App("vestimate-inference")

# Container image with model weights baked in
# Modal caches this image; model weights are NOT re-downloaded on every invocation
image = (
    modal.Image.debian_slim(python_version="3.12")
    .pip_install(["rembg[gpu]", "fashion-clip", "Pillow", "torch", "torchvision"])
    .run_commands(["python -c 'import rembg; rembg.remove(b\"\")'"])  # pre-warm model cache
)

@app.function(image=image, gpu="T4", timeout=30)
@modal.web_endpoint(method="POST")
def segment(image_bytes: bytes) -> bytes:
    # rembg background removal
    ...

@app.function(image=image, gpu="T4", timeout=20)
@modal.web_endpoint(method="POST")
def embed_and_tag(image_bytes: bytes) -> dict:
    # FashionCLIP forward pass
    ...
```

Modal deployments are versioned. Production deployment is triggered manually (`modal deploy`) after staging validation, not on every commit.

---

### 8.4 CI/CD Pipeline (GitHub Actions)

```yaml
# .github/workflows/ci.yml

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run unit tests
        run: |
          pip install -r requirements-dev.txt
          pytest tests/unit -v --cov=app --cov-report=xml
      - name: Run integration tests (against staging Supabase)
        env:
          SUPABASE_URL: ${{ secrets.STAGING_SUPABASE_URL }}
          SUPABASE_KEY: ${{ secrets.STAGING_SUPABASE_KEY }}
        run: pytest tests/integration -v

  deploy:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to Railway
        run: railway up --service api-server
        env:
          RAILWAY_TOKEN: ${{ secrets.RAILWAY_TOKEN }}
```

**Test categories:**

| Category | What it tests | Mocking |
|---|---|---|
| `tests/unit` | Pydantic schemas, context aggregator logic, cache key generation, color mapping | All external I/O mocked |
| `tests/integration` | Full recommendation flow, DB reads/writes, Redis cache behavior | Real staging Supabase; Modal mocked |
| `tests/eval` | FashionCLIP tagging accuracy on 100-item human-labeled eval set | Run manually pre-release |

---

### 8.5 Observability Configuration

**Sentry (FastAPI):**
```python
import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.celery import CeleryIntegration

sentry_sdk.init(
    dsn=settings.SENTRY_DSN,
    environment=settings.ENV,
    integrations=[FastApiIntegration(), CeleryIntegration()],
    traces_sample_rate=0.1,   # 10% of requests get full trace (cost control)
    profiles_sample_rate=0.1,
)
```

**Key Grafana dashboards to build at launch:**
1. Recommendation cache hit ratio (target: > 80%)
2. p50/p95/p99 recommendation endpoint latency
3. Celery task success/failure rate and duration per task type
4. Modal inference latency (segment + embed_and_tag separately)
5. OpenAI API call rate and cost estimate (computed from token count × price)
6. Daily active recommendations per user (health signal)

---

## 9. Security

### 9.1 Authentication & Authorization

**Mechanism:** Supabase Auth issues JWT tokens (RS256). The API Gateway validates tokens using the Supabase public JWKS endpoint, fetched at startup and cached for 24h. Token validation is middleware-level — no DB lookup per request.

**Authorization model:** Row-level isolation. Every DB query includes `WHERE user_id = :authenticated_user_id`. This is enforced at the application layer (SQLAlchemy query builder) AND at the Supabase RLS (Row-Level Security) policy layer as defense-in-depth.

```sql
-- Example RLS policy on wardrobe_items
ALTER TABLE wardrobe_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can only access their own items"
ON wardrobe_items FOR ALL
USING (user_id = auth.uid());
```

**Rate Limiting:** slowapi (FastAPI middleware), backed by Redis. Limits:
- Upload endpoint: 10 requests/minute per user (prevents abuse of Modal GPU compute)
- Recommendation endpoint: 30 requests/minute per user
- Feedback endpoint: 60 requests/minute per user

---

### 9.2 Data Protection

| Data Type | Protection Mechanism |
|---|---|
| JWT tokens | Short-lived (1h expiry), refresh token rotation via Supabase Auth |
| Google OAuth tokens | Stored encrypted in Supabase (pgcrypto AES-256) |
| Garment images | Stored in private R2 bucket; served via signed URLs with 1h expiry |
| User PII (email, city) | Supabase enforces TLS in transit; encrypted at rest on Supabase hosted infra |
| OpenAI API key | Railway environment variable; never logged or exposed in responses |
| Embedding vectors | Not PII; no special handling beyond standard DB security |

**Image URL strategy:**  
Images are NOT served from a public R2 URL. The API generates signed Cloudflare R2 URLs (TTL: 1 hour) for each response. The client caches the URL locally. This prevents unauthorized image access if a recommendation response is intercepted.

---

### 9.3 Threat Considerations

| Threat | Mitigation |
|---|---|
| JWT forgery | RS256 (asymmetric) — private key never leaves Supabase |
| Prompt injection via garment item_name | item_name is passed as structured JSON data to GPT, not interpolated into prompt text |
| IDOR (accessing another user's wardrobe) | RLS policies + application-layer user_id scoping on all queries |
| Modal endpoint abuse (unauthorized inference) | Modal endpoints require Bearer token (set as Modal secret, not public) |
| Celery task forgery (enqueue arbitrary tasks) | Tasks are enqueued only by the API server; Redis task queue is not publicly accessible |
| Image upload abuse (malicious payloads) | rembg processes images in an isolated Modal container; no code execution from image content |
| R2 storage enumeration | Object keys include user_id prefix; bucket is private; no directory listing |

---

## 10. Scalability & Reliability

### 10.1 Scaling Strategy by Component

| Component | Current (Alpha) | Scale Trigger | Scale Action |
|---|---|---|---|
| FastAPI API server | 1 Railway instance, 2 Uvicorn workers | p95 latency > 500ms | Increase Railway instance size (vertical) → add instances (horizontal) |
| Celery worker | 1 Railway instance, 4 concurrent tasks | Task queue depth > 50 | Add Railway worker instances (horizontal, stateless) |
| Modal inference | Auto-scales to 0; cold start ~3s | None (managed) | Set `min_containers=1` on Modal for zero cold start |
| Supabase PostgreSQL | Shared compute (free tier) | > 200 concurrent connections | Upgrade to Supabase Pro ($25/mo), add pgBouncer connection pooling |
| pgvector search | Per-user query, small dataset | > 5M total vectors across platform | Migrate to dedicated Postgres instance; tune IVFFlat `lists` parameter |
| Redis (Upstash) | Serverless | None (managed) | Upgrade Upstash plan; no architectural change |

### 10.2 Load Handling

**Recommendation endpoint is the hot path.** At 150 users with 3 app opens/day:
- 450 requests/day = ~0.005 req/s average
- Peak (morning rush, 7–9 AM): ~50 requests in 2 hours = ~0.007 req/s
- With 80% cache hit rate: ~10 OpenAI calls/day

This is negligible load. The architecture is designed for 10,000 DAU with cache before requiring horizontal scaling of the API server.

**Ingestion burst handling:** If 50 users all upload 10 items simultaneously (500 tasks), Celery queues them in Redis and processes at worker concurrency rate (4 tasks/worker). Users see "processing" status — the async design means no requests time out or fail. Add a second Celery worker instance on Railway to double throughput ($5/mo).

### 10.3 Fault Tolerance

**GPT-4o-mini unavailability:**  
- Fallback path is implemented (see Flow B Step 7): top-1 per category by cosine similarity, no LLM call.
- Client receives a valid recommendation. `fallback_used: true` is logged for monitoring.
- SLA degradation: recommendation quality drops, but app remains functional.

**Modal function timeout/failure:**  
- Celery task retries: `max_retries=3, countdown=30` (exponential backoff).
- After 3 failures: task marked `failed` in Redis, `wardrobe_items.status = 'failed'`.
- User sees item with "processing failed" state in app; prompted to re-upload.

**Supabase downtime:**  
- No local fallback. Supabase targets 99.9% uptime.
- API returns 503 with `Retry-After: 60` header.
- Recommendation cache in Redis is still readable during brief DB outages (Redis does not depend on Supabase).

**Redis (Upstash) unavailability:**  
- Celery falls back to database-backed broker (configure `CELERY_BROKER_FALLBACK_URL` pointing to Supabase via SQLAlchemy-Celery backend — configured at startup but not used in normal operation).
- Cache misses transparently on every request. Increased OpenAI calls, no functional failure.

**Recommendation cache invalidation correctness:**  
- Cache TTL is 4 hours. Even if invalidation fails (e.g. feedback endpoint error), the cache expires within 4 hours.
- Same outfit is never served more than two consecutive days: `last_worn_at` is updated on "worn" feedback, which filters that item from retrieval for 7 days.

---

## 11. Assumptions & Edge Cases

### 11.1 Explicit Assumptions

1. **FashionCLIP embedding space alignment with text embeddings:** OpenAI `text-embedding-3-small` embeddings are truncated from 1536 to 512 dimensions and used as query vectors against FashionCLIP's 512-dim embedding space. These spaces are NOT natively aligned (different model families). The cosine similarity search still produces *useful* results because: (a) both models are CLIP-family and share general semantic structure, and (b) the IVFFlat retrieval is used to produce a *candidate set* that is then re-ranked by the LLM — retrieval precision does not need to be perfect, only recall needs to be sufficient. If empirical testing shows poor candidate quality, the mitigation is to use FashionCLIP's own text encoder to embed the occasion string instead. This should be validated in Week 1.

2. **User's primary wardrobe categories are top, bottom, shoes.** The system builds outfits from exactly these three. Accessories, outerwear, and dresses are ingested and stored but not included in outfit assembly logic in V1.

3. **One outfit recommendation per day is sufficient.** The cache TTL of 4 hours means users who open the app at 8 AM and again at 1 PM get the same recommendation unless weather changes significantly. If user research shows this is a friction point, reduce TTL or add a "refresh" endpoint.

4. **Calendar event title is sufficient for formality inference.** The keyword classifier maps event titles ("Lunch", "Meeting", "Gym", "Date", "Interview") to formality levels. If the calendar event has no title or a generic title ("Busy"), formality defaults to `casual`.

5. **Manual review queue is a best-effort quality signal.** Low-confidence items are flagged but not blocked. In Alpha, the review queue is read by the team in Supabase Studio. No UI for user-facing correction is built until feedback shows this is a top user complaint.

---

### 11.2 Edge Cases and Handling

| Edge Case | Handling |
|---|---|
| User has 0 items in a required category (e.g., no shoes scanned) | Retrieval falls back to top-5 by recency for that category; LLM is informed via context that shoe selection is limited. API still returns a recommendation; no 500 error. |
| User opens app with no internet (mobile offline) | React Native detects offline state. Client serves last cached recommendation from local AsyncStorage. No API call made. |
| FashionCLIP returns `category = "unknown"` | Item is stored with `category = "unknown"`, excluded from outfit retrieval queries. Prompt on item detail screen: "We couldn't identify this item. Tap to categorize manually." |
| GPT returns a `stylist_note` > 120 characters | Pydantic validator truncates at word boundary to ≤ 120 chars. Not treated as a validation failure. |
| Two recommendation requests arrive simultaneously for the same user | Redis `SET NX` (set-if-not-exists) used on cache write. First request to compute wins. Second request reads the cache after first completes (if overlapping during miss). Race condition window is ~2s; both users get a valid recommendation. |
| User uploads a non-clothing image (e.g., selfie, food) | rembg removes background; FashionCLIP attempts tagging. If `category.confidence < 0.50`, item is marked `needs_review = true` with a low-confidence flag. It is excluded from outfit recommendations. No error shown to user; item appears in wardrobe as "unrecognized". |
| User revokes Google Calendar OAuth | Calendar fetch returns 401. Context Aggregator catches the error, sets `schedule = []`, continues with weather-only context. A soft notification is shown in app settings: "Re-connect Google Calendar for smarter recommendations." |
| OpenAI API key quota exceeded | HTTP 429 from OpenAI is caught; Celery-style exponential retry is applied to recommendation flow (max 2 retries, 5s apart). If all retries fail, the heuristic fallback (top-1 per category by vector similarity) is returned. |
| User deletes a wardrobe item that is in an existing cached recommendation | The recommendation cache record in Redis remains valid until TTL expiry. The item record in Supabase is set to `status = 'archived'`. On next fresh recommendation, the archived item is filtered. If a user happens to view a cached recommendation referencing a deleted item, the image URL will still be valid (signed URL TTL); no broken state visible to user. |
| Cold start: new user with 0 items | `GET /v1/recommendations/today` returns 404 with body `{ "code": "insufficient_wardrobe", "message": "Add at least 3 items to get your first recommendation" }`. Client routes to onboarding flow. |

---

*End of VESTIMATE Architecture v1.0.0*
