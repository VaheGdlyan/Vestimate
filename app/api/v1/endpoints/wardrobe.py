import uuid
import logging
from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from app.models.schemas import UploadResponse
from app.services.storage import save_upload_file
from app.worker.tasks import ingest_garment
from app.core.config import settings
from app.core.auth import CurrentUser

logger = logging.getLogger(__name__)

router = APIRouter()

ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}


def _get_supabase_client():
    """Lazy-init Supabase REST client for stub record creation."""
    from supabase import create_client
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)


@router.post("/upload", status_code=202, response_model=UploadResponse)
async def upload_garment(
    current_user: CurrentUser,
    file: UploadFile = File(...),
):
    user_id = str(current_user)
    if file.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid file type. Must be an image."
        )

    item_id = str(uuid.uuid4())
    
    ext_map = {
        "image/jpeg": ".jpg",
        "image/png": ".png",
        "image/webp": ".webp",
        "image/gif": ".gif",
    }
    ext = ext_map.get(file.content_type, ".jpg")
    filename = f"{item_id}{ext}"
    
    # Upload raw image to Cloudflare R2
    object_key = await save_upload_file(file, user_id, filename)
    
    # Create stub record in Supabase (status: "processing")
    # This lets the client see the item immediately in wardrobe with a "processing" state
    try:
        supabase = _get_supabase_client()
        supabase.table("wardrobe_items").insert({
            "id": item_id,
            "user_id": user_id,
            "status": "processing",
            "raw_image_key": object_key,
        }).execute()
    except Exception as e:
        logger.error(f"Failed to create stub record for item {item_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to initiate processing")
    
    # Enqueue Celery task for ML pipeline
    task = ingest_garment.delay(item_id=item_id, raw_object_key=object_key, user_id=user_id)

    return UploadResponse(
        item_id=item_id,
        task_id=task.id,
        status="processing"
    )

