import time
from app.worker.celery_app import celery_app

@celery_app.task(name="ingest_garment", bind=True)
def ingest_garment(self, item_id: str, file_path: str):
    time.sleep(2)
    return {"item_id": item_id, "status": "complete"}
