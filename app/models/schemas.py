from pydantic import BaseModel
from typing import Optional, Any

class ErrorResponse(BaseModel):
    code: str
    message: str
    detail: Optional[Any] = None
class TaskStatusResponse(BaseModel):
    task_id: str
    status: str
    item_id: str | None = None
    error: str | None = None

class UploadResponse(BaseModel):
    item_id: str
    task_id: str
    status: str
