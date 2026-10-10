import pytest
import sys
import os
from unittest.mock import AsyncMock, MagicMock, patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
from main import call_search_workers

@pytest.mark.asyncio
async def test_worker_tc_02_mcp_search_workers_proximity():
    """TC-02: Verifies call_search_workers calculates distances and sorts closest workers first."""
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = [
        {
            "id": 1,
            "name": "Kandy Worker",
            "primaryServiceArea": "Kandy",
            "locationLat": 7.2906,
            "locationLng": 80.6337
        },
        {
            "id": 2,
            "name": "Dehiwala Worker",
            "primaryServiceArea": "Dehiwala",
            "locationLat": 6.8511,
            "locationLng": 79.8659
        }
    ]

    with patch("main.backend_client.get", new_callable=AsyncMock) as mock_get:
        mock_get.return_value = mock_resp

        # Resident is in Colombo (6.9271, 79.8612)
        result = await call_search_workers({
            "skill": "Electrical",
            "residentLat": 6.9271,
            "residentLng": 79.8612
        })

        assert len(result) == 2
        # Dehiwala (~8.4 km) must be ordered before Kandy (~95 km)
        assert result[0]["name"] == "Dehiwala Worker"
        assert result[1]["name"] == "Kandy Worker"
        assert result[0]["distance"] < result[1]["distance"]
