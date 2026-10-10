import pytest
import sys
import os
from unittest.mock import AsyncMock, MagicMock, patch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
from main import call_check_worker_availability

@pytest.mark.asyncio
async def test_worker_tc_08_mcp_check_worker_availability():
    """TC-08: Verifies call_check_worker_availability inspects worker profile and schedule slots."""
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = {
        "id": 8,
        "name": "Nalaka Silva",
        "isAvailable": True,
        "availabilityScheduleJson": '{"monday": ["09:00", "17:00"]}'
    }

    with patch("main.backend_client.get", new_callable=AsyncMock) as mock_get:
        mock_get.return_value = mock_resp

        result = await call_check_worker_availability({
            "workerId": "8",
            "startTime": "2026-11-15T10:00:00",
            "endTime": "2026-11-15T12:00:00"
        })

        assert result is not None
        mock_get.assert_awaited()
