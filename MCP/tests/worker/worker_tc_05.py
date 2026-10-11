import pytest
import sys
import os
from unittest.mock import AsyncMock, MagicMock, patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
from main import call_search_workers

@pytest.mark.asyncio
async def test_worker_tc_05_mcp_search_workers_pagination():
    """TC-05: Verifies call_search_workers slices output based on pageSize and page."""
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = [
        {"id": 1, "name": "Worker 1"},
        {"id": 2, "name": "Worker 2"},
        {"id": 3, "name": "Worker 3"},
        {"id": 4, "name": "Worker 4"},
    ]

    with patch("main.backend_client.get", new_callable=AsyncMock) as mock_get:
        mock_get.return_value = mock_resp

        # Request page 2 with pageSize 2
        result = await call_search_workers({
            "page": 2,
            "pageSize": 2
        })

        assert len(result) == 2
        assert result[0]["name"] == "Worker 3"
        assert result[1]["name"] == "Worker 4"
