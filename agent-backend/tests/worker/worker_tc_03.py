import pytest
from agent_backend.tools.worker_matching_tools import normalize_service_category

def test_worker_tc_03_normalize_service_category():
    """TC-03: Verifies normalize_service_category maps synonyms and keywords to official Workio categories."""
    assert normalize_service_category("pipe leak under sink") == "Plumbing"
    assert normalize_service_category("water tap") == "Plumbing"
    assert normalize_service_category("house wiring") == "Electrical"
    assert normalize_service_category("short circuit fuse") == "Electrical"
    assert normalize_service_category("car repair mechanic") == "Vehicle Repair & Mechanic"
    assert normalize_service_category("ac not cooling") == "AC & Air Conditioning"
    assert normalize_service_category("wood door lock") == "Carpentry"
    assert normalize_service_category(None) is None
    assert normalize_service_category("") is None
