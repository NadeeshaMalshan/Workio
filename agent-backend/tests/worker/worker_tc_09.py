import pytest
from unittest.mock import AsyncMock, patch
from agent_backend.tools.worker_matching_tools import get_worker_performance

@pytest.mark.asyncio
async def test_worker_tc_09_get_worker_performance_tool():
    """TC-09: Verifies get_worker_performance retrieves performance metrics via MCP."""
    mock_metrics = {
        "id": 15,
        "name": "Ruwan Perera",
        "overallRating": 4.85,
        "completedJobs": 32,
        "acceptanceRate": "96.0%",
        "completionRate": "97.5%"
    }

    with patch("agent_backend.tools.worker_matching_tools.mcp_client.call_tool", new_callable=AsyncMock) as mock_mcp:
        mock_mcp.return_value = mock_metrics

        result = await get_worker_performance.ainvoke({"workerId": "15"})

        assert result["id"] == 15
        assert result["completedJobs"] == 32
        assert result["acceptanceRate"] == "96.0%"
        mock_mcp.assert_awaited_once_with("get_worker_performance", {"workerId": "15"})
