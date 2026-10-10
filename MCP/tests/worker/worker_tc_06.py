import pytest
import sys
import os
from unittest.mock import AsyncMock, MagicMock, patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
from main import call_get_worker_details

@pytest.mark.asyncio
async def test_worker_tc_06_mcp_get_worker_details():
    """TC-06: Verifies call_get_worker_details queries backend worker detail endpoint."""
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = {
        "id": 12,
        "name": "Prasanna Fernando",
        "primaryServiceArea": "Negombo",
        "isVerified": True
    }

    with patch("main.backend_client.get", new_callable=AsyncMock) as mock_get:
        mock_get.return_value = mock_resp

        result = await call_get_worker_details({"workerId": "12"})

        assert result["id"] == 12
        assert result["name"] == "Prasanna Fernando"
        mock_get.assert_awaited_once_with("/api/Workers/12")
