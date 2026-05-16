from slowapi import Limiter
from slowapi.util import get_remote_address
from fastapi import Request
from app.core.config import settings

def get_user_id_or_ip(request: Request) -> str:
    """Use authenticated user ID as rate limit key if available, else IP."""
    user_id = getattr(request.state, "user_id", None)
    return str(user_id) if user_id else get_remote_address(request)

limiter = Limiter(
    key_func=get_user_id_or_ip,
    storage_uri=settings.REDIS_URL,
    default_limits=[]
)
