# VESTIMATE Architecture Analysis

## 1. Project Topology

```
VESTIMATE/
├── .dockerignore
├── .env
├── .env.example
├── .gitignore
├── Dockerfile
├── README.md
├── docker-compose.yml
├── main.py
├── requirements.lock
├── requirements.txt
├── app/
│   ├── __init__.py
│   ├── api/
│   │   ├── __init__.py
│   │   └── v1/
│   │       ├── __init__.py
│   │       └── endpoints/
│   │           ├── __init__.py
│   │           ├── tasks.py
│   │           └── wardrobe.py
│   ├── core/
│   │   ├── __init__.py
│   │   └── config.py
│   ├── models/
│   │   ├── __init__.py
│   │   └── schemas.py
│   ├── services/
│   │   ├── __init__.py
│   │   └── storage.py
│   └── worker/
│       ├── __init__.py
│       ├── celery_app.py
│       └── tasks.py
├── scripts/
└── tests/
```

## 2. Infrastructure & Environment

### `requirements.txt`
```text
fastapi==0.111.0
celery==5.4.0
redis==5.0.6
pydantic==2.7.1
pydantic-settings==2.3.0
uvicorn[standard]==0.30.0
python-multipart==0.0.9
```

### `Dockerfile`
```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### `docker-compose.yml`
```yaml
version: "3.8"

services:
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3

  api:
    build: .
    ports:
      - "8000:8000"
    env_file: .env
    depends_on:
      redis:
        condition: service_healthy
    command: uvicorn main:app --host 0.0.0.0 --port 8000 --reload
    volumes:
      - .:/app
      - ./uploads:/app/uploads
    environment:
      - REDIS_URL=redis://redis:6379/0

  worker:
    build: .
    env_file: .env
    depends_on:
      redis:
        condition: service_healthy
    command: celery -A app.worker.celery_app worker --loglevel=info --concurrency=2
    volumes:
      - .:/app
      - ./uploads:/app/uploads
    environment:
      - REDIS_URL=redis://redis:6379/0

volumes:
  redis_data:
```

### `.env.example`
```env
APP_NAME=Vestimate
DEBUG=True
REDIS_URL=redis://redis:6379/0
```

## 3. Application Routing

### `main.py`
```python
from fastapi import FastAPI
from app.api.v1.endpoints.wardrobe import router as wardrobe_router
from app.api.v1.endpoints.tasks import router as tasks_router

app = FastAPI(title="Vestimate API", version="0.1.0")

app.include_router(wardrobe_router, prefix="/v1/wardrobe", tags=["wardrobe"])
app.include_router(tasks_router, prefix="/v1/tasks", tags=["tasks"])

@app.get("/health")
def health():
    return {"status": "ok"}
```

## 4. Core Business & ML Logic

### `app/api/v1/endpoints/wardrobe.py`
```python
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
```

## 5. Data Structures

Currently, the data structures are simplified and focus on task tracking and upload responses. The explicit schema for clothing entities and style vector embeddings (like FashionCLIP integration) has not been implemented in the codebase yet. 

### `app/models/schemas.py`
```python
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
```

## 6. Asynchronous Architecture

The application utilizes **Celery** along with **Redis** to handle heavy background processing asynchronously (e.g., ML processing, Vision pipeline integration). 

- **Broker & Backend**: Redis is utilized as both the message broker (queue) and the result backend. It is defined in `celery_app.py` pulling configurations from `app.core.config`.
- **Concurrency**: The worker is configured (via `docker-compose.yml`) to run with a concurrency of `2` (`--concurrency=2`), logging at the `info` level.
- **Tasks (`app/worker/tasks.py`)**: Defines Celery tasks such as `ingest_garment`. Currently, this acts as a placeholder that simulates a processing delay (`time.sleep(2)`) before marking the ingestion as complete. This is the designated insertion point for the upcoming FashionCLIP / Vision pipeline integration.
- **Workflow**:
  1. A garment image is uploaded via the `/v1/wardrobe/upload` endpoint.
  2. The image is saved locally (`app.services.storage.save_upload_file`).
  3. An asynchronous Celery task (`ingest_garment.delay()`) is fired, returning immediately with a `task_id` so the user is not blocked.
  4. The client can query the `/v1/tasks/{task_id}` endpoint (powered by `app/api/v1/endpoints/tasks.py`) to monitor the status (`PENDING`, `STARTED`, `SUCCESS`, `FAILURE`) of the heavy ML extraction operation without holding up the HTTP thread.

### `app/worker/celery_app.py`
```python
from celery import Celery
from app.core.config import settings

celery_app = Celery(
    "vestimate",
    broker=settings.REDIS_URL,
    backend=settings.REDIS_URL,
    include=["app.worker.tasks"]
)

celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    enable_utc=True,
    task_track_started=True
)
```

### `app/worker/tasks.py`
```python
import time
from app.worker.celery_app import celery_app

@celery_app.task(name="ingest_garment", bind=True)
def ingest_garment(self, item_id: str, file_path: str):
    time.sleep(2)
    return {"item_id": item_id, "status": "complete"} 
```
