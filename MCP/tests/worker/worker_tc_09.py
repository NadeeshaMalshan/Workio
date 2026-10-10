import pytest
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
from main import haversine_distance, get_city_coords, normalize_service_category

def test_worker_tc_09_mcp_utility_functions():
    """TC-09: Verifies haversine_distance, get_city_coords, and category normalization within MCP."""
    coords = get_city_coords("Colombo")
    assert coords == (6.9271, 79.8612)

    dist = haversine_distance(6.9271, 79.8612, 6.8511, 79.8659)
    assert 8.0 <= dist <= 9.0

    normalized = normalize_service_category("pipe")
    assert normalized == "Plumbing"
