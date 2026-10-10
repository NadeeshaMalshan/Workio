import pytest
from unittest.mock import AsyncMock, patch
from agent_backend.tools.worker_matching_tools import get_worker_details

@pytest.mark.asyncio
async def test_worker_tc_08_get_worker_details_tool():
    """TC-08: Verifies get_worker_details properly delegates to MCP client with worker ID."""
    mock_detail = {
        "id": 42,
        "name": "Jagath Silva",
        "primaryServiceArea": "Nugegoda",
        "hourlyRate": 2200,
        "isVerified": True,
        "overallRating": 4.9
    }

    with patch("agent_backend.tools.worker_matching_tools.mcp_client.call_tool", new_callable=AsyncMock) as mock_mcp:
        mock_mcp.return_value = mock_detail

        result = await get_worker_details.ainvoke({"workerId": "42"})

        assert result["id"] == 42
        assert result["name"] == "Jagath Silva"
        mock_mcp.assert_awaited_once_with("get_worker_details", {"workerId": "42"})
