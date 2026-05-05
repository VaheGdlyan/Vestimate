from fastapi import FastAPI
from app.api.v1 import api_router
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from app.core.rate_limit import limiter

app = FastAPI(title="Vestimate API", version="0.1.0")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

from app.api.v1.endpoints.wardrobe_read import router as wardrobe_read_router
from app.api.v1.endpoints.feedback import router as feedback_router
from app.api.v1.endpoints.users import router as users_router
from app.core.observability import init_all

@app.on_event("startup")
async def startup():
    init_all(app)

app.include_router(api_router, prefix="/v1")
app.include_router(wardrobe_read_router, prefix="/v1/wardrobe", tags=["wardrobe"])
app.include_router(feedback_router, prefix="/v1/feedback", tags=["feedback"])
app.include_router(users_router, prefix="/v1/users", tags=["users"])

@app.get("/health")
def health():
    return {"status": "ok"}
