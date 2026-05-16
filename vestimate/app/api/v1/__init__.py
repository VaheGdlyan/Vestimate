from fastapi import APIRouter
from app.api.v1.endpoints import wardrobe, tasks, recommendations, feedback

api_router = APIRouter()

# Existing routers — do not modify
api_router.include_router(wardrobe.router, prefix="/wardrobe", tags=["wardrobe"])
api_router.include_router(tasks.router, prefix="/tasks", tags=["tasks"])

# Phase 3 routers
from app.api.v1.endpoints import wardrobe_read
api_router.include_router(
    recommendations.router,
    prefix="/recommendations",
    tags=["recommendations"],
)
api_router.include_router(
    feedback.router,
    prefix="/feedback",
    tags=["feedback"],
)
api_router.include_router(
    wardrobe_read.router,
    prefix="/wardrobe",
    tags=["wardrobe"],
)
