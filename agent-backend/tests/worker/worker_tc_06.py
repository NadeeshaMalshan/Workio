import pytest
from unittest.mock import AsyncMock, patch
from agent_backend.tools.worker_matching_tools import search_workers

@pytest.mark.asyncio
async def test_worker_tc_06_budget_rate_filtering():
    """TC-06: Verifies search_workers enforces maxHourlyRate and minHourlyRate filtering."""
    mock_workers = [
      {"id": 1, "name": "Cheap Worker", "hourlyRate": 1500, "locationLat": 6.9, "locationLng": 79.8},
      {"id": 2, "name": "Mid Worker", "hourlyRate": 2500, "locationLat": 6.9, "locationLng": 79.8},
      {"id": 3, "name": "Expensive Worker", "hourlyRate": 4500, "locationLat": 6.9, "locationLng": 79.8},
    ]

    with patch("agent_backend.tools.worker_matching_tools.mcp_client.call_tool", new_callable=AsyncMock) as mock_mcp:
        mock_mcp.return_value = mock_workers

        # Budget cap of 3000 LKR
        result = await search_workers.ainvoke({
            "skill": "Plumbing",
            "maxHourlyRate": 3000.0,
            "minHourlyRate": 2000.0
        })

        assert len(result) == 1
        assert result[0]["name"] == "Mid Worker"
        assert result[0]["hourlyRate"] == 2500
