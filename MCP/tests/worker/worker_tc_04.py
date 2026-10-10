import pytest
import sys
import os
from unittest.mock import AsyncMock, MagicMock, patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
from main import call_search_workers

@pytest.mark.asyncio
async def test_worker_tc_04_mcp_search_workers_category_normalization():
    """TC-04: Verifies call_search_workers normalizes synonyms into official categories."""
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = []

    with patch("main.backend_client.get", new_callable=AsyncMock) as mock_get:
        mock_get.return_value = mock_resp

        await call_search_workers({
            "skill": "pipe leak"
        })

        mock_get.assert_awaited_once()
        params = mock_get.await_args[1]["params"]
        assert params["skill"] == "Plumbing"
