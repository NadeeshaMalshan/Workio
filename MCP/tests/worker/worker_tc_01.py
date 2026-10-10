import pytest
import sys
import os
from unittest.mock import AsyncMock, MagicMock, patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
from main import call_search_workers

@pytest.mark.asyncio
async def test_worker_tc_01_mcp_search_workers_basic():
    """TC-01: Verifies call_search_workers formats query params and queries backend client."""
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = [
        {
            "id": 10,
            "name": "Kamal Perera",
            "primaryServiceArea": "Colombo",
            "hourlyRate": 2500,
            "locationLat": 6.9271,
            "locationLng": 79.8612
        }
    ]

    with patch("main.backend_client.get", new_callable=AsyncMock) as mock_get:
        mock_get.return_value = mock_resp

        result = await call_search_workers({
            "skill": "Plumbing",
            "location": "Colombo"
        })

        assert isinstance(result, list)
        assert len(result) == 1
        assert result[0]["name"] == "Kamal Perera"
        mock_get.assert_awaited_once()
        params = mock_get.await_args[1]["params"]
        assert params["skill"] == "Plumbing"
