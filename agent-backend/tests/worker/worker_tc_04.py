import pytest
from unittest.mock import AsyncMock, patch
from agent_backend.tools.worker_matching_tools import search_workers

@pytest.mark.asyncio
async def test_worker_tc_04_search_workers_delegation():
    """TC-04: Verifies search_workers properly normalizes categories and calls MCP search_workers."""
    mock_workers = [
      {
        "id": 1,
        "name": "Kamal Perera",
        "primaryServiceArea": "Colombo",
        "hourlyRate": 2500,
        "locationLat": 6.9271,
        "locationLng": 79.8612
      }
    ]

    with patch("agent_backend.tools.worker_matching_tools.mcp_client.call_tool", new_callable=AsyncMock) as mock_mcp:
        mock_mcp.return_value = mock_workers

        result = await search_workers.ainvoke({
            "skill": "tap leak",
            "location": "Colombo",
            "residentLat": 6.9271,
            "residentLng": 79.8612
        })

        assert isinstance(result, list)
        assert len(result) == 1
        assert result[0]["name"] == "Kamal Perera"
        mock_mcp.assert_awaited_once()

        call_args = mock_mcp.await_args[0][1]
        assert call_args["skill"] == "Plumbing"
        assert call_args["location"] == "Colombo"
