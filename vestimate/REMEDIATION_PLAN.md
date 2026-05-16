# VESTIMATE — Remediation & Execution Roadmap

**Generated:** 2026-05-06  
**Audit Scope:** Full read-only diagnostic sweep of the Vestimate backend repository.  
**Status Key:** 🔴 Critical · 🟠 High · 🟡 Medium · 🟢 Low

---

## Executive Summary

The codebase is architecturally sound and production-hardened through Phase 4. However, **six bugs** were confirmed that will silently corrupt data or break features in production. The most severe is a **vector space mismatch** in the ML pipeline: garment images are embedded in standard OpenAI CLIP space, but the text query encoder uses FashionCLIP — making cosine similarity searches semantically meaningless. Additionally, the **Google OAuth token is passed to the Calendar API raw (encrypted)**, which will cause silent `401` failures on every calendar fetch despite appearing to work. Two schema columns referenced in production code do not exist in any migration. These issues must be fixed before any frontend handoff.

---

## Phase 1: Critical Blockers (Immediate Fixes)

These issues will cause **data corruption, silent pipeline failure, or broken product features** in production.

---

### 1.1 🔴 ML Vector Space Mismatch — `embed_and_tag` vs `text_embed`

**Severity:** Critical — Makes the entire recommendation engine's vector search semantically broken.

**Root Cause:**

The `embed_and_tag` function (called by the Celery worker during garment ingestion) uses `openai/clip-vit-base-patch16` — standard OpenAI CLIP. The `text_embed` function (called at recommendation time to build the query vector) uses `patrickjohncyh/fashion-clip` — a domain-specific fine-tuned model. **These two models produce embeddings in different latent spaces.** Cosine similarity between a standard CLIP image embedding and a FashionCLIP text embedding has no semantic meaning. Every pgvector retrieval result is essentially random.

**Evidence:**
```
# app/worker/modal_inference.py, line 44 — garment ingestion (WRONG model)
model_id = "openai/clip-vit-base-patch16"

# app/worker/modal_inference.py, line 114 — text query (CORRECT model)
model_id = "patrickjohncyh/fashion-clip"
```

**Also note:** The `text_embed` function is bound to `image_clip` container image (line 96), which does NOT install `fashion-clip` — it only installs `torch` and `transformers`. The `image_text` container (line 9) does install `fashion-clip` but is never used by any function.

**Fix:**
- [ ] In `app/worker/modal_inference.py`, change `embed_and_tag` to use `model_id = "patrickjohncyh/fashion-clip"`.
- [ ] In `app/worker/modal_inference.py`, change the `@app.function` decorator on `text_embed` (line 96) from `image=image_clip` to `image=image_text`.
- [ ] After deploying to Modal, **all existing `wardrobe_items` rows with non-null embeddings must be re-ingested** — their stored vectors are in the wrong space and will produce garbage retrieval results.

---

### 1.2 🔴 Encrypted OAuth Token Passed Raw to Google Calendar API

**Severity:** Critical — Google Calendar integration silently returns empty schedule on every request, even for connected users.

**Root Cause:**

`google_oauth.py` encrypts the `refresh_token` with Fernet before storing it in `users.google_oauth_token` (correct). However, `recommendations.py` (line 87) and `recommendation_service.py` (line 55) read `google_oauth_token` directly from the database and pass it as-is to `context_aggregator.get_calendar_events()`, which uses it as a raw Bearer token in the `Authorization` header. Google's API receives a Fernet ciphertext string instead of a valid access token, returns `401`, and the aggregator silently returns `[]`. Users always get weather-only recommendations with no schedule context.

**Evidence:**
```python
# app/api/v1/endpoints/recommendations.py, line 87
oauth_token = user_data.get("google_oauth_token")  # This is ENCRYPTED ciphertext

# app/services/context_aggregator.py, line 118 — raw token used as Bearer
headers={"Authorization": f"Bearer {oauth_token}"}  # WRONG — this is ciphertext
```

**Fix:**
- [ ] Create a `get_valid_access_token(encrypted_refresh_token: str) -> str` function in a new `app/services/google_oauth_service.py` that: decrypts the stored token with `decrypt_token()`, exchanges the refresh token for a new access token via `https://oauth2.googleapis.com/token` (grant_type=refresh_token), and returns the access token.
- [ ] In `recommendations.py` and `recommendation_service.py`, replace the raw `oauth_token` pass-through with a call to `get_valid_access_token()` before calling `build_context()`.

---

### 1.3 🔴 Missing Database Columns Referenced in Production Code

**Severity:** Critical — Celery beat task `prewarm_recommendations` will crash on every scheduled run with a PostgreSQL column-not-found error.

**Root Cause — `last_active_at`:**
`app/worker/tasks.py` (line 143) queries `SELECT id FROM users WHERE last_active_at > NOW() - INTERVAL '7 days'`. The column `last_active_at` does not exist in `scripts/001_database_migration.sql` or any other migration file. This query will throw `asyncpg.exceptions.UndefinedColumnError` on every beat run, silently failing the pre-warm task.

**Root Cause — `google_oauth_scopes`:**
`google_oauth.py` (lines 124, 159) reads and writes `users.google_oauth_scopes`. This column is not defined in any migration SQL file.

**Fix:**
- [ ] Create `migrations/004_missing_columns.sql` with the following:
```sql
-- Add last_active_at to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_users_last_active ON users(last_active_at DESC);

-- Add google_oauth_scopes to users table  
ALTER TABLE users ADD COLUMN IF NOT EXISTS google_oauth_scopes TEXT[];
```
- [ ] Run this migration against both staging and production Supabase before deploying.

---

### 1.4 🔴 Celery Worker — Missing `raise_for_status()` on Modal Embed Call

**Severity:** High — A failed Modal embedding call (e.g. HTTP 500 or 429) will silently proceed, with `resp.json()` throwing an unhandled exception or returning garbage that corrupts the DB record.

**Evidence:**
```python
# app/worker/tasks.py, line 53 — no raise_for_status before .json()
resp = client.post(modal_embed_url, content=segmented_png_bytes, ...)
ml_results = resp.json()  # Will crash with JSONDecodeError on non-200 response
```

Compare to line 44 where `resp.raise_for_status()` IS correctly called on the segmentation step.

**Fix:**
- [ ] In `app/worker/tasks.py`, add `resp.raise_for_status()` immediately after line 53 (the `client.post(modal_embed_url, ...)` call), before `ml_results = resp.json()`.

---

### 1.5 🔴 Fernet Key Derivation is Cryptographically Weak

**Severity:** High — The token encryption key derivation is insecure and will silently break if `TOKEN_ENCRYPTION_KEY` length changes.

**Root Cause:**
```python
# app/api/v1/endpoints/google_oauth.py, lines 26-28
raw = settings.TOKEN_ENCRYPTION_KEY.encode()
padded = (raw * ((32 // len(raw)) + 1))[:32]  # Naive byte repetition — NOT a hash
key = base64.urlsafe_b64encode(padded)
```
This derives a Fernet key by repeating the raw key bytes — a predictable, low-entropy derivation that is NOT a standard KDF. Any change to the length of `TOKEN_ENCRYPTION_KEY` changes the derived key, silently making all previously encrypted tokens undecryptable (Fernet will raise `InvalidToken` with no clear error message).

**Fix:**
- [ ] Replace the manual key derivation with HKDF:
```python
import hashlib, hmac
def _get_fernet() -> Fernet:
    raw = settings.TOKEN_ENCRYPTION_KEY.encode()
    derived = hashlib.sha256(raw).digest()  # Always 32 bytes regardless of input length
    key = base64.urlsafe_b64encode(derived)
    return Fernet(key)
```
- [ ] After deploying this fix, all existing encrypted tokens in the DB will be undecryptable with the new key — issue a one-time migration that nullifies `google_oauth_token` for all users so they re-connect cleanly.

---

### 1.6 🟠 File Encoding Corruption

**Severity:** Medium — UTF-16LE null bytes in `.gitignore` will cause `git` to treat the file as binary on some platforms. `requirements.lock` encoded in UTF-16LE will break `pip install -r requirements.lock` on CI runners using UTF-8 locale.

**Evidence:**
- `.gitignore` line 7 contains `t\0e\0s\0t\0_\0i\0m\0a\0g\0e\0s\0/\0` — UTF-16LE encoding artifact.
- `requirements.lock` — file tool reported `charset=utf-16le` MIME type.

**Fix:**
- [ ] Re-save `.gitignore` as UTF-8 with Unix line endings. The `test_images/` entry should read simply: `test_images/`.
- [ ] Regenerate `requirements.lock` using `pip-compile requirements.txt --output-file requirements.lock` in a UTF-8 environment, or delete it if not actively used in CI (CI currently uses `requirements.txt` directly).

---

## Phase 2: Feature Completion (API Readiness)

### 2.1 Complete Google Calendar OAuth Integration (Phase 5)

The OAuth endpoints (`/callback`, `/revoke`) are implemented, but the integration chain has two broken links beyond the encryption issue identified in Phase 1.

**Missing: Token Refresh Logic**
- [ ] Create `app/services/google_oauth_service.py` with:
  - `decrypt_stored_token(encrypted: str) -> str` — wraps `decrypt_token` from `google_oauth.py` (currently only accessible from the endpoint file).
  - `get_access_token(user_id: str) -> str | None` — fetches encrypted refresh token from DB, decrypts it, exchanges for a fresh access token via `POST https://oauth2.googleapis.com/token`.
  - Token refresh caching in Redis (e.g. `gtoken:{user_id}`, TTL = `expires_in - 60s`) to avoid re-fetching on every recommendation request.

**Missing: OAuth Initiation Endpoint**
- [ ] The `/callback` endpoint receives an authorization `code`, but there is **no `/authorize` endpoint** that generates the Google OAuth URL and redirects the user. Without it, the mobile client has no way to start the OAuth flow server-side.
- [ ] Add `GET /v1/users/me/google-oauth/authorize` that returns `{ "auth_url": "https://accounts.google.com/o/oauth2/v2/auth?..." }` with the correct scopes (`calendar.readonly`), `access_type=offline`, and `prompt=consent`.

**Missing: `decrypt_token` Accessibility**
- [ ] Move `encrypt_token` / `decrypt_token` out of `google_oauth.py` (an endpoint file) into `app/services/google_oauth_service.py` so they are importable by other services without circular imports.

---

### 2.2 Recommendation Endpoint — Remaining Gaps

**`/recommendations/history` — Image URLs Missing**
- [ ] `recommendations.py` lines 238–240: The history response constructs `OutfitItem` objects with `image_url=None`. This means the history feed has no images. Fix by joining `wardrobe_items` to fetch `raw_image_key` for each `top_id`, `bottom_id`, `shoe_id` and generating signed URLs.

**`/recommendations/today` — `city` query param is redundant after Phase 5**
- [ ] The endpoint accepts `city` as a query param (default: `"Yerevan"`) but also reads `user_data.get("city")`. The user's stored city takes precedence. Remove or deprecate the query param to prevent confusion; document the behaviour in OpenAPI.

**Pre-warm Beat Task will silently no-op**
- [ ] As identified in §1.3, `last_active_at` does not exist. Until migration §1.3 is run, `prewarm_recommendations` queries a non-existent column and crashes. After the column is added, ensure `last_active_at` is updated on every successful recommendation generation (add `UPDATE users SET last_active_at = NOW() WHERE id = $1` in `recommendation_service.py`).

---

### 2.3 `embed_and_tag` — Color Extraction Not Implemented

The architecture doc specifies a 32-color palette mapping. The Modal `embed_and_tag` function returns no `colors` field in its response. The Celery worker handles this with a fallback:

```python
# app/worker/tasks.py, line 60
colors = tags.get("colors", ["unknown"])  # Always returns ["unknown"] — no color in response
```

- [ ] Add color extraction to `embed_and_tag` in `modal_inference.py`: use CLIP zero-shot classification against a list of 32 standard color names (`["black", "white", "navy", "red", ...]`). Return top-2 colors by probability in `tags["colors"]`.

---

## Phase 3: Infrastructure & Hygiene (Technical Debt)

### 3.1 README.md — Replace Placeholder

**File:** `README.md` (2 lines, placeholder text only)

- [ ] Write a proper README covering: project description, local setup instructions (venv creation, `.env` setup, `docker compose up`, `uvicorn main:app --reload`), how to run tests, how to deploy Modal functions, and links to `CLAUDE_CONTEXT.md` and `Vestimate_archiecture (1).md`.

---

### 3.2 Testing Infrastructure

**No `conftest.py` exists** — pytest has no shared fixtures, no test database setup, and no environment variable injection. Every test that needs settings or mocked clients must do it manually and inconsistently.

- [ ] Create `tests/conftest.py` with:
```python
import pytest, os
os.environ.setdefault("SUPABASE_URL", "http://localhost")
os.environ.setdefault("SUPABASE_SERVICE_KEY", "test-key")
os.environ.setdefault("SUPABASE_DATABASE_URL", "postgresql+asyncpg://postgres:postgres@localhost:5432/test")
os.environ.setdefault("REDIS_URL", "redis://localhost:6379/0")
os.environ.setdefault("ENV", "test")

@pytest.fixture
def anyio_backend():
    return "asyncio"
```
- [ ] Create `pytest.ini` or add `[tool.pytest.ini_options]` to a new `pyproject.toml`:
```ini
[pytest]
asyncio_mode = auto
testpaths = tests
```
- [ ] Install `pytest-asyncio` and `pytest-cov` — they are used in CI but not listed in `requirements.txt`.

**Missing unit test coverage:**

| Module | Current Tests | Required Tests |
|---|---|---|
| `context_aggregator.py` | None | `test_classify_formality`, `test_compute_weather_bucket`, `test_get_time_of_day`, `test_build_occasion_string` |
| `recommendation_cache.py` | None | `test_build_cache_key`, `test_cache_hit`, `test_invalidate_user_cache` |
| `llm_service.py` | None | `test_heuristic_fallback`, `test_validate_against_candidates_hallucinated_id` |
| `vector_service.py` | None | `test_get_query_vector_cache_hit`, `test_get_query_vector_zero_fallback` |
| `retrieval.py` | None | `test_has_sufficient_candidates_empty_category` |

- [ ] Add the above test files under `tests/unit/`. Mock `asyncpg.connect`, `redis.Redis`, and `httpx.AsyncClient` at the fixture level in `conftest.py`.

---

### 3.3 Database Migration Strategy

Currently, migrations are raw `.sql` files split across two directories (`scripts/` and `migrations/`) with no runner, no version tracking, and no rollback support. They must be manually copy-pasted into Supabase's SQL editor.

**Recommended approach: Adopt `sqitch`** (lightweight, SQL-native, no ORM dependency).

- [ ] Initialize sqitch: `sqitch init vestimate --engine pg`
- [ ] Convert existing SQL files into sqitch changes:
  - `001_database_migration.sql` → `sqitch add core_schema`
  - `002_remaining_tables.sql` → `sqitch add phase2_tables`
  - `migrations/003_phase3_indexes_and_seed.sql` → `sqitch add phase3_indexes`
  - `scripts/004_rls_policies.sql` → `sqitch add rls_policies`
  - New `004_missing_columns.sql` (from §1.3) → `sqitch add missing_columns`
- [ ] Add `sqitch deploy` to the CI/CD pipeline before Railway deployment step.
- [ ] Add rollback scripts (`revert/`) for each change.

**Alternative (simpler):** If sqitch is too heavy, create a single `scripts/run_migrations.py` that reads SQL files in numbered order, tracks applied migrations in a `schema_migrations` table, and is idempotent (skips already-applied). Run it as a Railway one-off command on deploy.

---

### 3.4 SQLAlchemy Engine — Dead Code

`app/core/config.py` initializes a full SQLAlchemy async engine (`engine`, `async_session_maker`) but **no part of the application uses it**. All DB access goes through raw `asyncpg.connect()` or `supabase-py`. This adds ~100ms to startup time and creates an unused connection pool.

- [ ] Either: start using `async_session_maker` as the standard DB access pattern (preferred for type safety), or remove the `engine` / `async_session_maker` initialization entirely and delete the `sqlalchemy` import in `config.py`.

---

### 3.5 `app/api/v1/__init__.py` — Duplicate Router Registration

`main.py` registers `wardrobe_read_router` and `feedback_router` directly. `app/api/v1/__init__.py` also registers `feedback.router` via `api_router`. This means the feedback endpoint is mounted **twice** — at `/v1/feedback/` (via `api_router`) and at `/v1/feedback` (directly in `main.py`).

- [ ] Audit which mounts are active and remove the duplicate registrations from `main.py`. Consolidate all routing into `app/api/v1/__init__.py`.

---

### 3.6 Hard-coded CDN URL in Worker

```python
# app/worker/tasks.py, line 66
image_url = f"https://cdn.vestimate.app/{segmented_key}"
```

This URL is hard-coded. `cdn.vestimate.app` may not exist or may point to the wrong bucket. The rest of the system uses `generate_signed_url(raw_image_key)` from `storage.py`.

- [ ] Add `R2_PUBLIC_CDN_URL` to `Settings` in `config.py`.
- [ ] Replace the hard-coded string with `f"{settings.R2_PUBLIC_CDN_URL}/{segmented_key}"`.

---

## Phase 4: Frontend Handoff

### 4.1 Finalize OpenAPI Schema

FastAPI auto-generates an OpenAPI schema at `/openapi.json`. Before handing off to frontend, ensure the schema is complete and accurate.

- [ ] Add `summary`, `description`, and `response_model` to every endpoint that is missing them (`wardrobe_read.py` endpoints return raw `dict` — no response model).
- [ ] Add `tags` consistently to all routers.
- [ ] Add `responses` documentation for 401, 404, 422, 429 on each endpoint.
- [ ] Add `openapi_extra` or `response_description` to the `/recommendations/today` endpoint documenting the `insufficient_wardrobe` 404 error body — the frontend needs to detect this specific code to show the onboarding flow.

### 4.2 Standardize Wardrobe Read Response

`wardrobe_read.py` returns `item.__dict__` (a raw Python dataclass dict) instead of a typed Pydantic model. This bypasses FastAPI's serialization and produces inconsistent field names in the JSON response.

- [ ] Convert `WardrobeItem` and `WardrobeListResult` in `app/services/wardrobe_read.py` from `@dataclass` to `pydantic.BaseModel`.
- [ ] Update `wardrobe_read.py` endpoints to use `response_model=WardrobeListResult`.

### 4.3 Define a Stable API Version Contract

- [ ] Pin the OpenAPI spec to a file: add a GitHub Actions step that runs `curl https://api.vestimate.app/openapi.json > openapi.json` and commits it to a `docs/api/` directory on every merge to `main`.
- [ ] Frontend team should import this `openapi.json` into their HTTP client generator (e.g. `openapi-typescript` for React Native) to get fully typed API clients with zero manual maintenance.

### 4.4 Document Debug Auth Bypass Before Handoff

```python
# app/core/auth.py, line 47 — MUST be removed before public release
if settings.DEBUG and token == "debug-token-123":
    return uuid.UUID("11111111-1111-1111-1111-111111111111")
```

- [ ] Ensure `DEBUG=false` is set in all Railway production environment variables.
- [ ] Consider removing this bypass entirely and replacing with a proper test fixture user in staging.

### 4.5 Define Error Response Schema

The API returns inconsistent error bodies — some endpoints return `{"detail": "string"}`, others return `{"detail": {"code": "...", "message": "..."}}`. The frontend cannot reliably parse errors.

- [ ] Define a standard `ErrorResponse` Pydantic model: `{ "code": str, "message": str, "detail": Any | None }`.
- [ ] Apply it consistently across all `HTTPException` raises, particularly the `insufficient_wardrobe` case which the frontend must handle as a navigation trigger.

---

## Issue Index

| # | Severity | File | Issue |
|---|---|---|---|
| 1.1 | 🔴 Critical | `app/worker/modal_inference.py:44,96` | CLIP vs FashionCLIP vector space mismatch |
| 1.2 | 🔴 Critical | `app/api/v1/endpoints/recommendations.py:87` | Encrypted OAuth token passed raw to Google API |
| 1.3 | 🔴 Critical | `scripts/*.sql` | `last_active_at` and `google_oauth_scopes` columns missing from schema |
| 1.4 | 🟠 High | `app/worker/tasks.py:53` | Missing `raise_for_status()` on embed Modal call |
| 1.5 | 🟠 High | `app/api/v1/endpoints/google_oauth.py:26-28` | Weak Fernet key derivation (byte repetition, not hash) |
| 1.6 | 🟡 Medium | `.gitignore`, `requirements.lock` | UTF-16LE file encoding corruption |
| 2.1 | 🟠 High | `app/services/` (missing file) | No token refresh service; no OAuth authorize endpoint |
| 2.2 | 🟡 Medium | `app/api/v1/endpoints/recommendations.py:238` | History endpoint returns `image_url=None` for all items |
| 2.3 | 🟡 Medium | `app/worker/modal_inference.py:82-88` | Color extraction not implemented; always returns `["unknown"]` |
| 3.1 | 🟢 Low | `README.md` | Placeholder only |
| 3.2 | 🟡 Medium | `tests/` | No `conftest.py`, no `pytest.ini`, missing `pytest-asyncio` in requirements |
| 3.3 | 🟡 Medium | `scripts/*.sql`, `migrations/*.sql` | No migration runner; files split across two directories |
| 3.4 | 🟢 Low | `app/core/config.py:51-62` | SQLAlchemy engine initialized but never used |
| 3.5 | 🟠 High | `main.py` + `app/api/v1/__init__.py` | Duplicate router registration for feedback and wardrobe_read |
| 3.6 | 🟡 Medium | `app/worker/tasks.py:66` | Hard-coded CDN URL `cdn.vestimate.app` |
| 4.1 | 🟡 Medium | `app/api/v1/endpoints/wardrobe_read.py` | No `response_model`; returns raw `dict` |
| 4.2 | 🟡 Medium | All endpoints | Inconsistent error response schema |
| 4.3 | 🟢 Low | `app/core/auth.py:47` | Debug token bypass must be disabled before public release |

---

*End of VESTIMATE Remediation Plan*
