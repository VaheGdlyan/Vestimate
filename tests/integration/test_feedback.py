import pytest
import uuid
import httpx

@pytest.mark.asyncio
async def test_feedback_no_auth():
    async with httpx.AsyncClient(base_url="http://localhost:8000") as client:
        resp = await client.post("/v1/feedback/", json={
            "recommendation_id": str(uuid.uuid4()),
            "action": "worn",
            "item_ids": [str(uuid.uuid4())]
        })
        assert resp.status_code == 403
