import pytest
import uuid
from fastapi import HTTPException
from app.core.auth import get_current_user
from fastapi.security import HTTPAuthorizationCredentials
from unittest.mock import patch, MagicMock

@pytest.mark.asyncio
async def test_get_current_user_invalid_token():
    creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials="invalid-token")
    with patch("app.core.auth._get_rsa_key", side_effect=HTTPException(status_code=401, detail="Invalid")):
        with pytest.raises(HTTPException) as excinfo:
            await get_current_user(creds)
        assert excinfo.value.status_code == 401

@pytest.mark.asyncio
async def test_get_current_user_valid_token():
    creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials="valid-token")
    user_id = str(uuid.uuid4())
    payload = {"sub": user_id}
    with patch("app.core.auth._get_rsa_key", return_value={}):
        with patch("jose.jwt.decode", return_value=payload):
            result = await get_current_user(creds)
            assert result == uuid.UUID(user_id)
