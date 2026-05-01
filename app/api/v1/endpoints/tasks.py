from fastapi import APIRouter, HTTPException
from app.models.schemas import TaskStatusResponse
from app.worker.celery_app import celery_app

router = APIRouter()

@router.get("/{task_id}", response_model=TaskStatusResponse)
def get_task_status(task_id: str):
    if len(task_id) != 36:
        raise HTTPException(status_code=404, detail="Not Found")
        
    result = celery_app.AsyncResult(task_id)

    if result.state == "PENDING":
        return TaskStatusResponse(task_id=task_id, status="pending")
    elif result.state == "STARTED":
        return TaskStatusResponse(task_id=task_id, status="processing")
    elif result.state == "SUCCESS":
        return TaskStatusResponse(
            task_id=task_id, 
            status="complete", 
            item_id=result.result.get("item_id") if isinstance(result.result, dict) else None
        )
    elif result.state == "FAILURE":
        return TaskStatusResponse(task_id=task_id, status="failed", error=str(result.result))
    else:
        return TaskStatusResponse(task_id=task_id, status=result.state.lower())
