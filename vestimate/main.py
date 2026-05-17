"""
Vestimate API — Local Dev Backend v3.0
Serves wardrobe items from local folder, weather via Open-Meteo,
outfit history (in-memory), upload pipeline, task polling,
recommendations, and feedback.
"""
import uvicorn
import uuid
import os
import random
import time
import logging
import httpx
from datetime import datetime
from fastapi import FastAPI, Query, UploadFile, File, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse
from fastapi.exception_handlers import http_exception_handler
from typing import Optional

# ── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")
log = logging.getLogger("vestimate")

# ── App ──────────────────────────────────────────────────────────────────────
app = FastAPI(title="Vestimate API", version="3.0.0")

# Epic 6 — CORS restricted to localhost only (not wildcard *)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:*",
        "http://127.0.0.1:*",
        "http://localhost:5000",
        "http://localhost:8080",
        "http://localhost:42069",  # Flutter web default port range
    ],
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)

# ── Configuration ─────────────────────────────────────────────────────────────
IMAGES_DIR = "test_images2"
ALLOWED_MIME_TYPES = {"image/jpeg", "image/png", "image/jpg", "image/webp"}
MAX_FILE_SIZE_MB = 10
DB_CONNECTED = False

# ── Static File Mount ─────────────────────────────────────────────────────────
os.makedirs(IMAGES_DIR, exist_ok=True)
app.mount("/static_clothes", StaticFiles(directory=IMAGES_DIR), name="static_clothes")

# ── In-Memory Stores ──────────────────────────────────────────────────────────
_task_store: dict[str, dict] = {}
_outfit_history: list[dict] = []  # Epic 3 — Persistent outfit history


# ══════════════════════════════════════════════════════════════════════════════
# EPIC 7 — GLOBAL STRUCTURED ERROR HANDLER
# ══════════════════════════════════════════════════════════════════════════════

@app.exception_handler(HTTPException)
async def structured_http_exception_handler(request: Request, exc: HTTPException):
    """Returns all HTTP errors as structured JSON, never raw strings."""
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "code": _status_to_code(exc.status_code),
                "message": exc.detail,
            }
        },
    )

@app.exception_handler(Exception)
async def structured_generic_exception_handler(request: Request, exc: Exception):
    """Catches all unhandled exceptions — logs them, never exposes stack traces."""
    log.exception(f"Unhandled error on {request.method} {request.url.path}: {exc}")
    return JSONResponse(
        status_code=500,
        content={
            "error": {
                "code": "INTERNAL_SERVER_ERROR",
                "message": "An unexpected error occurred. Please try again.",
            }
        },
    )

def _status_to_code(status: int) -> str:
    mapping = {
        400: "BAD_REQUEST", 401: "UNAUTHORIZED", 403: "FORBIDDEN",
        404: "NOT_FOUND", 409: "CONFLICT", 413: "FILE_TOO_LARGE",
        422: "VALIDATION_ERROR", 429: "RATE_LIMITED", 500: "INTERNAL_SERVER_ERROR",
    }
    return mapping.get(status, f"HTTP_{status}")


# ══════════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

def get_category_from_filename(filename: str) -> str:
    f = filename.lower()
    if any(kw in f for kw in ("shirt", "hoodie", "tshirt", "top", "polo", "blouse")):
        return "tops"
    if any(kw in f for kw in ("trs", "pants", "jeans", "trouser", "bottom", "short")):
        return "bottoms"
    if any(kw in f for kw in ("shoes", "sneaker", "boot", "loafer", "sandal")):
        return "footwear"
    if any(kw in f for kw in ("jacket", "coat", "hoodie_zip", "blazer", "vest")):
        return "outerwear"
    return "outerwear"


def get_items_from_folder() -> list[dict]:
    items = []
    if not os.path.exists(IMAGES_DIR):
        return items
    for filename in sorted(os.listdir(IMAGES_DIR)):
        if filename.lower().endswith((".png", ".jpg", ".jpeg", ".webp")):
            category = get_category_from_filename(filename)
            items.append({
                "id": filename,
                "segmented_image_url": f"http://localhost:8888/static_clothes/{filename}",
                "raw_image_url": f"http://localhost:8888/static_clothes/{filename}",
                "category": category,
                "item_name": filename.replace("_", " ").replace("-", " ").split(".")[0].title(),
            })
    return items


# ══════════════════════════════════════════════════════════════════════════════
# HEALTH
# ══════════════════════════════════════════════════════════════════════════════

@app.get("/v1/health")
def health():
    return {
        "status": "ok",
        "db_connected": DB_CONNECTED,
        "wardrobe_items": len(get_items_from_folder()),
        "pending_tasks": len([t for t in _task_store.values() if t["status"] == "pending"]),
        "saved_outfits": len(_outfit_history),
    }


# ══════════════════════════════════════════════════════════════════════════════
# EPIC 1 — WEATHER ENDPOINT (Open-Meteo, no API key required)
# ══════════════════════════════════════════════════════════════════════════════

# Condition code → human label + emoji mapping from Open-Meteo WMO codes
_WMO_CONDITIONS: dict[int, tuple[str, str]] = {
    0: ("Clear Sky", "☀️"),
    1: ("Mainly Clear", "🌤"),
    2: ("Partly Cloudy", "⛅"),
    3: ("Overcast", "☁️"),
    45: ("Foggy", "🌫"),
    48: ("Depositing Rime Fog", "🌫"),
    51: ("Light Drizzle", "🌦"),
    53: ("Drizzle", "🌦"),
    55: ("Dense Drizzle", "🌧"),
    61: ("Slight Rain", "🌧"),
    63: ("Rain", "🌧"),
    65: ("Heavy Rain", "🌧"),
    71: ("Slight Snow", "❄️"),
    73: ("Snow", "❄️"),
    75: ("Heavy Snow", "❄️"),
    80: ("Rain Showers", "🌦"),
    81: ("Moderate Showers", "🌦"),
    82: ("Violent Showers", "⛈"),
    95: ("Thunderstorm", "⛈"),
    96: ("Thunderstorm w/ Hail", "⛈"),
    99: ("Thunderstorm w/ Heavy Hail", "⛈"),
}

from app.core.config import settings

# Default city if user auth not provided
_DEFAULT_CITY = "Baku"

from app.core.auth import CurrentUser
import asyncpg

async def _get_db_connection() -> asyncpg.Connection:
    dsn = settings.SUPABASE_DATABASE_URL.replace("postgresql+asyncpg://", "postgresql://")
    return await asyncpg.connect(dsn)

@app.get("/v1/weather")
async def get_weather(
    current_user: CurrentUser,
):
    """
    Fetch current weather from OpenWeatherMap (using env key) or gracefully degrade.
    """
    try:
        user_id = str(current_user)
        conn = await _get_db_connection()
        try:
            row = await conn.fetchrow("SELECT city FROM users WHERE id = $1", user_id)
            city = row["city"] if row and row["city"] else _DEFAULT_CITY
        finally:
            await conn.close()

        if settings.OPENWEATHERMAP_API_KEY:
            url = (
                f"https://api.openweathermap.org/data/2.5/weather"
                f"?q={city}&appid={settings.OPENWEATHERMAP_API_KEY}&units=metric"
            )
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(url)
                resp.raise_for_status()
                data = resp.json()

            temp = data["main"]["temp"]
            condition_id = data["weather"][0]["id"]
            wind = data.get("wind", {}).get("speed", 0.0)

            # Map condition ID to emoji
            if condition_id < 600:
                condition_label, emoji = "Rain", "🌦"
            elif condition_id < 700:
                condition_label, emoji = "Snow", "🌨"
            elif condition_id < 800:
                condition_label, emoji = "Cloudy", "☁️"
            elif condition_id == 800:
                condition_label, emoji = "Clear", "☀️"
            else:
                condition_label, emoji = "Cloudy", "☁️"

            return {
                "city": city,
                "temp_celsius": round(temp),
                "condition": condition_label,
                "emoji": emoji,
                "wind_kmh": round(wind * 3.6),
                "humidity_pct": data["main"]["humidity"],
                "available": True,
            }
        else:
            log.warning("OPENWEATHERMAP_API_KEY not set. Degrading weather gracefully.")
            raise Exception("No API Key")

    except Exception as e:
        log.warning(f"Weather fetch failed: {e}")
        return {
            "city": city if 'city' in locals() else _DEFAULT_CITY,
            "temp_celsius": None,
            "condition": "unavailable",
            "emoji": "🌡",
            "wind_kmh": None,
            "humidity_pct": None,
            "available": False,
        }


# ══════════════════════════════════════════════════════════════════════════════
# WARDROBE — ITEMS
# ══════════════════════════════════════════════════════════════════════════════

@app.get("/v1/wardrobe/items")
async def get_wardrobe_items(
    category: Optional[str] = Query(None),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
):
    log.info(f"GET /wardrobe/items  category={category or 'All'}  limit={limit}  offset={offset}")
    all_items = get_items_from_folder()

    filtered = all_items
    if category:
        cat = category.lower().strip()
        filtered = [c for c in all_items if c["category"] == cat]

    paginated = filtered[offset: offset + limit]

    return {
        "items": [
            {
                "id": c["id"],
                "segmented_image_url": c["segmented_image_url"],
                "raw_image_url": c["raw_image_url"],
                "category": c["category"],
                "status": "active",
                "metadata": {"name": c["item_name"]},
            }
            for c in paginated
        ],
        "total": len(filtered),
        "limit": limit,
        "offset": offset,
    }


# ══════════════════════════════════════════════════════════════════════════════
# WARDROBE — UPLOAD
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/v1/wardrobe/upload", status_code=202)
async def upload_garment(file: UploadFile = File(...)):
    # Validate content type by MIME, not extension
    if file.content_type not in ALLOWED_MIME_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid file type '{file.content_type}'. Allowed: JPEG, PNG, WebP.",
        )

    contents = await file.read()
    size_mb = len(contents) / (1024 * 1024)
    if size_mb > MAX_FILE_SIZE_MB:
        raise HTTPException(
            status_code=413,
            detail=f"File too large ({size_mb:.1f} MB). Maximum allowed is {MAX_FILE_SIZE_MB} MB.",
        )

    # Sanitize filename
    raw_name = file.filename or f"upload_{uuid.uuid4().hex[:8]}.jpg"
    safe_name = "".join(c for c in raw_name if c.isalnum() or c in ("_", "-", ".")).strip()
    if not safe_name:
        safe_name = f"upload_{uuid.uuid4().hex[:8]}.jpg"

    file_path = os.path.join(IMAGES_DIR, safe_name)
    with open(file_path, "wb") as f:
        f.write(contents)

    task_id = str(uuid.uuid4())
    _task_store[task_id] = {
        "status": "complete",
        "item_id": safe_name,
        "result": f"http://localhost:8888/static_clothes/{safe_name}",
        "error": None,
        "created_at": time.time(),
    }

    log.info(f"UPLOAD OK: {safe_name} ({size_mb:.1f} MB) → task {task_id}")

    return {
        "task_id": task_id,
        "item_id": safe_name,
        "status": "queued",
    }


# ══════════════════════════════════════════════════════════════════════════════
# TASKS — POLLING
# ══════════════════════════════════════════════════════════════════════════════

@app.get("/v1/tasks/{task_id}")
async def get_task_status(task_id: str):
    task = _task_store.get(task_id)
    if not task:
        raise HTTPException(status_code=404, detail=f"Task '{task_id}' not found.")

    response: dict = {
        "task_id": task_id,
        "status": task["status"],
        "item_id": task["item_id"],
        "error": task["error"],
    }

    if task["status"] == "complete":
        response["result"] = task["result"]
        response["segmented_image_url"] = task["result"]

    return response


# ══════════════════════════════════════════════════════════════════════════════
# RECOMMENDATIONS
# ══════════════════════════════════════════════════════════════════════════════

STYLIST_NOTES = [
    "☀️ Perfect for today's weather. The light colors keep you cool while looking sharp.",
    "🌤 A classic smart-casual look for your afternoon. Confident yet comfortable.",
    "✨ This combination scored highest in your style profile — your go-to power outfit.",
    "🎨 Great color harmony between these pieces. The contrast creates visual interest.",
    "💼 Business-ready but not overdressed. Ideal for a day that transitions from work to dinner.",
    "🏃 Comfortable and stylish — perfect for a busy day with lots of walking.",
]

@app.get("/v1/recommendations/today")
def get_recommendation():
    all_items = get_items_from_folder()
    if not all_items:
        return {
            "item_ids": [],
            "stylist_notes": "Add clothes to your wardrobe to get AI-powered recommendations!",
        }

    tops = [i for i in all_items if i["category"] == "tops"]
    bottoms = [i for i in all_items if i["category"] == "bottoms"]
    shoes = [i for i in all_items if i["category"] == "footwear"]

    item_ids = []
    if tops:
        item_ids.append(random.choice(tops)["id"])
    if bottoms:
        item_ids.append(random.choice(bottoms)["id"])
    if shoes:
        item_ids.append(random.choice(shoes)["id"])

    if not item_ids:
        return {
            "item_ids": [],
            "stylist_notes": "Need at least one top, bottom, or shoe to generate a recommendation.",
        }

    return {
        "item_ids": item_ids,
        "stylist_notes": random.choice(STYLIST_NOTES),
    }


# ══════════════════════════════════════════════════════════════════════════════
# EPIC 3 — OUTFIT HISTORY
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/v1/outfits", status_code=201)
async def save_outfit(data: dict):
    item_ids = data.get("item_ids")
    stylist_notes = data.get("stylist_notes", "")

    if not item_ids or not isinstance(item_ids, list) or len(item_ids) == 0:
        raise HTTPException(
            status_code=400,
            detail="item_ids must be a non-empty list of garment IDs.",
        )

    # Validate item IDs are strings
    if not all(isinstance(i, str) for i in item_ids):
        raise HTTPException(
            status_code=400,
            detail="All item_ids must be strings.",
        )

    outfit = {
        "id": str(uuid.uuid4()),
        "item_ids": item_ids,
        "stylist_notes": str(stylist_notes)[:500],  # Sanitize length
        "saved_at": datetime.utcnow().isoformat() + "Z",
    }
    _outfit_history.insert(0, outfit)  # Most recent first

    log.info(f"OUTFIT SAVED: {outfit['id']} with {len(item_ids)} items")

    return {"id": outfit["id"], "saved_at": outfit["saved_at"], "status": "saved"}


@app.get("/v1/outfits/history")
def get_outfit_history(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
):
    paginated = _outfit_history[offset: offset + limit]

    # Enrich each outfit with item details
    all_items_map = {i["id"]: i for i in get_items_from_folder()}
    enriched = []
    for outfit in paginated:
        items = [
            {
                "id": iid,
                "segmented_image_url": all_items_map[iid]["segmented_image_url"] if iid in all_items_map else None,
                "category": all_items_map[iid]["category"] if iid in all_items_map else "unknown",
                "metadata": {"name": all_items_map[iid]["item_name"]} if iid in all_items_map else {},
            }
            for iid in outfit["item_ids"]
        ]
        enriched.append({
            "id": outfit["id"],
            "items": items,
            "stylist_notes": outfit["stylist_notes"],
            "saved_at": outfit["saved_at"],
        })

    return {
        "outfits": enriched,
        "total": len(_outfit_history),
        "limit": limit,
        "offset": offset,
    }


# ══════════════════════════════════════════════════════════════════════════════
# FEEDBACK
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/v1/feedback")
async def receive_feedback(data: dict):
    item_id = data.get("item_id")
    action = data.get("action")

    if not item_id or not action:
        raise HTTPException(
            status_code=400,
            detail="Both 'item_id' and 'action' fields are required.",
        )

    allowed_actions = {"worn", "skipped", "liked", "disliked"}
    if action not in allowed_actions:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid action '{action}'. Must be one of: {', '.join(allowed_actions)}.",
        )

    log.info(f"FEEDBACK: item={item_id} action={action}")
    return {"status": "success", "message": f"Recorded '{action}' for item '{item_id}'"}


# ══════════════════════════════════════════════════════════════════════════════
# ENTRYPOINT
# ══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    import os
    import sys
    
    # Ensure uvicorn reloader subprocesses can resolve the 'vestimate' module
    parent_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    sys.path.insert(0, parent_dir)
    os.environ["PYTHONPATH"] = parent_dir + os.pathsep + os.environ.get("PYTHONPATH", "")

    log.info("=" * 60)
    log.info("  VESTIMATE API v3.0 — Local Dev Mode")
    log.info(f"  Images: ./{IMAGES_DIR}/ ({len(get_items_from_folder())} items)")
    log.info(f"  DB Connected: {DB_CONNECTED}")
    log.info("  Weather: Open-Meteo (free, no API key)")
    log.info("=" * 60)
    # Using import string "vestimate.main:app" because reload=True requires it.
    uvicorn.run("vestimate.main:app", host="0.0.0.0", port=8888, reload=True)
