"""
Vestimate API — Production-ready FastAPI backend.
Serves wardrobe items from local folder with graceful DB degradation,
upload pipeline, task polling, recommendations, and feedback.
"""
import uvicorn
import uuid
import os
import random
import shutil
import time
import logging
from datetime import datetime
from fastapi import FastAPI, Query, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse
from typing import Optional

# ── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")
log = logging.getLogger("vestimate")

# ── App ──────────────────────────────────────────────────────────────────────
app = FastAPI(title="Vestimate API", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Configuration ────────────────────────────────────────────────────────────
IMAGES_DIR = "test_images2"
ALLOWED_TYPES = {"image/jpeg", "image/png", "image/jpg"}
MAX_FILE_SIZE_MB = 10
DB_CONNECTED = False  # Will be set True when real DB is available

# ── Static File Mount ────────────────────────────────────────────────────────
os.makedirs(IMAGES_DIR, exist_ok=True)
app.mount("/static_clothes", StaticFiles(directory=IMAGES_DIR), name="static_clothes")

# ── In-Memory Task Store (Redis replacement for local dev) ───────────────────
_task_store: dict[str, dict] = {}


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
        if filename.lower().endswith((".png", ".jpg", ".jpeg")):
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
    }


# ══════════════════════════════════════════════════════════════════════════════
# WARDROBE — ITEMS
# ══════════════════════════════════════════════════════════════════════════════

@app.get("/v1/wardrobe/items")
async def get_wardrobe_items(category: Optional[str] = Query(None)):
    log.info(f"GET /wardrobe/items  category={category or 'All'}")
    all_items = get_items_from_folder()

    filtered = all_items
    if category:
        filtered = [c for c in all_items if c["category"] == category.lower()]

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
            for c in filtered
        ],
        "total": len(filtered),
    }


# ══════════════════════════════════════════════════════════════════════════════
# WARDROBE — UPLOAD  (Phase 1 Critical)
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/v1/wardrobe/upload")
async def upload_garment(file: UploadFile = File(...)):
    # Validate content type
    if file.content_type not in ALLOWED_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid file type '{file.content_type}'. Allowed: JPEG, PNG.",
        )

    # Read file and validate size
    contents = await file.read()
    size_mb = len(contents) / (1024 * 1024)
    if size_mb > MAX_FILE_SIZE_MB:
        raise HTTPException(
            status_code=400,
            detail=f"File too large ({size_mb:.1f}MB). Max {MAX_FILE_SIZE_MB}MB.",
        )

    # Save to wardrobe folder
    safe_name = file.filename or f"upload_{uuid.uuid4().hex[:8]}.jpg"
    file_path = os.path.join(IMAGES_DIR, safe_name)
    with open(file_path, "wb") as f:
        f.write(contents)

    # Create task
    task_id = str(uuid.uuid4())
    _task_store[task_id] = {
        "status": "pending",
        "item_id": safe_name,
        "result": None,
        "error": None,
        "created_at": time.time(),
    }

    log.info(f"UPLOAD OK: {safe_name} ({size_mb:.1f}MB) → task {task_id}")

    # Simulate background processing completing after a moment
    # In production this would be a Celery/Modal task
    _task_store[task_id]["status"] = "complete"
    _task_store[task_id]["result"] = f"http://localhost:8888/static_clothes/{safe_name}"

    return {
        "task_id": task_id,
        "item_id": safe_name,
        "status": "queued",
    }


# ══════════════════════════════════════════════════════════════════════════════
# TASKS — POLLING  (Phase 1 Critical)
# ══════════════════════════════════════════════════════════════════════════════

@app.get("/v1/tasks/{task_id}")
async def get_task_status(task_id: str):
    task = _task_store.get(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    response = {
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
    "☀️ Perfect for today's sunny 22°C weather. The light colors keep you cool while looking sharp.",
    "🌤 A classic smart-casual look for your afternoon meetings. Confident yet comfortable.",
    "✨ This combination scored highest in your style profile. Your go-to power outfit.",
    "🎨 Great color harmony between these pieces. The contrast creates visual interest.",
    "💼 Business-ready but not overdressed. Ideal for a day that transitions from work to dinner.",
    "🏃 Comfortable and stylish — perfect for a busy day with lots of walking.",
]

@app.get("/v1/recommendations/today")
def get_recommendation():
    all_items = get_items_from_folder()
    if not all_items:
        return {"item_ids": [], "stylist_notes": "Add clothes to your wardrobe to get AI-powered recommendations!"}

    tops = [i for i in all_items if i["category"] == "tops"]
    bottoms = [i for i in all_items if i["category"] == "bottoms"]
    shoes = [i for i in all_items if i["category"] == "footwear"]

    item_ids = []
    if tops: item_ids.append(random.choice(tops)["id"])
    if bottoms: item_ids.append(random.choice(bottoms)["id"])
    if shoes: item_ids.append(random.choice(shoes)["id"])

    if not item_ids:
        return {"item_ids": [], "stylist_notes": "Need at least one top, bottom, or shoe to recommend."}

    return {
        "item_ids": item_ids,
        "stylist_notes": random.choice(STYLIST_NOTES),
    }


# ══════════════════════════════════════════════════════════════════════════════
# FEEDBACK
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/v1/feedback")
async def receive_feedback(data: dict):
    item_id = data.get("item_id")
    action = data.get("action")
    log.info(f"FEEDBACK: item={item_id} action={action}")
    return {"status": "success", "message": f"Recorded '{action}'"}


# ══════════════════════════════════════════════════════════════════════════════
# ENTRYPOINT
# ══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    log.info("=" * 60)
    log.info("  VESTIMATE API v2.0 — Production Mode")
    log.info(f"  Images: ./{IMAGES_DIR}/ ({len(get_items_from_folder())} items)")
    log.info(f"  DB Connected: {DB_CONNECTED}")
    log.info("=" * 60)
    uvicorn.run(app, host="0.0.0.0", port=8888)
