import pytest
import sys
import os
from unittest.mock import AsyncMock, MagicMock, patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
from main import call_search_workers

@pytest.mark.asyncio
async def test_worker_tc_03_mcp_search_workers_budget():
    """TC-03: Verifies call_search_workers filters workers by maxHourlyRate and minHourlyRate."""
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = [
        {"id": 1, "name": "Worker 1500", "hourlyRate": 1500},
        {"id": 2, "name": "Worker 2500", "hourlyRate": 2500},
        {"id": 3, "name": "Worker 4000", "hourlyRate": 4000},
    ]

    with patch("main.backend_client.get", new_callable=AsyncMock) as mock_get:
        mock_get.return_value = mock_resp

        result = await call_search_workers({
            "skill": "Plumbing",
            "maxHourlyRate": 3000,
            "minHourlyRate": 2000
        })

        assert len(result) == 1
        assert result[0]["name"] == "Worker 2500"
