import pytest
from uuid import UUID
from fastapi import HTTPException
from jose import jwt
from app.core.auth import get_current_user
from fastapi.security import HTTPAuthorizationCredentials

def test_get_current_user_debug_bypass():
    """Verify local bypass token works in test environment"""
    creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials="debug-token-123")
    
    # Check if the function is async. Fastapi Depends resolves it, but here we call it directly.
    import inspect
    if inspect.iscoroutinefunction(get_current_user):
        import asyncio
        user_id = asyncio.run(get_current_user(creds))
    else:
        user_id = get_current_user(creds)
        
    assert isinstance(user_id, UUID)
    assert str(user_id) == "11111111-1111-1111-1111-111111111111"

@pytest.mark.asyncio
async def test_get_current_user_invalid_token(mocker):
    """Verify invalid tokens trigger 401 Unauthorized"""
    creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials="invalid.jwt.token")
    
    with pytest.raises(HTTPException) as exc_info:
        await get_current_user(creds)
        
    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == "Invalid token header"
