import pytest
from agent_backend.tools.worker_matching_tools import haversine_distance

def test_worker_tc_01_haversine_distance_calculation():
    """TC-01: Verifies haversine_distance accurately calculates proximity between coordinates."""
    # Distance from Colombo (6.9271, 79.8612) to Dehiwala (6.8511, 79.8659)
    dist_colombo_dehiwala = haversine_distance(6.9271, 79.8612, 6.8511, 79.8659)
    assert 8.0 <= dist_colombo_dehiwala <= 9.0

    # Distance to identical point must be 0.0
    zero_dist = haversine_distance(6.9271, 79.8612, 6.9271, 79.8612)
    assert zero_dist == 0.0

    # Distance from Colombo to Kandy (7.2906, 80.6337) ~ 90-100 km
    dist_kandy = haversine_distance(6.9271, 79.8612, 7.2906, 80.6337)
    assert 90.0 <= dist_kandy <= 110.0
