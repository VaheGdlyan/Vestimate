import pytest
from httpx import AsyncClient
from app.main import app

@pytest.mark.asyncio
async def test_upload_garment_success(mocker):
    """Test successful image upload enqueues Celery task."""
    
    # Mock CurrentUser dependency
    app.dependency_overrides[app.core.auth.get_current_user] = lambda: "11111111-1111-1111-1111-111111111111"
    
    # Mock R2 Storage
    mock_save = mocker.patch("app.api.v1.endpoints.wardrobe.save_upload_file", return_value="raw/mock_key.jpg")
    
    # Mock Supabase
    mock_supabase = mocker.patch("app.api.v1.endpoints.wardrobe._get_supabase_client")
    
    # Mock Celery Task
    mock_task = mocker.patch("app.api.v1.endpoints.wardrobe.ingest_garment.delay")
    mock_task.return_value.id = "mock-task-uuid"

    # Create dummy image file
    file_payload = {"file": ("test.jpg", b"fake_image_bytes", "image/jpeg")}

    async with AsyncClient(app=app, base_url="http://testserver") as client:
        response = await client.post("/v1/wardrobe/upload", files=file_payload)

    assert response.status_code == 202
    data = response.json()
    assert data["status"] == "processing"
    assert data["task_id"] == "mock-task-uuid"
    assert "item_id" in data
    
    # Verify mocks were called
    mock_save.assert_called_once()
    mock_task.assert_called_once_with(
        item_id=data["item_id"], 
        raw_object_key="raw/mock_key.jpg", 
        user_id="11111111-1111-1111-1111-111111111111"
    )
    
    # Clean up overrides
    app.dependency_overrides.clear()
