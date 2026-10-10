import pytest
from agent_backend.tools.worker_matching_tools import get_city_coords

def test_worker_tc_02_get_city_coords_resolution():
    """TC-02: Verifies get_city_coords resolves coordinates for Sri Lankan cities and handles unknowns."""
    # Test major cities
    colombo = get_city_coords("Colombo 03, Sri Lanka")
    assert colombo is not None
    assert colombo == (6.9271, 79.8612)

    kandy = get_city_coords("Kandy")
    assert kandy == (7.2906, 80.6337)

    galle = get_city_coords("Galle Fort")
    assert galle == (6.0535, 80.2210)

    # Unknown city and empty / None location
    assert get_city_coords("Paris, France") is None
    assert get_city_coords(None) is None
    assert get_city_coords("") is None
