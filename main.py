import uvicorn
import uuid
import os
from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from typing import Optional

app = FastAPI(title="Vestimate API", version="0.1.0")

# 1. CORS SETUP
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 2. MOUNT STATIC FILES (To serve your actual photos)
IMAGES_DIR = "test_images2"
if os.path.exists(IMAGES_DIR):
    app.mount("/static_clothes", StaticFiles(directory=IMAGES_DIR), name="static_clothes")

def get_category_from_filename(filename: str) -> str:
    f = filename.lower()
    if "shirt" in f or "hoodie" in f:
        return "tops"
    if "trs" in f or "pants" in f or "jeans" in f:
        return "bottoms"
    if "shoes" in f or "sneakers" in f:
        return "footwear"
    return "outerwear"

def get_items_from_folder():
    items = []
    if not os.path.exists(IMAGES_DIR):
        return items
        
    for filename in os.listdir(IMAGES_DIR):
        if filename.lower().endswith((".png", ".jpg", ".jpeg")):
            category = get_category_from_filename(filename)
            items.append({
                "id": filename,
                "segmented_image_url": f"http://localhost:8888/static_clothes/{filename}",
                "category": category,
                "item_name": filename.replace("_", " ").split(".")[0].title()
            })
    return items

@app.get("/v1/health")
def health():
    return {"status": "ok"}

@app.get("/v1/wardrobe/items")
async def get_wardrobe_items(category: Optional[str] = Query(None)):
    print(f"--- FETCHING REAL WARDROBE: {category or 'All'} ---")
    
    all_items = get_items_from_folder()
    
    filtered = all_items
    if category:
        filtered = [c for c in all_items if c["category"] == category.lower()]
    
    return {
        "items": [
            {
                "id": c["id"],
                "segmented_image_url": c["segmented_image_url"],
                "category": c["category"],
                "status": "active",
                "metadata": {"name": c["item_name"]}
            }
            for c in filtered
        ],
        "total": len(filtered)
    }

@app.get("/v1/recommendations/today")
def get_recommendation():
    all_items = get_items_from_folder()
    if not all_items:
        return {"item_ids": [], "stylist_notes": "No clothes found in folder!"}
        
    tops = [i for i in all_items if i["category"] == "tops"]
    bottoms = [i for i in all_items if i["category"] == "bottoms"]
    shoes = [i for i in all_items if i["category"] == "footwear"]
    
    # Pick IDs
    item_ids = []
    if tops: item_ids.append(tops[0]["id"])
    if bottoms: item_ids.append(bottoms[0]["id"])
    if shoes: item_ids.append(shoes[0]["id"])
    
    if not item_ids:
        return {"item_ids": [], "stylist_notes": "Try adding more clothes to see a look!"}

    return {
        "item_ids": item_ids,
        "stylist_notes": f"YOUR SIGNATURE LOOK: This combination is perfect for a 20°C sunny day. Based on your {len(all_items)} items."
    }

@app.post("/v1/feedback")
async def receive_feedback(data: dict):
    item_id = data.get("item_id")
    action = data.get("action")
    print(f"--- FEEDBACK RECEIVED: Item {item_id} was {action} ---")
    return {"status": "success", "message": f"Recorded {action} for items"}

if __name__ == "__main__":
    print("\n" + "="*50)
    print("--- VESTIMATE REAL-IMAGE MODE ACTIVE ---")
    print(f"--- FOLDER: {IMAGES_DIR} ---")
    print("="*50 + "\n")
    uvicorn.run(app, host="0.0.0.0", port=8888)
