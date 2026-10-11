import pytest
from unittest.mock import AsyncMock, patch
from agent_backend.tools.worker_matching_tools import search_workers

@pytest.mark.asyncio
async def test_worker_tc_07_resilient_fallback_on_location_miss():
    """TC-07: Verifies fallback search without location when location-specific query returns empty."""
    with patch("agent_backend.tools.worker_matching_tools.mcp_client.call_tool", new_callable=AsyncMock) as mock_mcp:
        # First call with location returns empty list, second call (fallback without location) returns workers
        mock_mcp.side_effect = [
            [],
            [{"id": 10, "name": "Regional Worker", "primaryServiceArea": "Colombo", "hourlyRate": 2000}]
        ]

        result = await search_workers.ainvoke({
            "skill": "Plumbing",
            "location": "RemoteTownXYZ"
        })

        assert len(result) == 1
        assert result[0]["name"] == "Regional Worker"
        assert mock_mcp.await_count == 2
