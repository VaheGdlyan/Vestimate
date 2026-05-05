from fastapi import FastAPI
from app.api.v1 import api_router
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from app.core.rate_limit import limiter

app = FastAPI(title="Vestimate API", version="0.1.0")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

from app.api.v1.endpoints.wardrobe_read import router as wardrobe_read_router

app.include_router(api_router, prefix="/v1")
app.include_router(wardrobe_read_router, prefix="/v1/wardrobe", tags=["wardrobe"])

@app.get("/health")
def health():
    return {"status": "ok"}
