import pytest
from langchain_core.messages import HumanMessage, AIMessage, ToolMessage
from agent_backend.utils.card_builders import _deterministic_card_builder

def test_delete_post_intent_does_not_return_edit_card():
    """Verify that when a user asks to delete a post, the card builder returns delete confirmation, NOT an edit post card."""
    user_msg = HumanMessage(content="can you delete hty post")
    tool_msg = ToolMessage(
        name="get_community_posts",
        content='[{"id": 2, "postId": 2, "title": "hty", "content": "jtyjty", "serviceCategoryId": "Plumbing", "location": "Colombo"}]',
        tool_call_id="call_123"
    )
    ai_msg = AIMessage(
        content='I found your active post **"hty"** (post #2). Would you like me to delete it? Please confirm before I remove it.'
    )

    state = {
        "messages": [user_msg, tool_msg, ai_msg],
        "email": "user@workio.lk",
        "user_type": "Resident",
        "metadata": {"agent": "community_agent"}
    }

    card_resp = _deterministic_card_builder(state, ai_message=ai_msg)

    # Must NOT be edit_community_post or post_confirmation with update action
    assert card_resp.response_type != "edit_community_post"
    assert card_resp.response_type == "text_message"
    assert card_resp.card_data.get("suggestions") is not None
    assert any("delete" in s.lower() for s in card_resp.card_data["suggestions"])
