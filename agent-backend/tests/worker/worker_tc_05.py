import pytest
from unittest.mock import AsyncMock, patch
from agent_backend.tools.worker_matching_tools import search_workers

@pytest.mark.asyncio
async def test_worker_tc_05_proximity_ranking_sort():
    """TC-05: Verifies search_workers sorts workers by closest distance to resident coordinates."""
    mock_workers = [
      {
        "id": 1,
        "name": "Far Worker in Kandy",
        "locationLat": 7.2906,
        "locationLng": 80.6337,
        "hourlyRate": 2000
      },
      {
        "id": 2,
        "name": "Close Worker in Dehiwala",
        "locationLat": 6.8511,
        "locationLng": 79.8659,
        "hourlyRate": 2500
      }
    ]

    with patch("agent_backend.tools.worker_matching_tools.mcp_client.call_tool", new_callable=AsyncMock) as mock_mcp:
        mock_mcp.return_value = mock_workers

        # Resident is in Colombo (6.9271, 79.8612)
        result = await search_workers.ainvoke({
            "skill": "Plumbing",
            "residentLat": 6.9271,
            "residentLng": 79.8612
        })

        assert len(result) == 2
        # Dehiwala (~8.5 km) must be ranked first before Kandy (~95 km)
        assert result[0]["name"] == "Close Worker in Dehiwala"
        assert result[1]["name"] == "Far Worker in Kandy"
        assert result[0]["distance"] < result[1]["distance"]
