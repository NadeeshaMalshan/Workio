import pytest
import sys
import os
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
from main import app

@pytest.fixture
def client():
    return TestClient(app)

def test_worker_tc_10_mcp_jsonrpc_search_workers_tool_call(client):
    """TC-10: Verifies full JSON-RPC 2.0 /mcp tools/call protocol dispatch for search_workers."""
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = [
        {"id": 101, "name": "Prasanna", "primaryServiceArea": "Colombo"}
    ]

    with patch("main.backend_client.get", new_callable=AsyncMock) as mock_get:
        mock_get.return_value = mock_resp
        payload = {
            "jsonrpc": "2.0",
            "id": "worker-req-1",
            "method": "tools/call",
            "params": {
                "name": "search_workers",
                "arguments": {
                    "skill": "Plumbing",
                    "location": "Colombo"
                }
            }
        }

        response = client.post("/mcp", json=payload)
        assert response.status_code == 200
        data = response.json()
        assert data["jsonrpc"] == "2.0"
        assert data["id"] == "worker-req-1"
        assert "result" in data
        assert isinstance(data["result"], list)
        assert data["result"][0]["id"] == 101
