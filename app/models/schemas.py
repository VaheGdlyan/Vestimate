from pydantic import BaseModel

class TaskStatusResponse(BaseModel):
    task_id: str
    status: str
    item_id: str | None = None
    error: str | None = None

class UploadResponse(BaseModel):
    item_id: str
    task_id: str
    status: str
