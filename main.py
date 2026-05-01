from fastapi import FastAPI
from app.api.v1.endpoints.wardrobe import router as wardrobe_router
from app.api.v1.endpoints.tasks import router as tasks_router

app = FastAPI(title="Vestimate API", version="0.1.0")

app.include_router(wardrobe_router, prefix="/v1/wardrobe", tags=["wardrobe"])
app.include_router(tasks_router, prefix="/v1/tasks", tags=["tasks"])

@app.get("/health")
def health():
    return {"status": "ok"}
