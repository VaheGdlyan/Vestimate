import uuid
from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from app.models.schemas import UploadResponse
from app.services.storage import save_upload_file
from app.worker.tasks import ingest_garment

router = APIRouter()

ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}

@router.post("/upload", status_code=202, response_model=UploadResponse)
async def upload_garment(
    file: UploadFile = File(...),
    user_id: str = Form(...),
):
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
    
    file_path = await save_upload_file(file, filename)
    
    task = ingest_garment.delay(item_id=item_id, file_path=file_path)

    return UploadResponse(
        item_id=item_id,
        task_id=task.id,
        status="pending"
    )
