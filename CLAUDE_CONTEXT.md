# CLAUDE_CONTEXT — Vestimate Codebase Architecture & Context Document

**Generated:** 2026-05-06  
**Scope:** Full read-only architectural analysis of the Vestimate backend repository.

---

## 1. Project Overview

### What is Vestimate?

Vestimate is a **mobile-first AI wardrobe assistant**. Users photograph their clothing, and the system automatically digitizes, categorizes, and stores each garment. On every app session, Vestimate assembles a **contextually-aware outfit recommendation** by synthesizing the user's closet state, real-time weather data, and Google Calendar schedule — presenting it as a visual outfit card with a one-sentence stylist rationale.

The AI operates invisibly as a background reasoning layer — there is no chatbot interface. The product experience is: open the app → see today's outfit → tap "Worn" or skip.

### Core Functionality

1. **Garment Ingestion** — Upload a photo → background removal (rembg/U-2-Net) → FashionCLIP embedding + zero-shot tagging → store in pgvector.
2. **Outfit Recommendation** — Aggregate context (weather + calendar) → build query vector → retrieve candidates via cosine similarity → GPT-4o-mini selects the final outfit → cache and serve.
3. **Feedback Loop** — User marks outfit as "worn", "skipped", or "saved" → updates `last_worn_at` to bias future recommendations away from recently worn items → busts Redis cache.

### Key Product Principles

- **Sub-1.5s latency** on cache hit for recommendations; <4s on cold path.
- **Async ingestion** — uploads return immediately (202 Accepted); ML processing runs in background workers.
- **Graceful degradation** — if GPT-4o-mini is unavailable, heuristic fallback (top-1 by vector similarity) keeps the app functional.
- **Alpha budget target:** ≤$200/month for 150 users.

---

## 2. System Architecture & Tech Stack

### 2.1 Backend Architecture

| Component | Technology | Role |
|---|---|---|
| **API Gateway** | FastAPI 0.111+ | HTTP entry point, JWT auth, rate limiting, request validation |
| **Task Queue** | Celery 5.4+ with Redis broker | Async garment ingestion pipeline |
| **Scheduled Tasks** | Celery Beat | Cache eviction (every 6h), recommendation pre-warming (23:00 UTC daily) |
| **Rate Limiting** | slowapi + Redis | Per-user/IP limits on upload (10/min), recommendation (30/min), feedback (60/min) |
| **Auth** | Supabase Auth (RS256 JWT) | JWKS-based token validation; `python-jose` for decoding |
| **Production Server** | Gunicorn + Uvicorn workers | 2 workers, 120s timeout |

### 2.2 ML Pipeline

| Step | Technology | Details |
|---|---|---|
| **Background Removal** | rembg 2.0 (U-2-Net) on Modal GPU (T4) | Input: raw image bytes → Output: PNG with alpha channel |
| **Embedding + Tagging** | FashionCLIP (ViT-B/16) on Modal GPU (T4) | Produces 512-dim embedding + zero-shot tags (category, material, fit) with confidence scores |
| **Text Embedding** | FashionCLIP text encoder (`patrickjohncyh/fashion-clip`) on Modal | Encodes occasion text into 512-dim vector for cosine similarity search |
| **Confidence Gate** | Python logic in Celery worker | Items with `min_confidence < 0.70` are flagged `needs_review` and enqueued in `manual_review_queue` |

**Tag Taxonomies:**
- Categories: `top`, `bottom`, `outerwear`, `shoes`, `accessory`, `dress`
- Fits: `slim`, `relaxed`, `regular`, `oversized`
- Materials: `cotton`, `wool`, `denim`, `leather`, `polyester`, `silk`

### 2.3 LLM Integration

- **Model:** GPT-4o-mini via OpenAI API
- **Temperature:** 0.3 (low for consistency, slight variation for novelty)
- **Max Tokens:** 200
- **Response Format:** JSON Schema structured outputs (strict mode) — model cannot return malformed JSON
- **Prompt Management:** Versioned prompts stored in `prompt_versions` table; only one `is_active=true` at a time
- **Hallucination Guard:** Selected item IDs are cross-referenced against the candidate set in Python — not trusted from LLM output
- **Fallback:** On any LLM failure or hallucinated IDs, top-1 per category by vector similarity is returned; `fallback_used=true` is logged

### 2.4 Storage Systems

| System | Technology | Purpose |
|---|---|---|
| **Relational DB** | Supabase (PostgreSQL 15) | Users, wardrobe items, outfits, feedback, event log |
| **Vector Store** | pgvector extension (IVFFlat index, 100 lists) | 512-dim cosine similarity search on garment embeddings |
| **Object Storage** | Cloudflare R2 (S3-compatible, boto3) | Raw uploads (`raw-uploads/{user_id}/`) and segmented PNGs (`segmented/{user_id}/`) |
| **Cache** | Redis (index 0: Celery broker; index 1: app cache) | Recommendation cache (4h TTL), vector query cache (1h TTL), rate limiting |

**Image URL Strategy:** Images are served via time-limited presigned R2 URLs (1h expiry), not public URLs.

### 2.5 Infrastructure Components

| Component | Platform | Notes |
|---|---|---|
| **API Server** | Railway | Dockerfile-based deploy, health check at `/health` |
| **Celery Worker** | Railway | Same Dockerfile, different start command, `--concurrency=4 --pool=prefork` in prod |
| **Celery Beat** | Railway | Lightweight scheduler for periodic tasks |
| **ML Inference** | Modal.com | Serverless GPU (T4), per-second billing, auto-scales to 0 |
| **Database** | Supabase | Managed PostgreSQL + pgvector + Auth + RLS |
| **Redis** | Upstash (or local Docker) | Serverless Redis, per-request pricing |

### 2.6 Observability Stack

| Tool | Role |
|---|---|
| **Sentry** | Exception tracking across FastAPI + Celery + asyncpg; 10% trace sample rate |
| **Logfire (Pydantic)** | Structured logging with FastAPI auto-instrumentation |
| **Prometheus** | Metrics exposed at `/metrics` via `prometheus-fastapi-instrumentator` |
| **Logfire spans** | Used throughout worker tasks and recommendation pipeline for tracing |

---

## 3. Repository Directory Structure

```
Vestimate/
├── main.py                          # FastAPI app entry point; route registration, startup hooks
├── Dockerfile                       # Multi-stage build: builder (compile deps) → runtime (slim)
├── docker-compose.yml               # Local dev: Redis + API + Worker + Beat
├── railway.toml                     # Railway deployment: 3 services (api, worker, beat)
├── requirements.txt                 # Direct Python dependencies (pinned ranges)
├── requirements.lock                # Fully resolved dependency versions
├── .env.example                     # Template for all required environment variables
├── .gitignore                       # Excludes .env, __pycache__, venv, uploads, test_images
├── .dockerignore                    # Excludes venv, scripts, docs, .git from Docker builds
├── README.md                        # Placeholder ("Something big coming soon...")
├── REPOSITORY_STATE.md              # Phase 2 completion summary and architecture overview
├── repository_state.md.resolved     # Hygiene report: resolved infrastructure bottlenecks
├── Vestimate_archiecture (1).md     # Full 1178-line production architecture specification
├── audit_output.txt                 # System audit results
│
├── app/                             # Application source code
│   ├── __init__.py
│   ├── api/                         # HTTP layer
│   │   ├── __init__.py
│   │   └── v1/
│   │       ├── __init__.py          # APIRouter aggregation; mounts wardrobe, tasks, recommendations, feedback
│   │       └── endpoints/
│   │           ├── wardrobe.py      # POST /v1/wardrobe/upload — image upload + Celery task dispatch
│   │           ├── wardrobe_read.py # GET /v1/wardrobe/items, GET /items/{id}, DELETE /items/{id}
│   │           ├── tasks.py         # GET /v1/tasks/{task_id} — poll Celery task status
│   │           ├── recommendations.py # GET /v1/recommendations/today + /history
│   │           ├── feedback.py      # POST /v1/feedback — worn/skipped/saved
│   │           ├── users.py         # GET/PUT /v1/users/me, POST /v1/users/me/onboard
│   │           └── google_oauth.py  # POST /callback, GET /revoke for Google Calendar OAuth
│   │
│   ├── core/                        # Cross-cutting concerns
│   │   ├── __init__.py
│   │   ├── config.py                # Pydantic BaseSettings; SQLAlchemy async engine init
│   │   ├── auth.py                  # JWT validation via Supabase JWKS; CurrentUser dependency
│   │   ├── rate_limit.py            # slowapi Limiter with user-ID-or-IP key function
│   │   └── observability.py         # Sentry, Logfire, Prometheus initialization
│   │
│   ├── models/                      # Pydantic schemas
│   │   ├── __init__.py
│   │   ├── schemas.py               # TaskStatusResponse, UploadResponse
│   │   └── recommendation_schemas.py # WeatherData, ScheduleEvent, RecommendationContext,
│   │                                  # GarmentCandidate, CandidateSet, OutfitSelection,
│   │                                  # OutfitItem, OutfitRecommendationResponse, FeedbackRequest
│   │
│   ├── services/                    # Business logic layer
│   │   ├── __init__.py
│   │   ├── storage.py               # Cloudflare R2: upload files, generate signed URLs
│   │   ├── retrieval.py             # pgvector cosine similarity queries (category-split)
│   │   ├── vector_service.py        # Text → 512-dim vector via Modal FashionCLIP text encoder
│   │   ├── llm_service.py           # GPT-4o-mini outfit selection with structured outputs
│   │   ├── context_aggregator.py    # Weather (OpenWeatherMap) + Calendar (Google) aggregation
│   │   ├── recommendation_service.py # Full recommendation pipeline (used by endpoint + beat tasks)
│   │   ├── recommendation_cache.py  # Redis cache: get/set/invalidate recommendations
│   │   └── wardrobe_read.py         # Paginated wardrobe queries, single item fetch, archive
│   │
│   └── worker/                      # Background processing
│       ├── __init__.py
│       ├── celery_app.py            # Celery instance config (Redis broker, JSON serialization)
│       ├── beat_schedule.py         # Periodic tasks: cache eviction (6h), pre-warm (23:00 UTC)
│       ├── tasks.py                 # ingest_garment, generate_recommendation_task,
│       │                              # evict_expired_recommendations, prewarm_recommendations
│       └── modal_inference.py       # Modal GPU function definitions: segment, embed_and_tag, text_embed
│
├── migrations/
│   └── 003_phase3_indexes_and_seed.sql  # IVFFlat index, composite indexes, prompt seed
│
├── scripts/
│   ├── 001_database_migration.sql   # Core schema: users, wardrobe_items, pgvector index
│   ├── 002_remaining_tables.sql     # Phase 2: outfits, recommendation_cache, feedback_events,
│   │                                  # prompt_versions, manual_review_queue, event_log
│   ├── 004_rls_policies.sql         # Row-Level Security on all tables
│   ├── bulk_upload.py               # Data simulation/testing tool
│   ├── check_db.py                  # DB connectivity verification
│   ├── check_health.py              # API health check
│   ├── check_pgcrypto.py            # pgcrypto extension verification
│   ├── system_audit.py              # Comprehensive diagnostic for all external connections
│   ├── test_sentry.py               # Sentry integration test
│   ├── verify_feedback_cache.py     # Feedback cache verification
│   ├── verify_production.py         # Production readiness verification
│   ├── verify_rate_limit.py         # Rate limiting verification
│   └── verify_rls.py               # RLS policy verification
│
├── tests/
│   ├── __init__.py
│   ├── unit/
│   │   ├── test_auth.py             # JWT validation tests (mock JWKS)
│   │   └── test_wardrobe_read.py    # Paginated wardrobe query tests (mock asyncpg)
│   └── integration/
│       └── test_feedback.py         # Feedback endpoint auth enforcement test
│
├── docs/
│   └── grafana_dashboards.md        # 6 dashboard specifications for observability
│
├── .github/workflows/
│   └── ci.yml                       # CI/CD: lint (ruff+mypy) → unit tests → integration tests → Railway deploy
│
├── test_images/                     # Test image assets (gitignored)
└── uploads/                         # Local upload directory (gitignored)
```

### Critical Entry Points

| File | Purpose |
|---|---|
| `main.py` | FastAPI application factory; all routers mounted here |
| `app/worker/tasks.py` | Celery task definitions — the ML ingestion pipeline lives here |
| `app/api/v1/endpoints/recommendations.py` | The recommendation endpoint — the core product flow |
| `app/services/recommendation_service.py` | Reusable recommendation pipeline (used by both endpoint and beat tasks) |
| `app/core/config.py` | All environment variables and SQLAlchemy engine initialization |
| `app/worker/modal_inference.py` | Modal GPU function definitions (deployed separately) |

---

## 4. Database & Data Flow

### 4.1 Database Schema (8 Tables)

#### Core Tables

| Table | Purpose | Key Columns |
|---|---|---|
| `users` | User accounts | `id` (UUID PK), `email`, `city`, `timezone`, `google_oauth_token` (encrypted), `onboarding_complete` |
| `wardrobe_items` | Garment metadata + embeddings | `id`, `user_id` (FK), `status` (processing→active\|failed\|archived), `category`, `material`, `fit`, `colors[]`, `embedding` (vector(512)), `raw_image_key`, `image_url`, `confidence_min`, `needs_review`, `last_worn_at`, `wear_count` |
| `outfits` | Assembled outfit records | `id`, `user_id`, `top_id`/`bottom_id`/`shoe_id` (FK→wardrobe_items), `stylist_note`, `source` (llm\|fallback\|user_created) |

#### Supporting Tables

| Table | Purpose |
|---|---|
| `recommendation_cache` | Durable record of recommendations for analytics; mirrors Redis cache key; stores weather/schedule snapshots |
| `feedback_events` | User interactions: `worn`, `skipped`, `saved` with `item_ids[]` array |
| `prompt_versions` | Versioned LLM system prompts; only one `is_active=true` (enforced by partial unique index) |
| `manual_review_queue` | Items with `confidence_min < 0.70`; stores raw ML tags for review |
| `event_log` | Append-only audit trail (BIGSERIAL PK) for system events |

#### Key Indexes

- `idx_wardrobe_embedding` — IVFFlat on `embedding vector_cosine_ops` (100 lists)
- `idx_wardrobe_active_user_category` — Composite on `(user_id, category) WHERE status='active'`
- `idx_wardrobe_last_worn` — On `(user_id, last_worn_at DESC)`
- `idx_prompt_active` — Partial unique on `is_active WHERE is_active=true`

#### Row-Level Security

All tables have RLS enabled. Policies enforce `user_id = auth.uid()` isolation. `event_log` is read-only for users (writes are service_role only). `prompt_versions` is read-only for all authenticated users.

### 4.2 End-to-End Image Ingestion Pipeline

```
Client uploads image
    │
    ▼
POST /v1/wardrobe/upload (FastAPI)
    ├── Validate JWT → extract user_id
    ├── Validate file type (jpeg/png/webp/gif)
    ├── Generate item_id (UUID)
    ├── Upload raw bytes to R2: raw-uploads/{user_id}/{item_id}.ext
    ├── Create stub record: wardrobe_items(status="processing")
    ├── Enqueue Celery task: ingest_garment(item_id, raw_object_key, user_id)
    └── Return 202: { item_id, task_id, status: "processing" }

Client polls GET /v1/tasks/{task_id} every ~3s
    │
    ▼
Celery Worker picks up task
    ├── 1. Download image from R2 via presigned URL
    ├── 2. POST to Modal /segment → receive segmented PNG (background removed)
    ├── 3. Upload segmented PNG to R2: segmented/{user_id}/{item_id}.png
    ├── 4. POST to Modal /embed_and_tag → receive embedding[512] + tags
    ├── 5. Confidence gate: min(category, fit, material confidence)
    │       └── If < 0.70 → insert into manual_review_queue
    ├── 6. UPDATE wardrobe_items: status="active", embedding, category, material, fit, colors, image_url
    ├── 7. INSERT event_log: "wardrobe.item.ingested"
    └── 8. Return {item_id, status: "complete"}
         (On failure: status="failed", retry up to 3x with 60s backoff)
```

### 4.3 Recommendation Pipeline (Data Flow)

```
GET /v1/recommendations/today
    │
    ▼
1. Fetch user record (city, oauth_token) from Supabase
    │
    ▼
2. Build RecommendationContext
    ├── Fetch weather from OpenWeatherMap → WeatherData(temp, condition, wind, temp_band)
    ├── Fetch calendar from Google Calendar API (OAuth) → ScheduleEvent[] (max 3)
    ├── Classify formality from event titles (keyword-based, not LLM)
    └── Determine: date, day_of_week, time_of_day, primary_formality
    │
    ▼
3. Check Redis cache: key = rec:{user_id}:{date}:{temp_band}_{condition}
    ├── HIT → return cached recommendation (<100ms)
    └── MISS → continue
    │
    ▼
4. Build occasion text → encode via Modal FashionCLIP text encoder → 512-dim query vector
    (cached in Redis index 1 with 1h TTL)
    │
    ▼
5. Category-split pgvector retrieval:
    FOR each category IN [top, bottom, shoes]:
        SELECT ... FROM wardrobe_items
        WHERE user_id AND status='active' AND category
          AND (last_worn_at IS NULL OR last_worn_at < NOW() - 7 days)
        ORDER BY embedding <=> query_vector
        LIMIT 5
    (Fallback: if 0 results for a category, use recency-based ordering)
    │
    ▼
6. GPT-4o-mini outfit selection (structured JSON output)
    ├── System prompt from prompt_versions table
    ├── User message: context + serialized candidates (excluding image URLs)
    ├── Validate: all returned IDs exist in candidate set
    └── On failure: heuristic fallback (top-1 per category)
    │
    ▼
7. Build response with signed R2 image URLs (1h expiry)
    │
    ▼
8. Persist: INSERT into outfits + recommendation_cache tables
   Cache: SET in Redis with 4h TTL
```

### 4.4 Feedback Flow

```
POST /v1/feedback { recommendation_id, action, item_ids }
    │
    ├── INSERT into feedback_events
    │
    └── IF action == "worn":
        ├── UPDATE wardrobe_items SET last_worn_at=NOW(), wear_count+=1 for each item_id
        └── DELETE Redis keys matching rec:{user_id}:* (bust recommendation cache)
```

---

## 5. Infrastructure Configuration

### 5.1 Docker Compose (Local Development)

Four services defined in `docker-compose.yml`:

| Service | Image/Build | Port | Purpose |
|---|---|---|---|
| `redis` | `redis:7-alpine` | 6379 | Message broker + cache; health-checked via `redis-cli ping` |
| `api` | Build from Dockerfile | 8000 | FastAPI dev server (`uvicorn --reload`); mounts source code as volume |
| `worker` | Build from Dockerfile | — | Celery worker (`--pool=threads --concurrency=2`) |
| `beat` | Build from Dockerfile | — | Celery Beat scheduler |

All services share `.env` file. `REDIS_URL` is overridden to `redis://redis:6379/0` for container networking.

### 5.2 Dockerfile

**Multi-stage build:**
1. **Builder stage** (`python:3.12-slim`): Installs build dependencies (`build-essential`, `libpq-dev`, `gcc`), pip-installs requirements to `--user` prefix.
2. **Runtime stage** (`python:3.12-slim`): Copies only runtime deps (`libpq5`) and installed packages from builder. Creates non-root `vestimate` user (UID 1001). Exposes port 8000.

**Health check:** `httpx.get('http://localhost:${PORT}/health')` every 30s.

**Default CMD:** Gunicorn with 2 Uvicorn workers, 120s timeout.

### 5.3 Railway Deployment (`railway.toml`)

Three services, all built from the same Dockerfile:

| Service | Start Command | Restart Policy |
|---|---|---|
| `api-server` | `gunicorn main:app -w 2 -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:$PORT --timeout 120` | Health check at `/health` |
| `celery-worker` | `celery -A app.worker.tasks worker --loglevel=info --concurrency=4 --pool=prefork` | ON_FAILURE (max 3 retries) |
| `celery-beat` | `celery -A app.worker.beat_schedule beat --loglevel=info` | ON_FAILURE (max 3 retries) |

### 5.4 CI/CD Pipeline (`.github/workflows/ci.yml`)

```
Push/PR to main/staging
    │
    ├── [lint] ruff check + mypy (strict-optional)
    │
    ├── [unit-tests] pytest tests/unit with Redis service container
    │   └── Coverage threshold: 70%
    │
    ├── [integration-tests] pytest tests/integration against staging Supabase
    │   └── Only runs on main/staging branches; needs: unit-tests
    │
    └── [deploy] Railway CLI deploy (api-server + celery-worker + celery-beat)
        └── Only on main; needs: lint + unit-tests + integration-tests
        └── Post-deploy health check: curl https://api.vestimate.app/health
```

### 5.5 Environment Variables

**Core:** `APP_NAME`, `DEBUG`, `REDIS_URL`, `ENV` (local/staging/production)

**Supabase:** `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `SUPABASE_DATABASE_URL` (postgresql+asyncpg://), `SUPABASE_JWKS_URL`, `SUPABASE_JWT_AUDIENCE`

**Cloudflare R2:** `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET_NAME`

**Modal:** `MODAL_ENDPOINT_SEGMENT`, `MODAL_ENDPOINT_EMBED`, `MODAL_ENDPOINT_TEXT_EMBED`

**External APIs:** `OPENAI_API_KEY`, `OPENWEATHERMAP_API_KEY`

**Google OAuth (Phase 5):** `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `TOKEN_ENCRYPTION_KEY`

**Observability:** `SENTRY_DSN`, `LOGFIRE_TOKEN`, `PROMETHEUS_METRICS_TOKEN`

**Rate Limits:** `RATE_LIMIT_UPLOAD` (10/min), `RATE_LIMIT_RECOMMENDATION` (30/min), `RATE_LIMIT_FEEDBACK` (60/min)

---

## 6. Current Roadmap & Development Status

### 6.1 Phase Completion Status

| Phase | Status | Description |
|---|---|---|
| **Phase 1** | ✅ Complete | Core ingestion pipeline: FastAPI + Celery + Modal + R2 + Supabase |
| **Phase 2** | ✅ Complete | Database schema, Docker Compose, dependency resolution, stress testing |
| **Phase 3** | ✅ Complete | Recommendation engine: context aggregator, pgvector retrieval, LLM selection, caching, feedback loop |
| **Phase 4** | ✅ Complete | Production hardening: JWT auth (Supabase JWKS), rate limiting (slowapi), observability (Sentry/Logfire/Prometheus), RLS policies, CI/CD pipeline |
| **Phase 5** | 🔧 In Progress | Google Calendar OAuth integration (endpoints exist: callback + revoke); token encryption via Fernet |

### 6.2 Implemented Systems

- ✅ Full ML ingestion pipeline (upload → segment → embed → tag → persist)
- ✅ Recommendation engine with cache-first strategy
- ✅ GPT-4o-mini structured output integration with hallucination guard
- ✅ Category-split pgvector cosine similarity retrieval
- ✅ Context aggregation (weather + calendar + formality classification)
- ✅ Redis recommendation cache (4h TTL) + vector query cache (1h TTL)
- ✅ Supabase JWT authentication with JWKS validation
- ✅ Rate limiting (per-user or per-IP via slowapi + Redis)
- ✅ Row-Level Security policies on all tables
- ✅ Full CI/CD pipeline (lint → test → deploy)
- ✅ Observability stack (Sentry + Logfire + Prometheus)
- ✅ Celery Beat periodic tasks (cache eviction, pre-warming)
- ✅ Google OAuth callback/revoke endpoints with Fernet token encryption
- ✅ User profile management (onboarding, profile update)
- ✅ Wardrobe CRUD (list, get, archive/soft-delete)
- ✅ Recommendation history endpoint
- ✅ Feedback endpoint with wear tracking + cache invalidation

### 6.3 Known Technical Debt & Resolved Issues

**Resolved (documented in `repository_state.md.resolved`):**
1. **PgBouncer collision** — SQLAlchemy `asyncpg` prepared statement cache conflicts with Supabase transaction pooler → Fixed with `statement_cache_size=0`.
2. **Celery thread/asyncio conflict** — Worker threads shared asyncpg connection pool → Fixed by using synchronous Supabase REST client in workers.
3. **Modal free-tier exhaustion** — Reduced worker concurrency to 2, added 120s timeouts and exponential backoff retries.

**Outstanding items:**
- `README.md` is a placeholder — needs proper documentation.
- `.gitignore` has encoding corruption on the `test_images/` line (UTF-16LE null bytes).
- `requirements.lock` is UTF-16LE encoded (unusual; may cause issues in some tools).
- No `conftest.py` or pytest configuration file exists.
- Unit test coverage is minimal (only 2 test files in `tests/unit/`).
- The `embed_and_tag` Modal function uses `openai/clip-vit-base-patch16` (standard CLIP) as a stand-in; the `text_embed` function correctly uses `patrickjohncyh/fashion-clip`.
- No migration runner or versioning tool (migrations are raw SQL files run manually via Supabase SQL editor).

### 6.4 Architecture Notes for Future Development

- **Monorepo design** — All services (API, worker, beat) share the same codebase and Dockerfile. Designed to be extractable into microservices post-PMF.
- **Database access patterns** — The codebase uses BOTH `asyncpg` (direct connections for queries) and `supabase-py` REST client (for table operations). The worker exclusively uses the synchronous Supabase REST client to avoid asyncio conflicts.
- **SQLAlchemy engine** is initialized in `config.py` but is NOT actively used for queries — most DB access goes through raw `asyncpg` connections or `supabase-py` REST client.
- **The `Vestimate_archiecture (1).md` file** (1178 lines) is the authoritative architecture specification. It contains the complete system design, data flows, security model, scalability strategy, and edge case handling. Consult it for any architectural decision context.

---

*End of CLAUDE_CONTEXT.md*
