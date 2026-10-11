import pytest
import sys
import os
from unittest.mock import AsyncMock, MagicMock, patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
from main import call_get_worker_performance

@pytest.mark.asyncio
async def test_worker_tc_07_mcp_get_worker_performance():
    """TC-07: Verifies call_get_worker_performance queries backend worker performance endpoint."""
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = {
        "id": 15,
        "overallRating": 4.9,
        "completedJobs": 40,
        "acceptanceRate": "98.0%"
    }

    with patch("main.backend_client.get", new_callable=AsyncMock) as mock_get:
        mock_get.return_value = mock_resp

        result = await call_get_worker_performance({"workerId": "15"})

        assert result["id"] == 15
        assert result["completedJobs"] == 40
        assert result["acceptanceRate"] == "98.0%"
        mock_get.assert_awaited_once_with("/api/Workers/15/performance")
