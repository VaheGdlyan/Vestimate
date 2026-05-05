# VESTIMATE — PHASE 4 IMPLEMENTATION ROADMAP
## Agent Execution Document: Production Hardening, Observability & Alpha Launch
**Version:** 1.0 | **Status:** Ready for execution | **Depends on:** Phase 3 complete
**Estimated total effort:** 6–9 engineering days

---

## DOCUMENT PURPOSE

This is the authoritative execution contract for Phase 4 of the Vestimate backend.
Phase 3 delivered a working Recommendation Engine (Service 3). Phase 4 transforms
the system from a locally-proven pipeline into a production-deployable, observable,
secure, and mobile-ready backend capable of serving Alpha users.

This document covers four parallel tracks:
- **Track A** — Authentication & Security hardening (what blocks production)
- **Track B** — Missing API surface (what the mobile client needs)
- **Track C** — Observability stack (what lets you operate the system)
- **Track D** — Infrastructure & Deployment (Railway + CI/CD + staging)

### Agent rules (non-negotiable)
1. Execute tasks in strict order within each track.
2. Tracks A and B must complete before Track C or D begins.
3. After each task, run its GATE command. Do not proceed until GATE: PASS.
4. Every file must contain complete, runnable code. No stubs, no `# TODO`.
5. Commit after every task with the exact commit message specified.
6. Report: `TASK N — [name] → [command] → [output] → GATE: PASS ✓ | FAIL — [reason] — [fix]`

---

## SECTION 1 — WHERE WE ARE (Phase 3 completion baseline)

```
SERVICES COMPLETE:
  ✅ Service 1 — API Gateway (FastAPI): /health, /v1/wardrobe/upload, /v1/tasks/{task_id}
  ✅ Service 2 — Ingestion Worker (Celery + Modal): full ML pipeline operational
  ✅ Service 3 — Recommendation Engine: cache → context → pgvector → GPT-4o-mini → response
  ✅ Service 4 — Modal inference layer: rembg + FashionCLIP deployed

WHAT IS MISSING FOR PRODUCTION:
  ❌ Auth: Supabase JWT middleware not enforced on any endpoint
  ❌ Auth: user_id still accepted from request body (IDOR vulnerability)
  ❌ Auth: Google OAuth token handling for Calendar integration
  ❌ API: GET /v1/wardrobe/items (paginated) — not built
  ❌ API: POST /v1/feedback — not built (feedback_events table unused)
  ❌ API: GET /v1/wardrobe/items/{item_id} — not built
  ❌ API: DELETE /v1/wardrobe/items/{item_id} — not built
  ❌ API: User profile endpoints — not built (city, timezone required for weather)
  ❌ Rate limiting — slowapi middleware not configured
  ❌ RLS policies — wardrobe_items, feedback_events, recommendation_cache unprotected
  ❌ Observability: Sentry not integrated (FastAPI + Celery)
  ❌ Observability: Logfire structured logging not configured
  ❌ Observability: Prometheus metrics endpoint not exposed
  ❌ Observability: Grafana dashboards not created
  ❌ Deployment: Railway services not configured
  ❌ Deployment: GitHub Actions CI/CD pipeline not created
  ❌ Deployment: Staging environment does not exist
  ❌ Deployment: Docker worker image broken (needs rebuild with Phase 2–3 deps)
  ❌ Pre-warm: Celery Beat schedule for nightly recommendation pre-warming not built
  ❌ Mobile: signed R2 URL generation not wired into recommendation response
```

---

## SECTION 2 — PHASE 4 ARCHITECTURE OVERVIEW

```
What Phase 4 adds to the running system:

  Mobile Client (React Native)
       │  HTTPS + Bearer JWT
       ▼
  ┌─────────────────────────────────────────────────┐
  │  API Gateway (FastAPI)                          │
  │  NEW: JWT middleware (Supabase RS256 JWKS)      │
  │  NEW: slowapi rate limiting (Redis-backed)      │
  │  NEW: Sentry + Logfire + OpenTelemetry          │
  │  NEW: GET /v1/wardrobe/items (paginated)        │
  │  NEW: GET /v1/wardrobe/items/{id}               │
  │  NEW: DELETE /v1/wardrobe/items/{id}            │
  │  NEW: POST /v1/feedback                         │
  │  NEW: GET/PUT /v1/users/me (profile)            │
  └─────────────────────────────────────────────────┘
       │
       ├── Redis (Upstash) — rate limiting, cache, task queue
       ├── Supabase — RLS policies enforced on all tables
       ├── Cloudflare R2 — signed URLs (1h TTL) in all responses
       └── Celery Beat — nightly pre-warm job (23:00 UTC)

  Observability Plane:
  Sentry → exception capture (FastAPI + Celery)
  Logfire → structured JSON logs (every request, every task)
  Prometheus → /metrics endpoint → Grafana Cloud dashboards
```

---

## SECTION 3 — ENVIRONMENT VARIABLES (Phase 4 additions)

Add to `.env`, `.env.example`, and `app/core/config.py`:

```env
# Supabase Auth (for JWT validation)
SUPABASE_JWKS_URL=https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json
SUPABASE_JWT_AUDIENCE=authenticated

# Observability
SENTRY_DSN=https://...@sentry.io/...
LOGFIRE_TOKEN=your-logfire-token
PROMETHEUS_METRICS_TOKEN=your-scrape-token   # bearer token for /metrics endpoint

# Rate limiting
RATE_LIMIT_UPLOAD=10/minute
RATE_LIMIT_RECOMMENDATION=30/minute
RATE_LIMIT_FEEDBACK=60/minute

# App environment
ENV=production   # local | staging | production

# Pre-warm schedule
PREWARM_CRON_UTC=23:00
```

---

## SECTION 4 — NEW FILE MANIFEST

### Files to CREATE
```
app/core/auth.py                          Supabase JWT middleware + CurrentUser dependency
app/core/rate_limit.py                    slowapi limiter configuration
app/core/observability.py                 Sentry + Logfire + OpenTelemetry init
app/api/v1/endpoints/wardrobe_read.py     GET /v1/wardrobe/items + GET + DELETE single item
app/api/v1/endpoints/feedback.py          POST /v1/feedback
app/api/v1/endpoints/users.py             GET /v1/users/me + PUT /v1/users/me
app/services/wardrobe_read.py             Paginated wardrobe query service
app/worker/beat_schedule.py               Celery Beat task definitions (pre-warm, cache eviction)
scripts/004_rls_policies.sql              Supabase RLS policy definitions for all tables
scripts/005_production_indexes.sql        Any missing production indexes
.github/workflows/ci.yml                  GitHub Actions CI/CD pipeline
Dockerfile                                Production-ready multi-stage Docker image
railway.toml                              Railway service definitions
tests/unit/test_auth.py                   Auth middleware unit tests
tests/unit/test_rate_limit.py             Rate limiter unit tests
tests/integration/test_wardrobe_read.py   Wardrobe list/read/delete integration tests
tests/integration/test_feedback.py        Feedback flow integration tests
```

### Files to MODIFY
```
main.py                        Add JWT middleware, rate limiter, observability init,
                               register all new routers, add /metrics endpoint
app/core/config.py             Add all Phase 4 env vars
requirements.txt               Add: sentry-sdk, logfire, prometheus-fastapi-instrumentator,
                               slowapi, python-jose[cryptography], httpx[http2]
requirements.lock              Regenerate
app/api/v1/endpoints/wardrobe.py    Remove user_id from request body; extract from JWT
app/api/v1/endpoints/recommendations.py  Same — remove user_id from body
docker-compose.yml             Add Celery Beat service; ensure worker rebuilt
```

---

## SECTION 5 — TASK EXECUTION PLAN

---

### ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
### TRACK A — AUTHENTICATION & SECURITY
### Priority: CRITICAL. No other track can go to production without this.
### Estimated time: 1.5 days
### ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

---

#### TASK A1 — Install auth and security dependencies

**Commands:**
```bash
pip install "python-jose[cryptography]>=3.3.0" "slowapi>=0.1.9" "httpx[http2]>=0.27.0"
pip freeze > requirements.lock
```

**`requirements.txt`** — append:
```
python-jose[cryptography]>=3.3.0
slowapi>=0.1.9
httpx[http2]>=0.27.0
```

**GATE:**
```bash
python -c "import jose, slowapi, httpx; print('auth deps ok')"
```

**COMMIT:** `chore: add auth and rate-limit dependencies`

---

#### TASK A2 — Build Supabase JWT auth middleware

**File to CREATE: `app/core/auth.py`**

Complete implementation:
```python
import uuid
import httpx
from typing import Annotated
from functools import lru_cache
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError, ExpiredSignatureError
from jose.backends import RSAKey
from app.core.config import settings
import logging

logger = logging.getLogger(__name__)
security = HTTPBearer()

@lru_cache(maxsize=1)
def get_jwks() -> dict:
    """Fetch and cache Supabase JWKS public keys. Cached in-process for 24h.
    Call get_jwks.cache_clear() to force refresh."""
    response = httpx.get(settings.SUPABASE_JWKS_URL, timeout=10)
    response.raise_for_status()
    return response.json()

def _get_rsa_key(token: str) -> dict:
    """Extract the matching RSA key from JWKS for the token's kid header."""
    jwks = get_jwks()
    try:
        header = jwt.get_unverified_header(token)
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token header")
    for key in jwks.get("keys", []):
        if key.get("kid") == header.get("kid"):
            return key
    # kid not found — JWKS may be stale; refresh once and retry
    get_jwks.cache_clear()
    jwks = get_jwks()
    for key in jwks.get("keys", []):
        if key.get("kid") == header.get("kid"):
            return key
    raise HTTPException(status_code=401, detail="Token signing key not found")

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> uuid.UUID:
    token = credentials.credentials
    try:
        rsa_key = _get_rsa_key(token)
        payload = jwt.decode(
            token,
            rsa_key,
            algorithms=["RS256"],
            audience=settings.SUPABASE_JWT_AUDIENCE,
            options={"verify_exp": True}
        )
        user_id_str = payload.get("sub")
        if not user_id_str:
            raise HTTPException(status_code=401, detail="Token missing subject claim")
        return uuid.UUID(user_id_str)
    except ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token has expired")
    except JWTError as e:
        logger.warning(f"JWT validation failed: {e}")
        raise HTTPException(status_code=401, detail="Token validation failed")
    except ValueError:
        raise HTTPException(status_code=401, detail="Invalid user ID in token")

# Clean dependency alias for all protected endpoints
CurrentUser = Annotated[uuid.UUID, Depends(get_current_user)]
```

**GATE:**
```bash
python -c "
import asyncio
from fastapi import HTTPException
from app.core.auth import get_current_user
from fastapi.security import HTTPAuthorizationCredentials

async def test():
    fake_creds = HTTPAuthorizationCredentials(scheme='Bearer', credentials='fake.token.value')
    try:
        await get_current_user(fake_creds)
        print('ERROR: should have raised 401')
    except HTTPException as e:
        assert e.status_code == 401, f'expected 401, got {e.status_code}'
        print(f'auth middleware: PASS — raises 401 on invalid token')

asyncio.run(test())
"
```

**COMMIT:** `feat: add Supabase RS256 JWT auth middleware with JWKS caching`

---

#### TASK A3 — Wire JWT middleware into all existing endpoints

**Files to MODIFY:**

`app/api/v1/endpoints/wardrobe.py` — replace `user_id` body param with JWT:
```python
# BEFORE (insecure):
async def upload_wardrobe_item(user_id: str = Form(...), file: UploadFile = File(...)):

# AFTER (secure):
from app.core.auth import CurrentUser
async def upload_wardrobe_item(
    current_user: CurrentUser,
    file: UploadFile = File(...),
    item_name: str = Form(default=None)
):
    user_id = current_user  # UUID extracted from JWT, not from request body
```

`app/api/v1/endpoints/recommendations.py` — same pattern:
```python
# Remove user_id from RecommendationRequest body
# Extract from: current_user: CurrentUser
```

`app/api/v1/endpoints/tasks.py` — add ownership check:
```python
async def get_task_status(task_id: str, current_user: CurrentUser):
    # After fetching task result, verify task belongs to current_user
    # Store user_id in task metadata at enqueue time for this check
```

**GATE:**
```bash
uvicorn main:app --reload &
sleep 3

# Test upload without auth → 401/403
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  http://localhost:8000/v1/wardrobe/upload \
  -F "file=@/dev/null;type=image/jpeg")
echo "upload no auth: $STATUS"   # expected: 403 (HTTPBearer returns 403 on missing header)

# Test recommendations without auth → 403
STATUS2=$(curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:8000/v1/recommendations/today)
echo "rec no auth: $STATUS2"   # expected: 403

kill %1
```
Expected: both return 403.

**COMMIT:** `feat: enforce JWT auth on all existing endpoints, remove user_id from request bodies`

---

#### TASK A4 — Configure rate limiting

**File to CREATE: `app/core/rate_limit.py`**
```python
from slowapi import Limiter
from slowapi.util import get_remote_address
from fastapi import Request
from app.core.config import settings

def get_user_id_or_ip(request: Request) -> str:
    """Use authenticated user ID as rate limit key if available, else IP."""
    user_id = getattr(request.state, "user_id", None)
    return str(user_id) if user_id else get_remote_address(request)

limiter = Limiter(
    key_func=get_user_id_or_ip,
    storage_uri=settings.REDIS_URL,
    default_limits=[]
)
```

**`main.py`** — add slowapi integration:
```python
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from app.core.rate_limit import limiter

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
```

Apply decorators to endpoints:
```python
# wardrobe upload — 10/minute per user
@router.post("/upload")
@limiter.limit("10/minute")
async def upload_wardrobe_item(request: Request, current_user: CurrentUser, ...):

# recommendations — 30/minute per user
@router.get("/today")
@limiter.limit("30/minute")
async def get_recommendation_today(request: Request, current_user: CurrentUser, ...):

# feedback — 60/minute per user
@router.post("/")
@limiter.limit("60/minute")
async def submit_feedback(request: Request, current_user: CurrentUser, ...):
```

**GATE:**
```bash
python -c "
from app.core.rate_limit import limiter
print(f'rate limiter: PASS — key_func={limiter.key_func.__name__}')
"
```

**COMMIT:** `feat: add slowapi rate limiting (Redis-backed, user-scoped)`

---

#### TASK A5 — Deploy Supabase RLS policies

**File to CREATE: `scripts/004_rls_policies.sql`**
```sql
-- ══════════════════════════════════════════════════
-- VESTIMATE — Row-Level Security Policies
-- Run against Supabase production project
-- ══════════════════════════════════════════════════

-- wardrobe_items
ALTER TABLE wardrobe_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "wardrobe_items_user_isolation"
  ON wardrobe_items FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- feedback_events
ALTER TABLE feedback_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "feedback_events_user_isolation"
  ON feedback_events FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- recommendation_cache
ALTER TABLE recommendation_cache ENABLE ROW LEVEL SECURITY;
CREATE POLICY "recommendation_cache_user_isolation"
  ON recommendation_cache FOR ALL
  USING (user_id = auth.uid());

-- outfits
ALTER TABLE outfits ENABLE ROW LEVEL SECURITY;
CREATE POLICY "outfits_user_isolation"
  ON outfits FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- manual_review_queue
ALTER TABLE manual_review_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY "review_queue_user_isolation"
  ON manual_review_queue FOR SELECT
  USING (user_id = auth.uid());

-- event_log (read-only for users; write is service_role only)
ALTER TABLE event_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "event_log_user_read"
  ON event_log FOR SELECT
  USING (user_id = auth.uid());

-- users (users can read/update only their own row)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users_self_access"
  ON users FOR ALL
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- prompt_versions (read-only for all authenticated users; write is service_role)
ALTER TABLE prompt_versions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "prompt_versions_read_all"
  ON prompt_versions FOR SELECT
  USING (auth.role() = 'authenticated');
```

**Command to apply:**
```bash
python -c "
import asyncio, asyncpg
from app.core.config import settings

async def run():
    url = settings.SUPABASE_DATABASE_URL.replace('postgresql+asyncpg://', 'postgresql://')
    conn = await asyncpg.connect(url)
    with open('scripts/004_rls_policies.sql') as f:
        await conn.execute(f.read())
    print('RLS policies applied')
    await conn.close()

asyncio.run(run())
"
```

**GATE:**
```bash
python -c "
import asyncio, asyncpg
from app.core.config import settings

async def check():
    url = settings.SUPABASE_DATABASE_URL.replace('postgresql+asyncpg://', 'postgresql://')
    conn = await asyncpg.connect(url)
    # Verify RLS enabled on all critical tables
    tables = ['wardrobe_items', 'feedback_events', 'recommendation_cache', 'outfits', 'users']
    for t in tables:
        result = await conn.fetchval(
            f\"SELECT rowsecurity FROM pg_tables WHERE tablename = '{t}' AND schemaname = 'public'\"
        )
        status = 'ENABLED' if result else 'DISABLED'
        print(f'  RLS on {t}: {status}')
    await conn.close()

asyncio.run(check())
"
```
Expected: all 5 tables show `ENABLED`.

**COMMIT:** `feat: deploy RLS policies for all Supabase tables`

---

### ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
### TRACK B — MISSING API SURFACE
### Builds all endpoints required by the mobile client.
### Estimated time: 1.5 days
### ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

---

#### TASK B1 — Build wardrobe read service

**File to CREATE: `app/services/wardrobe_read.py`**

Complete implementation:
```python
import uuid
from typing import Optional
from dataclasses import dataclass
import asyncpg
from app.core.config import settings

@dataclass
class WardrobeItem:
    id: uuid.UUID
    image_url: str
    category: Optional[str]
    material: Optional[str]
    fit: Optional[str]
    colors: list[str]
    item_name: Optional[str]
    needs_review: bool
    status: str
    last_worn_at: Optional[str]
    wear_count: int
    created_at: str

@dataclass
class WardrobeListResult:
    items: list[WardrobeItem]
    total: int
    page: int
    limit: int

async def list_wardrobe_items(
    user_id: uuid.UUID,
    page: int = 1,
    limit: int = 20,
    category: Optional[str] = None,
    status: str = "active"
) -> WardrobeListResult:
    """Paginated wardrobe retrieval. Generates signed R2 URLs for each item."""
    url = settings.SUPABASE_DATABASE_URL.replace("postgresql+asyncpg://", "postgresql://")
    conn = await asyncpg.connect(url)
    try:
        offset = (page - 1) * limit
        where_clauses = ["user_id = $1", "status = $2"]
        params = [user_id, status]

        if category:
            where_clauses.append(f"category = ${len(params) + 1}")
            params.append(category)

        where_sql = " AND ".join(where_clauses)
        count_params = params[:len(params)]

        total = await conn.fetchval(
            f"SELECT COUNT(*) FROM wardrobe_items WHERE {where_sql}",
            *count_params
        )
        rows = await conn.fetch(
            f"""SELECT id, raw_image_key, category, material, fit, colors, item_name,
                       needs_review, status, last_worn_at, wear_count, created_at
                FROM wardrobe_items
                WHERE {where_sql}
                ORDER BY created_at DESC
                LIMIT ${len(params) + 1} OFFSET ${len(params) + 2}""",
            *params, limit, offset
        )
        from app.services.storage import generate_signed_url
        items = [
            WardrobeItem(
                id=row["id"],
                image_url=generate_signed_url(row["raw_image_key"], expiry_seconds=3600),
                category=row["category"],
                material=row["material"],
                fit=row["fit"],
                colors=list(row["colors"] or []),
                item_name=row["item_name"],
                needs_review=row["needs_review"],
                status=row["status"],
                last_worn_at=row["last_worn_at"].isoformat() if row["last_worn_at"] else None,
                wear_count=row["wear_count"] or 0,
                created_at=row["created_at"].isoformat()
            )
            for row in rows
        ]
        return WardrobeListResult(items=items, total=total, page=page, limit=limit)
    finally:
        await conn.close()

async def get_wardrobe_item(user_id: uuid.UUID, item_id: uuid.UUID) -> Optional[WardrobeItem]:
    """Fetch single item with ownership check."""
    url = settings.SUPABASE_DATABASE_URL.replace("postgresql+asyncpg://", "postgresql://")
    conn = await asyncpg.connect(url)
    try:
        row = await conn.fetchrow(
            """SELECT id, raw_image_key, category, material, fit, colors, item_name,
                      needs_review, status, last_worn_at, wear_count, created_at
               FROM wardrobe_items
               WHERE id = $1 AND user_id = $2""",
            item_id, user_id
        )
        if not row:
            return None
        from app.services.storage import generate_signed_url
        return WardrobeItem(
            id=row["id"],
            image_url=generate_signed_url(row["raw_image_key"], expiry_seconds=3600),
            category=row["category"], material=row["material"], fit=row["fit"],
            colors=list(row["colors"] or []), item_name=row["item_name"],
            needs_review=row["needs_review"], status=row["status"],
            last_worn_at=row["last_worn_at"].isoformat() if row["last_worn_at"] else None,
            wear_count=row["wear_count"] or 0,
            created_at=row["created_at"].isoformat()
        )
    finally:
        await conn.close()

async def archive_wardrobe_item(user_id: uuid.UUID, item_id: uuid.UUID) -> bool:
    """Soft-delete: sets status = 'archived'. Returns False if item not found."""
    url = settings.SUPABASE_DATABASE_URL.replace("postgresql+asyncpg://", "postgresql://")
    conn = await asyncpg.connect(url)
    try:
        result = await conn.execute(
            "UPDATE wardrobe_items SET status = 'archived', updated_at = NOW() "
            "WHERE id = $1 AND user_id = $2 AND status != 'archived'",
            item_id, user_id
        )
        return result != "UPDATE 0"
    finally:
        await conn.close()
```

**GATE:**
```bash
python -c "
from app.services.wardrobe_read import list_wardrobe_items, get_wardrobe_item, archive_wardrobe_item
import inspect
for fn in [list_wardrobe_items, get_wardrobe_item, archive_wardrobe_item]:
    assert inspect.iscoroutinefunction(fn), f'{fn.__name__} not async'
print('wardrobe_read service: PASS — all 3 functions are async and importable')
"
```

**COMMIT:** `feat: add wardrobe read service (list, get, archive)`

---

#### TASK B2 — Build wardrobe read endpoints

**File to CREATE: `app/api/v1/endpoints/wardrobe_read.py`**
```python
import uuid
from typing import Optional
from fastapi import APIRouter, HTTPException, Query
from app.core.auth import CurrentUser
from app.services.wardrobe_read import list_wardrobe_items, get_wardrobe_item, archive_wardrobe_item
from app.core.rate_limit import limiter
from fastapi import Request

router = APIRouter()

@router.get("/items")
@limiter.limit("60/minute")
async def get_wardrobe_items(
    request: Request,
    current_user: CurrentUser,
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=20, ge=1, le=100),
    category: Optional[str] = Query(default=None),
    status: str = Query(default="active")
):
    """Returns paginated wardrobe items for the authenticated user.
    Each item includes a signed R2 image URL valid for 1 hour."""
    result = await list_wardrobe_items(current_user, page, limit, category, status)
    return {
        "items": [item.__dict__ for item in result.items],
        "total": result.total,
        "page": result.page,
        "limit": result.limit
    }

@router.get("/items/{item_id}")
async def get_single_wardrobe_item(item_id: uuid.UUID, current_user: CurrentUser):
    """Returns a single wardrobe item. Returns 404 if not found or not owned by user."""
    item = await get_wardrobe_item(current_user, item_id)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return item.__dict__

@router.delete("/items/{item_id}", status_code=204)
async def delete_wardrobe_item(item_id: uuid.UUID, current_user: CurrentUser):
    """Soft-deletes a wardrobe item (sets status = 'archived').
    Archived items are excluded from all recommendation queries."""
    success = await archive_wardrobe_item(current_user, item_id)
    if not success:
        raise HTTPException(status_code=404, detail="Item not found or already archived")
```

**`main.py`** — add router:
```python
from app.api.v1.endpoints.wardrobe_read import router as wardrobe_read_router
app.include_router(wardrobe_read_router, prefix="/v1/wardrobe", tags=["wardrobe"])
```

**GATE:**
```bash
uvicorn main:app --reload &
sleep 3

# No auth → 403
STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/v1/wardrobe/items)
echo "wardrobe items no auth: $STATUS"   # expected: 403

# Route exists (check OpenAPI)
STATUS2=$(curl -s http://localhost:8000/openapi.json | python -c "
import sys, json
spec = json.load(sys.stdin)
paths = list(spec['paths'].keys())
required = ['/v1/wardrobe/items', '/v1/wardrobe/items/{item_id}']
for r in required:
    assert r in paths, f'missing route: {r}'
print('routes registered: PASS')
")

kill %1
```

**COMMIT:** `feat: add GET /v1/wardrobe/items, GET /v1/wardrobe/items/{id}, DELETE /v1/wardrobe/items/{id}`

---

#### TASK B3 — Build feedback endpoint

**File to CREATE: `app/api/v1/endpoints/feedback.py`**

Implementation requirements:
- `POST /v1/feedback`
- Validates `recommendation_id` exists in `recommendation_cache` — if not, returns 404
- Inserts into `feedback_events`: user_id, recommendation_id, action, item_ids, created_at
- If `action == "worn"` AND item_ids provided:
  - `UPDATE wardrobe_items SET last_worn_at = NOW(), wear_count = wear_count + 1 WHERE id = ANY($1) AND user_id = $2`
  - Invalidate Redis cache: `DEL rec:{user_id}:{today}:*` (use SCAN + DEL pattern)
- Returns 204 on success

**`main.py`** — add:
```python
from app.api.v1.endpoints.feedback import router as feedback_router
app.include_router(feedback_router, prefix="/v1", tags=["feedback"])
```

**GATE:**
```bash
python -c "
from app.api.v1.endpoints.feedback import router
routes = [(r.path, list(r.methods)) for r in router.routes]
assert any('/feedback' in r[0] for r in routes), 'feedback route missing'
print(f'feedback router: PASS — {routes}')
"
```

**COMMIT:** `feat: add POST /v1/feedback with worn-tracking and cache invalidation`

---

#### TASK B4 — Build user profile endpoints

**File to CREATE: `app/api/v1/endpoints/users.py`**

Endpoints:
```
GET /v1/users/me
  → Returns: { id, email, display_name, city, timezone, onboarding_complete, created_at }
  → 404 if user row not in DB (first-login scenario)

PUT /v1/users/me
  → Body: { display_name?, city?, timezone?, onboarding_complete? }
  → Validates city against OpenWeatherMap (call weather API with the city string before write)
  → Updates users table
  → Returns updated user object
  → 422 if city is invalid (OWM returns 404)

POST /v1/users/me/onboard
  → Called once after registration to create the users row
  → Body: { email, display_name, city, timezone }
  → INSERT INTO users — idempotent (ON CONFLICT DO UPDATE)
  → Returns 201 with user object
```

**`main.py`** — add:
```python
from app.api.v1.endpoints.users import router as users_router
app.include_router(users_router, prefix="/v1/users", tags=["users"])
```

**GATE:**
```bash
python -c "
from app.api.v1.endpoints.users import router
routes = [r.path for r in router.routes]
required = ['/v1/users/me', '/v1/users/me/onboard']
for r in required:
    assert any(r.endswith(p.split('/')[-1]) for p in routes), f'missing: {r}'
print(f'users router: PASS — routes: {routes}')
"
```

**COMMIT:** `feat: add GET/PUT /v1/users/me and POST /v1/users/me/onboard`

---

#### TASK B5 — Wire signed R2 URLs into recommendation response

The recommendation response currently returns `image_key` strings from R2 object keys.
The architecture requires signed URLs with 1-hour TTL in every response.

**`app/services/storage.py`** — add if not present:
```python
def generate_signed_url(object_key: str, expiry_seconds: int = 3600) -> str:
    """Generate a time-limited presigned GET URL for a private R2 object."""
    url = s3_client.generate_presigned_url(
        "get_object",
        Params={"Bucket": settings.R2_BUCKET_NAME, "Key": object_key},
        ExpiresIn=expiry_seconds
    )
    return url
```

**`app/api/v1/endpoints/recommendations.py`** — after recommendation is generated,
replace all `image_key` fields with signed URLs before returning:
```python
from app.services.storage import generate_signed_url

# After generating recommendation rec:
rec.outfit.top.image_url    = generate_signed_url(top_item.raw_image_key)
rec.outfit.bottom.image_url = generate_signed_url(bottom_item.raw_image_key)
rec.outfit.shoes.image_url  = generate_signed_url(shoes_item.raw_image_key)
```

**GATE:**
```bash
python -c "
from app.services.storage import generate_signed_url
import inspect
assert inspect.isfunction(generate_signed_url), 'not a function'
# Verify signature accepts object_key and expiry_seconds
sig = inspect.signature(generate_signed_url)
assert 'object_key' in sig.parameters, 'missing object_key param'
assert 'expiry_seconds' in sig.parameters, 'missing expiry_seconds param'
print('generate_signed_url: PASS')
"
```

**COMMIT:** `feat: wire signed R2 URLs into recommendation and wardrobe responses`

---

### ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
### TRACK C — OBSERVABILITY STACK
### Prerequisite: Track A complete.
### Estimated time: 1 day
### ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

---

#### TASK C1 — Install observability dependencies

```bash
pip install "sentry-sdk[fastapi]>=2.0.0" "logfire[fastapi]>=0.40.0" \
            "prometheus-fastapi-instrumentator>=6.1.0" "opentelemetry-sdk>=1.24.0"
pip freeze > requirements.lock
```

**`requirements.txt`** — append:
```
sentry-sdk[fastapi]>=2.0.0
logfire[fastapi]>=0.40.0
prometheus-fastapi-instrumentator>=6.1.0
opentelemetry-sdk>=1.24.0
```

**GATE:**
```bash
python -c "import sentry_sdk, logfire, prometheus_fastapi_instrumentator, opentelemetry; print('obs deps ok')"
```

**COMMIT:** `chore: add observability dependencies (sentry, logfire, prometheus, otel)`

---

#### TASK C2 — Build observability initialisation module

**File to CREATE: `app/core/observability.py`**
```python
import sentry_sdk
import logfire
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.celery import CeleryIntegration
from sentry_sdk.integrations.asyncpg import AsyncPGIntegration
from prometheus_fastapi_instrumentator import Instrumentator
from fastapi import FastAPI
from app.core.config import settings
import logging

logger = logging.getLogger(__name__)

def init_sentry():
    if not settings.SENTRY_DSN:
        logger.warning("SENTRY_DSN not set — exception tracking disabled")
        return
    sentry_sdk.init(
        dsn=settings.SENTRY_DSN,
        environment=settings.ENV,
        integrations=[
            FastApiIntegration(transaction_style="endpoint"),
            CeleryIntegration(monitor_beat_tasks=True),
            AsyncPGIntegration(),
        ],
        traces_sample_rate=0.1,    # 10% of requests traced (cost control)
        profiles_sample_rate=0.05, # 5% profiling
        send_default_pii=False,    # GDPR: no PII in Sentry payloads
    )
    logger.info(f"Sentry initialised — env={settings.ENV}")

def init_logfire(app: FastAPI):
    if not settings.LOGFIRE_TOKEN:
        logger.warning("LOGFIRE_TOKEN not set — structured logging disabled")
        return
    logfire.configure(token=settings.LOGFIRE_TOKEN, service_name="vestimate-api")
    logfire.instrument_fastapi(app)
    logger.info("Logfire instrumentation active")

def init_prometheus(app: FastAPI):
    instrumentator = Instrumentator(
        should_group_status_codes=False,
        should_ignore_untemplated=True,
        should_instrument_requests_inprogress=True,
        excluded_handlers=["/health", "/metrics"],
    )
    instrumentator.instrument(app)
    instrumentator.expose(
        app,
        endpoint="/metrics",
        include_in_schema=False,
        # Secure /metrics behind a bearer token to prevent public scraping
        dependencies=[]  # Add token check dependency if needed
    )
    logger.info("Prometheus metrics exposed at /metrics")

def init_all(app: FastAPI):
    """Call once at application startup."""
    init_sentry()
    init_logfire(app)
    init_prometheus(app)
```

**`main.py`** — add to startup:
```python
from app.core.observability import init_all

# After app = FastAPI(...):
@app.on_event("startup")
async def startup():
    init_all(app)
```

**GATE:**
```bash
python -c "
from app.core.observability import init_sentry, init_logfire, init_prometheus, init_all
import inspect
for fn in [init_sentry, init_logfire, init_prometheus, init_all]:
    print(f'  {fn.__name__}: importable ✓')
print('observability module: PASS')
"
```

**COMMIT:** `feat: add observability init module (Sentry, Logfire, Prometheus)`

---

#### TASK C3 — Add structured logging to all service functions

Add `logfire` spans to the three hottest code paths:

**`app/services/recommendation.py`** — wrap the full pipeline:
```python
import logfire

async def generate_recommendation(context, candidates, settings) -> OutfitRecommendation:
    with logfire.span("recommendation.generate", user_id=str(context.user_id),
                       weather=context.weather.bucket.value,
                       occasion=context.occasion.tag.value):
        # ... existing pipeline code ...
        with logfire.span("recommendation.llm_call"):
            # GPT call here
            pass
        logfire.info("recommendation.complete",
                     from_cache=False,
                     confidence=rec.confidence,
                     fallback_used=(rec.narrative is None))
        return rec
```

**`app/worker/tasks.py`** — wrap the ingestion task:
```python
import logfire

@celery_app.task(bind=True, max_retries=3)
def ingest_garment(self, user_id: str, object_key: str, item_id: str):
    with logfire.span("worker.ingest_garment", user_id=user_id, item_id=item_id):
        # ... existing pipeline ...
        logfire.info("worker.ingest_complete", item_id=item_id, category=category)
```

**GATE:**
```bash
python -c "
import logfire
from app.services.recommendation import generate_recommendation
from app.worker.tasks import ingest_garment
import inspect
# Verify logfire import didn't break anything
print('logfire instrumentation: PASS — modules import cleanly')
"
```

**COMMIT:** `feat: add logfire structured logging spans to recommendation and worker pipelines`

---

#### TASK C4 — Define Grafana dashboard specification

**File to CREATE: `docs/grafana_dashboards.md`**

Document the 6 dashboards to build in Grafana Cloud:

```markdown
# Vestimate Grafana Dashboards

## Dashboard 1: Recommendation Engine Health
Panels:
- Cache hit ratio (target: > 80%) — metric: ratio of requests with cache_hit=true
- p50 / p95 / p99 recommendation endpoint latency (ms)
- OpenAI API calls per hour (target: < 20% of total requests)
- Fallback recommendation rate (GPT unavailable events)

## Dashboard 2: Ingestion Pipeline
Panels:
- Celery task success rate (%) over time
- Celery task duration p50/p95 (seconds) — segment + embed separately
- Task queue depth (Redis LLEN celery)
- Failed items rate (status = 'failed' inserts per hour)
- Manual review queue depth (needs_review = true unreviewed)

## Dashboard 3: API Gateway
Panels:
- Total requests per minute (all endpoints)
- Error rate by endpoint (4xx, 5xx)
- Rate limit hits per user (429 responses)
- Authentication failures (401/403 count)

## Dashboard 4: Infrastructure
Panels:
- Railway API server memory/CPU
- Railway Celery worker memory/CPU
- Redis memory usage vs. maxmemory limit
- Modal invocations and cold start frequency

## Dashboard 5: Product Metrics (Alpha)
Panels:
- Daily active recommendations generated
- Feedback action breakdown (worn / skipped / saved) — pie chart
- Items ingested per day
- Users with 0 wardrobe items (stuck in onboarding)

## Dashboard 6: Cost Tracker
Panels:
- OpenAI token usage → estimated daily/monthly cost
- Modal GPU seconds consumed → cost
- R2 storage usage and egress
- Total estimated monthly cost gauge vs. $200 budget
```

**GATE:**
```bash
ls docs/grafana_dashboards.md && echo "dashboard spec: PASS — file exists"
```

**COMMIT:** `docs: add Grafana dashboard specification for Alpha launch`

---

### ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
### TRACK D — INFRASTRUCTURE & DEPLOYMENT
### Prerequisite: Tracks A, B, C complete.
### Estimated time: 1.5 days
### ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

---

#### TASK D1 — Write production Dockerfile

**File to CREATE: `Dockerfile`**
```dockerfile
# ── Stage 1: Builder ──────────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libpq-dev gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# ── Stage 2: Runtime ─────────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

WORKDIR /app

# Runtime system dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Copy installed packages from builder
COPY --from=builder /root/.local /root/.local
ENV PATH=/root/.local/bin:$PATH

# Copy application code
COPY . .

# Non-root user for security
RUN useradd -m -u 1001 vestimate && chown -R vestimate:vestimate /app
USER vestimate

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD python -c "import httpx; httpx.get('http://localhost:${PORT:-8000}/health').raise_for_status()"

EXPOSE 8000

# Default: API server. Override CMD for worker.
CMD gunicorn app.main:app \
    --workers 2 \
    --worker-class uvicorn.workers.UvicornWorker \
    --bind 0.0.0.0:${PORT:-8000} \
    --timeout 120 \
    --graceful-timeout 30 \
    --access-logfile - \
    --error-logfile -
```

**GATE:**
```bash
docker build -t vestimate:test .
docker run --rm vestimate:test python -c "import app.main; print('image builds and imports cleanly: PASS')"
```

**COMMIT:** `chore: add production multi-stage Dockerfile`

---

#### TASK D2 — Configure Railway deployment

**File to CREATE: `railway.toml`**
```toml
[build]
builder = "DOCKERFILE"
dockerfilePath = "Dockerfile"

[[services]]
name = "api-server"
[services.deploy]
startCommand = "gunicorn app.main:app -w 2 -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:$PORT --timeout 120"
healthcheckPath = "/health"
healthcheckTimeout = 30

[[services]]
name = "celery-worker"
[services.deploy]
startCommand = "celery -A app.worker.tasks worker --loglevel=info --concurrency=4 --pool=prefork"
restartPolicyType = "ON_FAILURE"
restartPolicyMaxRetries = 3

[[services]]
name = "celery-beat"
[services.deploy]
startCommand = "celery -A app.worker.beat_schedule beat --loglevel=info"
restartPolicyType = "ON_FAILURE"
restartPolicyMaxRetries = 3
```

**File to CREATE: `app/worker/beat_schedule.py`**
```python
from celery.schedules import crontab
from app.worker.celery_app import celery_app

celery_app.conf.beat_schedule = {
    # Evict expired recommendation cache keys from Supabase (Redis expires itself)
    "evict-expired-recommendation-cache": {
        "task": "app.worker.tasks.evict_expired_recommendations",
        "schedule": crontab(minute=0, hour="*/6"),  # every 6 hours
    },
    # Pre-warm recommendations for users active in last 7 days
    "prewarm-recommendations": {
        "task": "app.worker.tasks.prewarm_recommendations",
        "schedule": crontab(minute=0, hour=23),  # 23:00 UTC daily
    },
}
celery_app.conf.timezone = "UTC"
```

Add these two tasks to `app/worker/tasks.py`:
```python
@celery_app.task
def evict_expired_recommendations():
    """Remove recommendation_cache rows older than 24h."""
    # asyncpg DELETE WHERE generated_at < NOW() - INTERVAL '24 hours'
    ...

@celery_app.task
def prewarm_recommendations():
    """Enqueue recommendation pre-generation for recently active users."""
    # Fetch users WHERE last_active_at > NOW() - INTERVAL '7 days'
    # For each: trigger get_recommendation_today with force_refresh=True
    ...
```

**GATE:**
```bash
python -c "
from app.worker.beat_schedule import celery_app
schedule = celery_app.conf.beat_schedule
assert 'evict-expired-recommendation-cache' in schedule
assert 'prewarm-recommendations' in schedule
print(f'beat schedule: PASS — {len(schedule)} scheduled tasks registered')
"
```

**COMMIT:** `feat: add Railway deployment config and Celery Beat schedule (eviction + pre-warm)`

---

#### TASK D3 — Build GitHub Actions CI/CD pipeline

**File to CREATE: `.github/workflows/ci.yml`**
```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [main, staging]
  pull_request:
    branches: [main]

env:
  PYTHON_VERSION: "3.12"

jobs:
  # ── Lint & Type Check ───────────────────────────────────────────────────────
  lint:
    name: Lint & Type Check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}
          cache: pip
      - run: pip install ruff mypy
      - run: ruff check app/ tests/
      - run: mypy app/ --ignore-missing-imports --strict-optional

  # ── Unit Tests ──────────────────────────────────────────────────────────────
  unit-tests:
    name: Unit Tests
    runs-on: ubuntu-latest
    services:
      redis:
        image: redis:7-alpine
        ports: ["6379:6379"]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}
          cache: pip
      - run: pip install -r requirements.txt -r requirements-dev.txt
      - run: pytest tests/unit -v --cov=app --cov-report=xml --cov-fail-under=70
        env:
          REDIS_URL: redis://localhost:6379/0
          ENV: test
      - uses: codecov/codecov-action@v4
        with:
          file: coverage.xml

  # ── Integration Tests ────────────────────────────────────────────────────────
  integration-tests:
    name: Integration Tests (staging)
    runs-on: ubuntu-latest
    needs: unit-tests
    if: github.ref == 'refs/heads/main' || github.ref == 'refs/heads/staging'
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}
          cache: pip
      - run: pip install -r requirements.txt -r requirements-dev.txt
      - run: pytest tests/integration -v --timeout=60
        env:
          SUPABASE_URL: ${{ secrets.STAGING_SUPABASE_URL }}
          SUPABASE_SERVICE_KEY: ${{ secrets.STAGING_SUPABASE_SERVICE_KEY }}
          SUPABASE_DATABASE_URL: ${{ secrets.STAGING_SUPABASE_DATABASE_URL }}
          REDIS_URL: ${{ secrets.STAGING_REDIS_URL }}
          R2_ACCOUNT_ID: ${{ secrets.STAGING_R2_ACCOUNT_ID }}
          R2_ACCESS_KEY_ID: ${{ secrets.STAGING_R2_ACCESS_KEY_ID }}
          R2_SECRET_ACCESS_KEY: ${{ secrets.STAGING_R2_SECRET_ACCESS_KEY }}
          R2_BUCKET_NAME: ${{ secrets.STAGING_R2_BUCKET_NAME }}
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
          WEATHER_API_KEY: ${{ secrets.WEATHER_API_KEY }}
          ENV: staging

  # ── Deploy to Railway ────────────────────────────────────────────────────────
  deploy:
    name: Deploy to Railway (production)
    runs-on: ubuntu-latest
    needs: [lint, unit-tests, integration-tests]
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - name: Install Railway CLI
        run: npm install -g @railway/cli
      - name: Deploy API server
        run: railway up --service api-server --detach
        env:
          RAILWAY_TOKEN: ${{ secrets.RAILWAY_TOKEN }}
      - name: Deploy Celery worker
        run: railway up --service celery-worker --detach
        env:
          RAILWAY_TOKEN: ${{ secrets.RAILWAY_TOKEN }}
      - name: Deploy Celery Beat
        run: railway up --service celery-beat --detach
        env:
          RAILWAY_TOKEN: ${{ secrets.RAILWAY_TOKEN }}
      - name: Verify deployment health
        run: |
          sleep 30
          curl --fail https://api.vestimate.app/health || exit 1
          echo "Production deployment verified ✓"
```

**GATE:**
```bash
# Validate YAML syntax
python -c "
import yaml
with open('.github/workflows/ci.yml') as f:
    spec = yaml.safe_load(f)
jobs = list(spec['jobs'].keys())
print(f'CI/CD pipeline: PASS — jobs: {jobs}')
"
```

**COMMIT:** `chore: add GitHub Actions CI/CD pipeline (lint + unit + integration + deploy)`

---

#### TASK D4 — Write test suite for Phase 4 additions

**File to CREATE: `tests/unit/test_auth.py`**

Cover:
- `get_current_user` raises 401 on expired token
- `get_current_user` raises 401 on malformed token
- `get_current_user` raises 401 on missing subject claim
- `_get_rsa_key` refreshes JWKS cache on key-not-found
- `get_jwks` is called only once for multiple requests (LRU cache working)

**File to CREATE: `tests/unit/test_wardrobe_read.py`**

Cover:
- `list_wardrobe_items` returns correct pagination metadata
- `list_wardrobe_items` applies category filter correctly
- `archive_wardrobe_item` returns False when item not found
- Signed URL is included in every item response (non-empty string)

**File to CREATE: `tests/integration/test_feedback.py`**

Cover:
- `POST /v1/feedback` action=worn → updates `last_worn_at` and `wear_count` in DB
- `POST /v1/feedback` action=worn → invalidates Redis recommendation cache
- `POST /v1/feedback` action=skipped → does NOT update wear tracking
- `POST /v1/feedback` with unknown `recommendation_id` → 404
- `POST /v1/feedback` without auth → 403

**GATE:**
```bash
pytest tests/unit/test_auth.py tests/unit/test_wardrobe_read.py -v --tb=short
```
Expected: all PASS, 0 failures.

**COMMIT:** `test: add Phase 4 unit tests (auth middleware, wardrobe read, feedback flow)`

---

### ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
### PHASE 4 FINAL CHECKLIST (run after all tracks complete)
### ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Run every check below. Report PASS or FAIL with exact command output as evidence.
Do not declare completion until all 20 items are PASS.

```
SECURITY
[ ] All endpoints return 403 without Authorization header
[ ] All endpoints extract user_id from JWT, not from request body
[ ] RLS enabled on: wardrobe_items, feedback_events, recommendation_cache, outfits, users
[ ] Rate limiting returns 429 after limit exceeded (test upload endpoint at 11 req/min)

API COMPLETENESS
[ ] GET /v1/wardrobe/items → 200 with paginated list (with auth)
[ ] GET /v1/wardrobe/items/{id} → 200 with signed image URL (with auth)
[ ] DELETE /v1/wardrobe/items/{id} → 204 (soft archive)
[ ] GET /v1/wardrobe/items/{id} after DELETE → 404 (archived = invisible)
[ ] POST /v1/feedback action=worn → 204, last_worn_at updated in Supabase
[ ] POST /v1/feedback → Redis rec cache invalidated (redis-cli confirms key gone)
[ ] GET /v1/users/me → 200 with user profile
[ ] PUT /v1/users/me with invalid city → 422

OBSERVABILITY
[ ] uvicorn main:app starts with no Sentry/Logfire import errors
[ ] GET /metrics → 200 with Prometheus text format
[ ] Sentry captures a test exception: sentry_sdk.capture_message("phase4_test")
[ ] Logfire shows structured span in dashboard after one recommendation request

DEPLOYMENT
[ ] docker build -t vestimate:prod . → successful
[ ] docker run vestimate:prod → /health returns 200
[ ] pytest tests/unit/ -v → all PASS
[ ] pytest tests/integration/ -v → all PASS
[ ] .github/workflows/ci.yml YAML validates cleanly
```

On all 20 PASS, output:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Phase 4 complete. Backend is production-ready for Alpha.
Tracks complete: A (auth+security) · B (API surface) ·
                 C (observability) · D (infrastructure)
Total: 18 tasks · 18 gates · 18 commits.
Ready for React Native frontend integration.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## SECTION 6 — COMMIT LOG REFERENCE

```
[A1]  chore: add auth and rate-limit dependencies
[A2]  feat: add Supabase RS256 JWT auth middleware with JWKS caching
[A3]  feat: enforce JWT auth on all existing endpoints, remove user_id from request bodies
[A4]  feat: add slowapi rate limiting (Redis-backed, user-scoped)
[A5]  feat: deploy RLS policies for all Supabase tables
[B1]  feat: add wardrobe read service (list, get, archive)
[B2]  feat: add GET /v1/wardrobe/items, GET /v1/wardrobe/items/{id}, DELETE
[B3]  feat: add POST /v1/feedback with worn-tracking and cache invalidation
[B4]  feat: add GET/PUT /v1/users/me and POST /v1/users/me/onboard
[B5]  feat: wire signed R2 URLs into recommendation and wardrobe responses
[C1]  chore: add observability dependencies (sentry, logfire, prometheus, otel)
[C2]  feat: add observability init module (Sentry, Logfire, Prometheus)
[C3]  feat: add logfire structured logging spans to recommendation and worker pipelines
[C4]  docs: add Grafana dashboard specification for Alpha launch
[D1]  chore: add production multi-stage Dockerfile
[D2]  feat: add Railway deployment config and Celery Beat schedule
[D3]  chore: add GitHub Actions CI/CD pipeline
[D4]  test: add Phase 4 unit tests (auth middleware, wardrobe read, feedback flow)
```

---

## SECTION 7 — PHASE 5 PREVIEW (do not implement)

Phase 5 is the mobile client (React Native + Expo) and Google Calendar OAuth integration.
The backend APIs are designed and typed for this integration. No backend changes are
expected in Phase 5 except:
- Add `POST /v1/users/me/google-oauth/callback` endpoint (OAuth token exchange)
- Add `GET /v1/users/me/google-oauth/revoke` endpoint
- Potentially add `GET /v1/recommendations/history` if the mobile UI requires it

The following are explicitly deferred to Phase 5 or post-Alpha:
- Google Calendar OAuth token exchange and storage
- Push notifications (deferred from architecture constraints)
- Manual review queue admin UI
- Multi-outfit generation (3 alternatives)
- Accessories/outerwear/dresses in outfit assembly
- GDPR data export endpoint (`GET /v1/users/me/export`)
- A/B testing infrastructure for prompt_versions

---

*End of VESTIMATE_PHASE4_ROADMAP.md*
*18 tasks · 4 tracks · 18 gates · 18 commits*
*Prerequisite: Phase 3 complete and all gates green*
