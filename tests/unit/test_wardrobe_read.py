import pytest
import uuid
from app.services.wardrobe_read import list_wardrobe_items, get_wardrobe_item, archive_wardrobe_item
from unittest.mock import patch, MagicMock

@pytest.mark.asyncio
async def test_list_wardrobe_items_pagination():
    user_id = uuid.uuid4()
    with patch("asyncpg.connect") as mock_connect:
        mock_conn = mock_connect.return_value
        mock_conn.fetchval.return_value = 10
        mock_conn.fetch.return_value = []
        
        result = await list_wardrobe_items(user_id, page=1, limit=5)
        assert result.total == 10
        assert result.page == 1
        assert result.limit == 5

@pytest.mark.asyncio
async def test_get_wardrobe_item_not_found():
    user_id = uuid.uuid4()
    item_id = uuid.uuid4()
    with patch("asyncpg.connect") as mock_connect:
        mock_conn = mock_connect.return_value
        mock_conn.fetchrow.return_value = None
        
        result = await get_wardrobe_item(user_id, item_id)
        assert result is None
