import pytest
from agent_backend.tools.worker_matching_tools import (
    WORKER_MATCHING_TOOLS,
    search_workers,
    get_worker_details,
    get_worker_performance
)

def test_worker_tc_10_worker_matching_tools_registry():
    """TC-10: Verifies WORKER_MATCHING_TOOLS exposes required tools with accurate schemas."""
    tool_names = [t.name for t in WORKER_MATCHING_TOOLS]

    assert "search_workers" in tool_names
    assert "get_worker_details" in tool_names
    assert "get_worker_performance" in tool_names
    assert len(WORKER_MATCHING_TOOLS) == 3

    # Check search_workers schema parameters
    schema = search_workers.args_schema.model_json_schema()["properties"]
    assert "skill" in schema
    assert "location" in schema
    assert "residentLat" in schema
    assert "maxHourlyRate" in schema
