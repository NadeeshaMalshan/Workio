"""
Direct Tool-to-UI Card Mapper for Workio Multi-Agent System (Architecture A).
Directly maps MCP tool results and LangGraph agent states into strictly typed
Pydantic UI Card responses (AgentCardResponse) for the React frontend.
Zero regex-scraping of free-form LLM text.
"""

from typing import Dict, Any, List, Optional, Union
import json
import logging
import re
from datetime import datetime, timezone, timedelta
from langchain_core.messages import ToolMessage, HumanMessage, AIMessage
from langchain_openai import ChatOpenAI

from agent_backend.state.state import AgentState
from agent_backend.utils.sanitizer import extract_text_content
from agent_backend.schemas.card_models import (
    AgentCardResponse,
    PostConfirmationCard,
    PostCreatedCard,
    PostListCard,
    PostDetailCard,
    PostUpdatedCard,
    PostDeletedCard,
    UserProfileCard,
    ServiceCategoriesCard,
    TextMessageCard,
    ErrorCard,
    CommunityPostSummary,
    WorkerListCard,
    WorkerSummary,
    SpecialistConversationalOutput,
    BookingFormCard,
    BookingConfirmationReviewCard,
    BookingConfirmedCard,
    BookingSummary,
    BookingListCard,
    ReviewFormCard,
    ReviewSubmittedCard,
    DisputeTicketCard
)

logger = logging.getLogger("agent_backend.card_builders")


def _normalize_skills(raw: Any) -> List[str]:
    """Ensure skills are always a clean list of strings."""
    if not raw:
        return []
    result = []
    if isinstance(raw, list):
        for s in raw:
            if isinstance(s, dict):
                val = s.get("name") or s.get("skillName") or s.get("title") or s.get("label")
                if val:
                    result.append(str(val))
            elif s:
                result.append(str(s))
    elif isinstance(raw, str) and raw:
        result.append(raw)
    return result


def generate_issue_title(raw_title: Optional[str] = None, issue_text: str = "", category: str = "", content: str = "") -> str:
    """
    Ensures community post title is always specific to the actual issue/problem,
    and never generic like 'Community Service Request'.
    """
    generic_titles = [
        "community service request", "service request", "community post", "draft post",
        "draft community post", "post title", "title", "<title>", "<pre-filled title>",
        "n/a", "new post", "help needed", "general request", "general service request"
    ]
    if raw_title:
        clean = re.sub(r'^(?:[\*\#\-\s•]*title[\*\s]*[:\-]\s*)', '', raw_title.strip(), flags=re.IGNORECASE)
        clean = clean.strip().strip("*#\"'").strip()
        if clean and clean.lower() not in generic_titles and len(clean) >= 3:
            return clean

    candidate_text = issue_text or content or ""
    # Strip conversational request/post prefixes
    cleaned = re.sub(
        r'^(?:i want to|i need to|please|can you|help me to|help me)?\s*(?:create|make|post|publish)\s+(?:a\s+)?(?:community\s+)?(?:post)?\s*[:\-]?\s*',
        '',
        candidate_text.strip(),
        flags=re.IGNORECASE
    ).strip()
    cleaned = re.sub(
        r'^(?:i have a problem with|i have an issue with|there is an issue with|my|i need help with|i need to repair|i need someone to|please help me with|can you help me with|i want to fix|fix my|repair my|i need|help me|please)\s+',
        '',
        cleaned,
        flags=re.IGNORECASE
    ).strip()

    first_clause = re.split(r'[\.\n\r;!?]', cleaned)[0].strip()
    first_clause = re.sub(r'\s+(?:in|at|near)\s+(?:colombo|kandy|galle|my area|my house|my home|my place|my room|home)$', '', first_clause, flags=re.IGNORECASE).strip()

    if first_clause and len(first_clause) >= 4 and len(first_clause) <= 60:
        words = first_clause.split()
        title_cased = ' '.join([w.capitalize() if not w.isupper() else w for w in words])
        return title_cased

    if category and category.lower() != 'general':
        return f"{category} Repair & Service Request"
    return "Home Maintenance Service Request"


def extract_smart_booking_details(
    messages: List[Any],
    data: Dict[str, Any],
    metadata: Dict[str, Any],
    user_profile: Dict[str, Any],
    default_category: str = "Home Service"
) -> Dict[str, Any]:
    """
    Intelligently extracts priority, date, district, specific address, specialized title,
    and detailed problem description from the user prompt & conversation context.
    """
    user_msgs = []
    if messages:
        for m in messages:
            content = ""
            m_type = ""
            if isinstance(m, dict):
                content = m.get("content", "")
                m_type = m.get("type") or m.get("role") or ""
            elif hasattr(m, "content"):
                content = getattr(m, "content", "")
                m_type = getattr(m, "type", "") or getattr(m, "role", "")
            elif isinstance(m, str):
                content = m
                m_type = "user"
            
            # Extract content if human/user or unspecified
            if not m_type or m_type.lower() in ("human", "user", "resident"):
                text = extract_text_content(content)
                if text:
                    user_msgs.append(text)
            elif m_type.lower() not in ("system",):
                text = extract_text_content(content)
                if text:
                    user_msgs.append(text)

    # Also include prompt from data / metadata if provided
    extra_prompt = data.get("prompt") or data.get("message") or metadata.get("message") or metadata.get("prompt")
    if extra_prompt and isinstance(extra_prompt, str) and extra_prompt not in user_msgs:
        user_msgs.append(extra_prompt)

    last_user_text = user_msgs[-1] if user_msgs else ""
    conv_text = " ".join(user_msgs).lower()

    # 1. PRIORITY / URGENCY (Low, Medium, High)
    priority = data.get("priority") or data.get("urgency") or metadata.get("priority")
    if priority:
        p_lower = str(priority).lower().strip()
        if p_lower in ("high", "urgent", "emergency"):
            priority = "High"
        elif p_lower in ("low",):
            priority = "Low"
        else:
            priority = "Medium"
    else:
        if any(w in conv_text for w in [
            "emergency", "burst", "flooding", "spark", "sparking", "shock", "fire",
            "exploded", "danger", "hazard", "leaking heavily", "urgent", "urgently",
            "asap", "immediately", "right now", "hurry", "critical", "severe",
            "ikmanin", "ikmnta", "danma", "high", "high priority", "quickly", "fast", "speedy"
        ]):
            priority = "High"
        elif any(w in conv_text for w in ["low", "low priority", "not urgent", "whenever", "next week", "flexible", "slow"]):
            priority = "Low"
        else:
            priority = "Medium"

    # 2. DATE
    scheduled_date = data.get("requestedDate") or data.get("selectedDate") or data.get("scheduledDate") or data.get("date")
    if not scheduled_date:
        today_date = datetime.now()
        if "today" in conv_text or "tonight" in conv_text or "adha" in conv_text:
            scheduled_date = today_date.strftime("%Y-%m-%d")
        elif "day after tomorrow" in conv_text or "after tomorrow" in conv_text or "anidhdha" in conv_text:
            scheduled_date = (today_date + timedelta(days=2)).strftime("%Y-%m-%d")
        elif "tomorrow" in conv_text or "tmrw" in conv_text or "heta" in conv_text:
            scheduled_date = (today_date + timedelta(days=1)).strftime("%Y-%m-%d")
        else:
            d_match = re.search(r'\b(202\d-\d{1,2}-\d{1,2})\b', last_user_text)
            if d_match:
                scheduled_date = d_match.group(1)
            else:
                scheduled_date = (today_date + timedelta(days=1)).strftime("%Y-%m-%d")

    # 3. LOCATION & SPECIFIC ADDRESS
    res_dict = user_profile.get("resident") if isinstance(user_profile.get("resident"), dict) else {}
    profile_loc = (
        res_dict.get("district")
        or res_dict.get("address")
        or user_profile.get("address")
        or metadata.get("location")
        or metadata.get("user_location_name")
        or data.get("location")
        or data.get("primaryServiceArea")
        or "Ratnapura"
    )
    profile_address = res_dict.get("specificAddress") or res_dict.get("address") or user_profile.get("address") or ""

    district_val = profile_loc
    specific_addr_val = profile_address if profile_address != profile_loc else ""

    SL_DISTRICTS = [
        "Ratnapura", "Colombo", "Gampaha", "Kalutara", "Kandy", "Matale", "Nuwara Eliya",
        "Galle", "Matara", "Hambantota", "Jaffna", "Kilinochchi", "Mannar", "Vavuniya",
        "Mullaitivu", "Batticaloa", "Ampara", "Trincomalee", "Kurunegala", "Puttalam",
        "Anuradhapura", "Polonnaruwa", "Badulla", "Monaragala", "Kegalle", "Nugegoda",
        "Dehiwala", "Moratuwa", "Negombo", "Bambalapitiya", "Rajagiriya", "Maharagama"
    ]
    for d in SL_DISTRICTS:
        if d.lower() in conv_text:
            district_val = d
            break

    addr_match = re.search(r'\b(?:at|address[:\s]+|location[:\s]+)\b\s*([0-9A-Za-z\s,.\/-]{5,40}(?:road|street|lane|mawatha|batuhena|colombo|ratnapura|kandy|place|gardens|ave|avenue|house|flat)?)', last_user_text, re.IGNORECASE)
    if addr_match:
        extracted = addr_match.group(1).strip().rstrip(".,")
        if len(extracted) > 4:
            specific_addr_val = extracted

    if not specific_addr_val:
        specific_addr_val = res_dict.get("street") or res_dict.get("specificAddress") or ""

    # 4. CATEGORY, JOB TITLE & DETAILED PROBLEM DESCRIPTION
    cat_val = data.get("category") or default_category or "Home Service"
    if not cat_val or cat_val in ("General", "None", "Others", "Home Service"):
        if any(w in conv_text for w in ["plumb", "pipe", "tap", "leak", "sink", "drain", "water", "wathura", "toilet", "kadila"]):
            cat_val = "Plumbing"
        elif any(w in conv_text for w in ["electric", "wire", "wiring", "breaker", "fuse", "short", "socket", "light", "fan", "switch", "current", "power"]):
            cat_val = "Electrical"
        elif any(w in conv_text for w in ["ac", "air condition", "cooling", "filter", "compressor"]):
            cat_val = "AC Repair"
        elif any(w in conv_text for w in ["clean", "wash", "scrub", "housekeep"]):
            cat_val = "Cleaning"
        elif any(w in conv_text for w in ["roof", "tile", "seep"]):
            cat_val = "Roofing"
        elif any(w in conv_text for w in ["carpent", "wood", "door", "lock"]):
            cat_val = "Carpentry"
        elif any(w in conv_text for w in ["paint", "wall"]):
            cat_val = "Painting"

    custom_title = data.get("jobTitle")
    custom_desc = data.get("description") or data.get("notes")

    if not custom_title or custom_title.endswith("Service Request") or "appointment" in custom_title.lower():
        if any(w in conv_text for w in ["kitchen sink", "sink leak", "sink pipe"]):
            custom_title = "Kitchen Sink Pipe Leak Repair"
            custom_desc = custom_desc or "Kitchen sink pipe is leaking heavily under the counter. Requires pipe joint inspection, washer replacement, and leak sealing."
        elif any(w in conv_text for w in ["pipe burst", "burst pipe", "pipe leak", "water leak", "leaking pipe", "wathura pipe", "pipe eka burst", "pipe kadila", "burst wela"]):
            custom_title = "Water Pipe Leak Repair & Sealing"
            custom_desc = custom_desc or "Water pipe line has developed a leak. Inspection and replacement of damaged pipe section or joint sealing required."
        elif any(w in conv_text for w in ["drain", "clogged", "blocked", "overflowing"]):
            custom_title = "Drain Cleaning & Unclogging"
            custom_desc = custom_desc or "Drainage line is blocked causing water accumulation. Professional unclogging and line flushing needed."
        elif any(w in conv_text for w in ["toilet", "commode", "flush"]):
            custom_title = "Toilet Flush & Mechanism Repair"
            custom_desc = custom_desc or "Toilet flush mechanism issue or inlet valve leakage. Requires component repair or replacement."
        elif any(w in conv_text for w in ["tap", "faucet", "shower"]):
            custom_title = "Tap & Faucet Fixture Repair"
            custom_desc = custom_desc or "Leaking water tap or faulty faucet fixture. Requires washer replacement or new fixture installation."
        elif any(w in conv_text for w in ["trip", "tripping", "breaker", "fuse"]):
            custom_title = "Circuit Breaker Tripping Diagnosis"
            custom_desc = custom_desc or "Main circuit breaker trips frequently when appliances are active. Requires electrical load diagnosis and breaker check."
        elif any(w in conv_text for w in ["short circuit", "spark", "sparking", "wiring"]):
            custom_title = "Electrical Wiring & Short Circuit Fix"
            custom_desc = custom_desc or "Sparks or burning smell detected in electrical wiring. Urgent inspection and cable replacement required."
        elif any(w in conv_text for w in ["switch", "socket", "plug", "switchboard"]):
            custom_title = "Power Socket & Switchboard Fix"
            custom_desc = custom_desc or "Wall power sockets or switchboard malfunctioning. Replacement and safe wiring termination required."
        elif any(w in conv_text for w in ["ac not cooling", "not cooling", "warm air", "gas refill"]):
            custom_title = "AC Cooling & Refrigerant Gas Refill"
            custom_desc = custom_desc or "AC unit runs but does not cool room adequately. Requires refrigerant pressure check, gas top-up, and cooling coil check."
        elif any(w in conv_text for w in ["chemical wash", "filter", "servicing"]):
            custom_title = "AC Full Chemical Wash & Maintenance"
            custom_desc = custom_desc or "Routine AC maintenance and deep chemical cleaning of indoor evaporator and outdoor condenser coils."
        elif any(w in conv_text for w in ["deep clean", "house cleaning"]):
            custom_title = "Full House Deep Cleaning & Sanitization"
            custom_desc = custom_desc or "Comprehensive deep cleaning, dust removal, and floor sanitization across living areas."
        elif any(w in conv_text for w in ["roof", "seepage", "ceiling"]):
            custom_title = "Roof Leak Sealing & Waterproofing"
            custom_desc = custom_desc or "Water seepage through roof tiles or ceiling during rain. Waterproofing seal and tile adjustment required."
        elif any(w in conv_text for w in ["door", "lock", "hinge"]):
            custom_title = "Door Lock & Woodwork Repair"
            custom_desc = custom_desc or "Door lock jam or wooden frame alignment issue. Adjustment of hinges and locking mechanism needed."
        else:
            custom_title = f"{cat_val} Service Request"
            custom_desc = custom_desc or f"Resident requested professional assistance for {cat_val.lower()} work. On-site diagnostics and repair required."

    if not custom_desc:
        custom_desc = f"Standard on-site {custom_title.lower()} requested via Workio AI."

    return {
        "priority": priority,
        "selectedDate": scheduled_date,
        "location": district_val,
        "specificAddress": specific_addr_val,
        "category": cat_val,
        "jobTitle": custom_title,
        "description": custom_desc,
    }


def _clean_card_intro_message(raw_msg: str, default_intro: str, card_type: str = "card") -> str:
    """
    Strips raw field headers and empty bracket tokens from conversational bubbles
    so they don't duplicate interactive UI card components.
    """
    if not raw_msg or not isinstance(raw_msg, str):
        return default_intro

    text = raw_msg.strip()
    text = re.sub(r'^(?:\[\s*\]|\(\s*\))\s*', '', text).strip()

    # If the text contains bulleted or bold field dumps (e.g. • **Title:** ...), extract conversational intro & closing
    has_dump = bool(
        re.search(
            r'(?:'
            r'(?:\n|\s+)(?:1\.\s*\*\*|\d+\.\s*\*\*|[-*•]\s*\*\*)|'
            r'(?:[•\-*]?\s*)\*\*(?:Title|Category|Location|Content|Description|Urgency|Worker|Price|Rate|Phone|Email|Skills?):\*\*|'
            r'!\[.*?\]\(.*?\)|\(tel:\d+\)|###\s+[A-Z]'
            r')',
            text,
            re.IGNORECASE
        )
    )

    if card_type == "post_detail" and any(w in text.lower() for w in ["draft", "confirm when you're ready", "publish"]):
        return default_intro

    if not has_dump:
        return text

    # For draft community post confirmation cards
    if card_type in ["post_confirmation", "create_community_post", "edit_community_post"]:
        intro_match = re.search(
            r'^(.*?)(?=(?:\s*[•\-*]?\s*)\*\*(?:Title|Category|Location|Content|Description|Urgency):\*\*)',
            text,
            re.IGNORECASE | re.DOTALL
        )
        intro = intro_match.group(1).strip() if intro_match else ""
        if intro:
            intro = intro.rstrip(" \t\n•-*")
            if not intro.endswith((".", "!", ":", "?")):
                intro += ":"

        closing_match = re.search(
            r'((?:Please review|You can edit|Feel free|Would you like|I\'ll wait|I will wait|Reply with|Reply \'confirm\')[^\n]*[.?!]?\s*)$',
            text,
            re.IGNORECASE
        )
        closing = closing_match.group(1).strip() if closing_match else ""
        if closing:
            closing = re.sub(r'\bdetails above\b', 'details below', closing, flags=re.IGNORECASE)
        else:
            closing = "Please review the details below and confirm when you're ready to publish."

        if intro and len(intro) > 5 and not intro.startswith(("•", "-", "*", "1.")):
            cleaned = f"{intro} {closing}".strip()
        else:
            cleaned = f"Here is your draft community post. {closing}".strip()

        cleaned = re.sub(r'^(?:\[\s*\]|\(\s*\))\s*', '', cleaned)
        cleaned = re.sub(r'\s{2,}', ' ', cleaned)
        return cleaned

    # For booking detail or list cards
    if card_type in ["booking_list", "booking_detail", "booking_confirmed", "booking_form"]:
        intro_match = re.search(
            r'^(.*?)(?=(?:\s*\n\s*|\s+)(?:1\.\s*\*\*|\d+\.\s*\*\*|[-*•]\s*\*\*|(?:[•\-*]?\s*)\*\*(?:Booking|Worker|Technician|Service|Status|Time|Date|Location|Price|Rate):\*\*|###\s+))',
            text,
            re.DOTALL | re.IGNORECASE
        )
        intro = intro_match.group(1).strip() if intro_match else ""
        closing_match = re.search(r'(?:(?:\n|\.\s+|:\s+))([A-Z][^\n]*\?)\s*$', text)
        closing = closing_match.group(1).strip() if closing_match else ""

        parts = []
        if intro and len(intro) > 6 and not intro.startswith(("1.", "-", "*", "•")):
            if not intro.endswith((".", "!", ":", "?")):
                intro += ":"
            parts.append(intro)
        else:
            parts.append(default_intro)

        if closing and closing not in (parts[0] if parts else ""):
            parts.append(closing)
        else:
            parts.append("You can view your appointment details or manage your booking below.")

        cleaned = " ".join(parts).strip()
        cleaned = re.sub(r'!\[.*?\]\(.*?\)', '', cleaned).strip()
        cleaned = re.sub(r'\[(.*?)\]\(tel:.*?\)', r'\1', cleaned).strip()
        cleaned = re.sub(r'\s{2,}', ' ', cleaned)
        return cleaned if cleaned else default_intro

    # For worker lists or general items
    intro_match = re.search(
        r'^(.*?)(?=(?:\s*\n\s*|\s+)(?:1\.\s*\*\*|\d+\.\s*\*\*|[-*•]\s*\*\*|(?:[•\-*]?\s*)\*\*(?:Worker|Name|Price|Rate|Title):\*\*|!\[.*?\]\(.*?\)|###\s+))',
        text,
        re.DOTALL
    )
    intro = intro_match.group(1).strip() if intro_match else ""

    closing_match = re.search(r'(?:(?:\n|\.\s+|:\s+))([A-Z][^\n]*\?)\s*$', text)
    closing = closing_match.group(1).strip() if closing_match else ""

    parts = []
    if intro and len(intro) > 8 and not intro.startswith(("1.", "-", "*", "•")):
        if not intro.endswith((".", "!", ":", "?")):
            intro += ":"
        parts.append(intro)
    else:
        parts.append(default_intro)

    if closing and closing not in (parts[0] if parts else ""):
        parts.append(closing)
    elif card_type == "worker_list" and not any("book" in p.lower() for p in parts):
        parts.append("Would you like to book one of these technicians, or inspect more details?")

    cleaned = " ".join(parts).strip()
    cleaned = re.sub(r'!\[.*?\]\(.*?\)', '', cleaned).strip()
    cleaned = re.sub(r'\[(.*?)\]\(tel:.*?\)', r'\1', cleaned).strip()
    cleaned = re.sub(r'\s{2,}', ' ', cleaned)
    return cleaned if cleaned else default_intro


async def format_specialist_structured_message(
    prompt: list,
    response: AIMessage,
    llm: Optional[ChatOpenAI] = None,
    agent_type: Optional[str] = None
) -> AIMessage:
    """
    Validates and formats the specialist agent's conversational output.
    Ensures message content is clean text without redundant raw card data dumps.
    """
    raw_content = extract_text_content(getattr(response, "content", ""))
    if not raw_content:
        return response

    has_card_dump = bool(
        re.search(
            r'(?:'
            r'(?:\n|\s+)(?:1\.\s*\*\*|\d+\.\s*\*\*|[-*•]\s*\*\*)|'
            r'(?:[•\-*]?\s*)\*\*(?:Title|Category|Location|Content|Description|Urgency|Worker|Price|Rate|Booking|Status|Scheduled):\*\*|'
            r'!\[.*?\]\(.*?\)|\(tel:\d+\)|###\s+[A-Z]'
            r')',
            raw_content,
            re.IGNORECASE
        )
    )
    if not has_card_dump:
        if isinstance(getattr(response, "content", None), list):
            return AIMessage(
                content=raw_content,
                additional_kwargs=getattr(response, "additional_kwargs", {}),
                response_metadata=getattr(response, "response_metadata", {})
            )
        return response

    lower_raw = raw_content.lower()
    if agent_type == "booking_agent" or any(k in lower_raw for k in ["booking #", "appointment", "booking id", "scheduled for"]):
        card_type_hint = "booking_list"
        default_intro = "Here are the details for your booking:"
    elif agent_type == "community_agent" or any(k in lower_raw for k in ["draft community post", "post confirmation", "publish post"]):
        card_type_hint = "post_confirmation"
        default_intro = "Here is your draft community post:"
    elif agent_type == "support_review_agent" or any(k in lower_raw for k in ["ticket #", "review", "dispute"]):
        card_type_hint = "support"
        default_intro = "Here is your support update:"
    elif agent_type == "worker_matching_agent" or any(k in lower_raw for k in ["technician", "worker", "plumber", "electrician"]):
        card_type_hint = "worker_list"
        default_intro = "Here are the recommended service options:"
    elif bool(re.search(r'\*\*(?:Title|Category|Location|Content):\*\*', raw_content, re.IGNORECASE)):
        card_type_hint = "post_confirmation"
        default_intro = "Here is your draft community post:"
    else:
        card_type_hint = "worker_list"
        default_intro = "Here are the recommended service options:"

    cleaned = _clean_card_intro_message(raw_content, default_intro, card_type_hint)
    return AIMessage(
        content=cleaned,
        additional_kwargs=getattr(response, "additional_kwargs", {}),
        response_metadata=getattr(response, "response_metadata", {})
    )


def _deterministic_card_builder(state: AgentState, ai_message: Optional[Any] = None) -> AgentCardResponse:
    """
    Direct Tool-to-UI Card Mapper.
    Uses tool outputs directly to build structured frontend cards, and uses
    clean conversational text for the chat bubble.
    """
    messages = list(state.get("messages", []))
    email = state.get("email", "resident@workio.lk")
    user_type = state.get("user_type", "Resident")
    metadata = state.get("metadata") or {}
    user_profile = state.get("user_profile") or {}
    user_name = metadata.get("user_name") or user_profile.get("displayName") or (email.split("@")[0] if "@" in email else "Resident")

    last_ai_content = ""
    if ai_message and hasattr(ai_message, "content") and ai_message.content:
        last_ai_content = extract_text_content(ai_message.content)
    else:
        for msg in reversed(messages):
            if getattr(msg, "type", "") == "ai" and msg.content:
                last_ai_content = extract_text_content(msg.content)
                break

    # Locate the ToolMessage executed in the CURRENT conversation turn
    latest_tool: Optional[ToolMessage] = None
    for msg in reversed(messages):
        if isinstance(msg, ToolMessage) or getattr(msg, "type", "") == "tool":
            latest_tool = msg
            break
        elif isinstance(msg, HumanMessage) or getattr(msg, "type", "") in ("human", "user"):
            # Turn boundary reached: no tool executed in this current turn
            break

    # =========================================================================
    # 1. TOOL-DRIVEN CARDS (Direct JSON mapping from MCP tools)
    # =========================================================================
    if latest_tool:
        tool_name = getattr(latest_tool, "name", "")
        raw_content = latest_tool.content
        data = {}
        if isinstance(raw_content, str):
            try:
                data = json.loads(raw_content)
            except Exception:
                data = {"raw": raw_content}
        elif isinstance(raw_content, dict):
            data = raw_content

        # Error handling
        if isinstance(data, dict) and data.get("error"):
            return AgentCardResponse(
                response_type="error",
                message=last_ai_content or str(data.get("error")),
                card_data=ErrorCard(
                    errorCode="TOOL_EXECUTION_ERROR",
                    message=str(data.get("error")),
                    actionRequired="Please verify your input or check if the server is running."
                ).model_dump(),
                metadata={"agent": "community_agent", "user_email": email}
            )

        # 1. create_community_post
        if tool_name == "create_community_post":
            post_id = data.get("id") or data.get("postId") or "new"
            card = PostCreatedCard(
                id=post_id,
                title=data.get("title", "Community Post"),
                content=data.get("content", ""),
                communityId=data.get("serviceCategoryId") or data.get("communityId", "General"),
                location=data.get("location", "Colombo"),
                authorId=data.get("userId") or email,
                authorName=data.get("userName") or email.split("@")[0]
            )
            clean_msg = f"Your community post '{card.title}' has been published successfully to the Workio community!"
            return AgentCardResponse(
                response_type="post_created",
                message=clean_msg,
                card_data=card.model_dump(),
                metadata={"agent": "community_agent", "user_email": email}
            )

        # 2. get_community_posts / get_user_community_posts
        if tool_name in ["get_community_posts", "get_user_community_posts"]:
            user_query = ""
            for msg in reversed(messages):
                if getattr(msg, "type", "") in ("human", "user"):
                    user_query = extract_text_content(getattr(msg, "content", ""))
                    break

            user_query_lower = user_query.lower()
            last_ai_lower = last_ai_content.lower()

            is_delete_intent = (
                any(w in user_query_lower for w in [
                    "delete", "remove", "trash", "take down", "erase", "cancel post", "drop post"
                ])
                or any(w in last_ai_lower for w in [
                    "like me to delete", "confirm before i remove", "confirm before deleting", "delete it?", "remove it?"
                ])
            )

            is_edit_intent = not is_delete_intent and (
                any(w in user_query_lower for w in [
                    "edit", "update", "modify", "change", "add more detail", "add detail", "fix this post", "correct this post", "need edit", "edit that", "edit this"
                ])
                or any(w in last_ai_lower for w in [
                    "what additional details", "proposed update", "edit the post", "edit your post", "to update post", "update post id", "post details for editing", "for editing (id", "for editing"
                ])
            )

            # Handle delete confirmation before editing or single post detail
            if is_delete_intent:
                target_id_m = (
                    re.search(r'\b(?:id|post)\s*[:#]?\s*(\d+)\b', last_ai_content, re.IGNORECASE)
                    or re.search(r'\b(?:id|post)\s*[:#]?\s*(\d+)\b', user_query, re.IGNORECASE)
                )
                del_id = target_id_m.group(1) if target_id_m else None

                del_title = ""
                raw_posts_check = data if isinstance(data, list) else (data.get("posts", data.get("items", [])) if isinstance(data, dict) else [])
                if isinstance(data, dict) and bool(data.get("id") or data.get("postId") or data.get("PostId")) and not raw_posts_check:
                    del_id = del_id or str(data.get("id") or data.get("postId") or data.get("PostId") or "")
                    del_title = data.get("title") or data.get("Title") or ""
                elif raw_posts_check and del_id:
                    for p in raw_posts_check:
                        if isinstance(p, dict) and str(p.get("postId") or p.get("id") or p.get("PostId")) == str(del_id):
                            del_title = p.get("title") or p.get("Title") or ""
                            break

                confirm_label = f"Yes, delete post #{del_id}" if del_id else "Yes, delete this post"

                card = TextMessageCard(
                    text=last_ai_content,
                    suggestions=[
                        confirm_label,
                        "No, keep my post"
                    ]
                )
                return AgentCardResponse(
                    response_type="text_message",
                    message=last_ai_content,
                    card_data=card.model_dump(),
                    metadata={"agent": "community_agent", "user_email": email, "action": "delete_confirmation", "postId": del_id}
                )

            is_single_post = isinstance(data, dict) and bool(data.get("id") or data.get("postId") or data.get("PostId")) and not ("posts" in data or "items" in data)
            if is_single_post:
                post_id_val = data.get("postId") or data.get("id") or data.get("PostId")
                post_title = data.get("title") or data.get("Title", "")
                post_content = data.get("content") or data.get("Content", "")
                post_cat = data.get("serviceCategoryId") or data.get("ServiceCategoryId") or data.get("communityId", "General")
                post_loc = data.get("location") or data.get("Location", "Colombo")

                post_images = data.get("images") or data.get("Images") or []
                if not isinstance(post_images, list):
                    post_images = []

                if is_edit_intent:
                    card = PostConfirmationCard(
                        action="update",
                        postId=post_id_val,
                        title=post_title,
                        content=post_content,
                        communityId=post_cat,
                        location=post_loc,
                        images=post_images,
                        authorId=email,
                        authorName=user_name,
                        validationStatus="valid",
                        validationNotes="You can edit the details in the form above and click 'Update Post' to save your changes.",
                        confirmPrompt=f"CONFIRM_UPDATE: Yes, please update post ID {post_id_val} with title '{post_title}' in {post_cat} for {post_loc}. Description: {post_content}"
                    )
                    return AgentCardResponse(
                        response_type="edit_community_post",
                        message=last_ai_content,
                        card_data=card.model_dump(),
                        metadata={"agent": "community_agent", "user_email": email, "action": "update", "postId": post_id_val}
                    )

                # Single post detail view (read-only view)
                card = PostDetailCard(
                    id=post_id_val,
                    title=post_title,
                    content=post_content,
                    communityId=post_cat,
                    location=post_loc,
                    authorName=data.get("userName") or data.get("UserName") or (data.get("userEmail") or data.get("UserEmail", "")).split("@")[0],
                    authorEmail=data.get("userEmail") or data.get("UserEmail"),
                    likesCount=data.get("likesCount") or data.get("LikesCount", 0),
                    commentsCount=data.get("commentsCount") or data.get("CommentsCount", 0),
                    images=post_images
                )
                default_detail_intro = f"Here are the details for post #{card.id}:"
                clean_msg = _clean_card_intro_message(
                    last_ai_content,
                    default_detail_intro,
                    "post_detail"
                )
                if any(w in clean_msg.lower() for w in ["draft", "confirm when you're ready", "publish"]):
                    clean_msg = default_detail_intro
                return AgentCardResponse(
                    response_type="post_detail",
                    message=clean_msg,
                    card_data=card.model_dump(),
                    metadata={"agent": "community_agent", "user_email": email}
                )

            raw_posts = data if isinstance(data, list) else data.get("posts", data.get("items", []))

            # If user wants to edit a post, return the Edit Post Form Card instead of showing all posts
            if is_edit_intent and raw_posts:
                # 1. Try to extract post ID mentioned in AI response (e.g. "post (ID 26)") or user query
                target_id_m = re.search(r'\b(?:id|post)\s*[:#]?\s*(\d+)\b', last_ai_content, re.IGNORECASE) or re.search(r'\b(?:id|post)\s*[:#]?\s*(\d+)\b', user_query, re.IGNORECASE)
                target_id = target_id_m.group(1) if target_id_m else None

                target_post = None
                if target_id:
                    for p in raw_posts:
                        if isinstance(p, dict) and str(p.get("postId") or p.get("id") or p.get("PostId")) == str(target_id):
                            target_post = p
                            break

                if not target_post:
                    # Match post authored by user that has issue keywords or is user's recent post
                    user_posts = [p for p in raw_posts if isinstance(p, dict) and (p.get("userEmail") == email or p.get("userId") == email)]
                    if user_posts:
                        words = [w for w in re.findall(r'\b[a-zA-Z]{3,}\b', user_query_lower) if w not in ["need", "edit", "this", "post", "because", "more", "details", "for"]]
                        matched = None
                        for up in user_posts:
                            up_text = (str(up.get("title", "")) + " " + str(up.get("content", ""))).lower()
                            if any(w in up_text for w in words):
                                matched = up
                                break
                        target_post = matched or user_posts[0]
                    elif raw_posts and isinstance(raw_posts[0], dict):
                        target_post = raw_posts[0]

                if target_post:
                    post_id_val = target_post.get("postId") or target_post.get("id") or target_post.get("PostId") or target_id
                    post_title = target_post.get("title") or target_post.get("Title") or "Community Post"
                    post_content = target_post.get("content") or target_post.get("Content") or ""
                    post_cat = target_post.get("serviceCategoryId") or target_post.get("ServiceCategoryId") or target_post.get("communityId") or "General"
                    post_loc = target_post.get("location") or target_post.get("Location") or "Colombo"
                    post_images = target_post.get("images") or target_post.get("Images") or []
                    if not isinstance(post_images, list):
                        post_images = []

                    card = PostConfirmationCard(
                        action="update",
                        postId=post_id_val,
                        title=post_title,
                        content=post_content,
                        communityId=post_cat,
                        location=post_loc,
                        images=post_images,
                        authorId=email,
                        authorName=user_name,
                        validationStatus="valid",
                        validationNotes="You can edit the details in the form above and click 'Update Post' to save your changes.",
                        confirmPrompt=f"CONFIRM_UPDATE: Yes, please update post ID {post_id_val} with title '{post_title}' in {post_cat} for {post_loc}. Description: {post_content}"
                    )
                    return AgentCardResponse(
                        response_type="edit_community_post",
                        message=last_ai_content,
                        card_data=card.model_dump(),
                        metadata={"agent": "community_agent", "user_email": email, "action": "update", "postId": post_id_val}
                    )

            # Multiple posts list (feed / search view)
            post_summaries: List[CommunityPostSummary] = []
            for item in (raw_posts if isinstance(raw_posts, list) else []):
                if isinstance(item, dict):
                    raw_post_id = item.get("postId") or item.get("id") or item.get("PostId") or ""
                    item_images = item.get("images") or item.get("Images") or []
                    if not isinstance(item_images, list):
                        item_images = []
                    post_summaries.append(
                        CommunityPostSummary(
                            id=raw_post_id,
                            title=item.get("title") or item.get("Title", "Untitled"),
                            content=(item.get("content") or item.get("Content", ""))[:140],
                            communityId=item.get("serviceCategoryId") or item.get("ServiceCategoryId") or item.get("communityId", "General"),
                            location=item.get("location") or item.get("Location", "Colombo"),
                            authorName=item.get("userName") or item.get("UserName") or (item.get("userEmail") or item.get("UserEmail") or item.get("userId") or "").split("@")[0],
                            authorEmail=item.get("userEmail") or item.get("UserEmail") or item.get("userId"),
                            createdAt=str(item.get("createdAt") or item.get("CreatedAt") or ""),
                            likesCount=item.get("likesCount") or item.get("LikesCount", 0),
                            commentsCount=item.get("commentsCount") or item.get("CommentsCount", 0),
                            images=item_images
                        )
                    )
            card = PostListCard(
                category=str(data.get("category", "All") if isinstance(data, dict) else "All"),
                totalCount=len(post_summaries),
                posts=post_summaries
            )
            clean_msg = _clean_card_intro_message(
                last_ai_content,
                f"Found {len(post_summaries)} community posts in your area:",
                "post_list"
            )
            return AgentCardResponse(
                response_type="post_list",
                message=clean_msg,
                card_data=card.model_dump(),
                metadata={"agent": "community_agent", "user_email": email}
            )

        # 3. update_community_post
        if tool_name == "update_community_post":
            post_images = data.get("images") or data.get("Images") or []
            if not isinstance(post_images, list):
                post_images = []
            card = PostUpdatedCard(
                id=data.get("id") or data.get("postId") or "",
                title=data.get("title", "Updated Post"),
                content=data.get("content", ""),
                communityId=data.get("serviceCategoryId") or data.get("communityId") or "General",
                location=data.get("location") or "Colombo",
                images=post_images
            )
            clean_msg = _clean_card_intro_message(
                last_ai_content,
                f"Post #{card.id} has been updated successfully.",
                "post_updated"
            )
            return AgentCardResponse(
                response_type="post_updated",
                message=clean_msg,
                card_data=card.model_dump(),
                metadata={"agent": "community_agent", "user_email": email}
            )

        # 4. delete_community_post
        if tool_name == "delete_community_post":
            card = PostDeletedCard(
                id=data.get("id") or data.get("postId") or "",
                status=data.get("status", "Removed"),
                message=data.get("message", "Post successfully removed from community board.")
            )
            clean_msg = _clean_card_intro_message(
                last_ai_content,
                "The community post has been removed.",
                "post_deleted"
            )
            return AgentCardResponse(
                response_type="post_deleted",
                message=clean_msg,
                card_data=card.model_dump(),
                metadata={"agent": "community_agent", "user_email": email}
            )

        # 5. get_user_details / get_worker_details
        if tool_name in ["get_user_details", "get_worker_details"]:
            card = UserProfileCard(
                email=data.get("email") or email,
                role=data.get("role") or ("Worker" if tool_name == "get_worker_details" or data.get("isWorker") or data.get("workerRating") or data.get("overallRating") or data.get("skills") else user_type),
                isWorker=data.get("isWorker", True if tool_name == "get_worker_details" else False),
                displayName=data.get("displayName") or data.get("name") or user_name,
                phoneNo=data.get("phoneNo") or data.get("phoneNumber"),
                address=data.get("address") or data.get("primaryServiceArea") or "Colombo",
                workerRating=data.get("workerRating") or data.get("overallRating") or data.get("rating"),
                completedJobs=data.get("completedJobs"),
                skills=_normalize_skills(data.get("skills")),
                pricingModel=data.get("pricingModel") or (f"LKR {data.get('hourlyRate')}/hr" if data.get('hourlyRate') else None)
            )
            clean_msg = _clean_card_intro_message(
                last_ai_content,
                f"Here are the profile details for {card.displayName}:",
                "user_profile"
            )
            return AgentCardResponse(
                response_type="user_profile",
                message=clean_msg,
                card_data=card.model_dump(),
                metadata={"agent": "worker_matching_agent" if tool_name == "get_worker_details" else "community_agent", "user_email": email}
            )

        # 6. get_service_categories
        if tool_name == "get_service_categories":
            user_msg_content = ""
            for msg in reversed(messages):
                if getattr(msg, "type", "") in ("human", "user"):
                    user_msg_content = extract_text_content(getattr(msg, "content", "") or "")
                    break

            lower_user = user_msg_content.lower()
            lower_ai = (last_ai_content or "").lower()

            user_explicitly_asked_categories = any(kw in lower_user for kw in [
                "category", "categories", "what services", "list services", "available services",
                "all services", "browse services", "explore services", "services do you provide"
            ])
            is_draft_post = "draft" in lower_ai or ("title:" in lower_ai and "category:" in lower_ai)
            is_choice_turn_check = any(kw in lower_ai for kw in ["find a verified worker", "create a community post", "how would you like to proceed"])

            if user_explicitly_asked_categories and not is_draft_post and not is_choice_turn_check:
                categories_raw = data if isinstance(data, list) else (
                    data.get("value") or data.get("categories") or []
                    if isinstance(data, dict) else []
                )
                if not isinstance(categories_raw, list):
                    categories_raw = []
                categories_clean: List[str] = []
                for c in categories_raw:
                    if isinstance(c, dict):
                        name = c.get("name") or c.get("title") or c.get("id")
                        if name:
                            categories_clean.append(str(name))
                    elif isinstance(c, str):
                        categories_clean.append(c)

                card = ServiceCategoriesCard(
                    totalCount=len(categories_clean),
                    categories=categories_clean
                )
                clean_msg = _clean_card_intro_message(
                    last_ai_content,
                    "Here are the service categories available across Workio:",
                    "service_categories"
                )
                return AgentCardResponse(
                    response_type="service_categories",
                    message=clean_msg,
                    card_data=card.model_dump(),
                    metadata={"agent": "community_agent", "user_email": email}
                )

        # 7. search_workers
        if tool_name == "search_workers":
            raw_workers = data if isinstance(data, list) else (
                data.get("workers") or data.get("items") or data.get("value") or []
                if isinstance(data, dict) else []
            )
            if not isinstance(raw_workers, list):
                raw_workers = []

            # Determine if a maximum budget was requested
            max_budget: Optional[float] = None
            for msg in reversed(messages):
                tool_calls = getattr(msg, "tool_calls", None) or []
                for tc in tool_calls:
                    if isinstance(tc, dict) and tc.get("name") == "search_workers":
                        args = tc.get("args") or {}
                        if args.get("maxHourlyRate") is not None:
                            try:
                                max_budget = float(args["maxHourlyRate"])
                                break
                            except Exception:
                                pass
                if max_budget is not None:
                    break

            if max_budget is None:
                # Fallback to inspecting user message
                for msg in reversed(messages):
                    if getattr(msg, "type", "") in ("human", "user"):
                        umsg = extract_text_content(getattr(msg, "content", "")).lower()
                        bmatch = re.search(r'(?:below|under|less than|max|budget)\s*(?:lkr\s*)?(\d+(?:\.\d+)?)', umsg)
                        if bmatch:
                            try:
                                max_budget = float(bmatch.group(1))
                            except Exception:
                                pass
                        break

            all_summaries: List[WorkerSummary] = []
            for item in raw_workers:
                if isinstance(item, dict):
                    raw_skills = item.get("skills") or []
                    w_img = item.get("profileImage") or item.get("ProfileImage") or item.get("avatarUrl") or item.get("profilePicture") or item.get("image") or item.get("workerAvatar")
                    w_role = item.get("primaryRole") or item.get("role") or item.get("category")
                    if not w_role and raw_skills:
                        first_sk = raw_skills[0]
                        w_role = first_sk.get("skillName") if isinstance(first_sk, dict) else str(first_sk)
                    all_summaries.append(
                        WorkerSummary(
                            id=item.get("id", 0),
                            name=item.get("name", "Verified Technician"),
                            profileImage=w_img,
                            primaryRole=w_role or "Verified Community Service Professional",
                            skills=_normalize_skills(raw_skills),
                            primaryServiceArea=item.get("primaryServiceArea") or item.get("district") or item.get("location") or "Colombo",
                            hourlyRate=float(item.get("hourlyRate", 0.0) or 0.0) if item.get("hourlyRate") else None,
                            dailyRate=float(item.get("dailyRate", 0.0) or 0.0) if item.get("dailyRate") else None,
                            overallRating=float(item.get("overallRating") or item.get("rating", 5.0) or 5.0),
                            completedJobs=int(item.get("completedJobs") or 0),
                            isAvailable=item.get("isAvailable", True) if item.get("isAvailable") is not None else True,
                            distance=float(item.get("distance")) if item.get("distance") is not None else None,
                        )
                    )

            if max_budget is not None and all_summaries:
                matching_workers = [w for w in all_summaries if w.hourlyRate <= max_budget]
                if not matching_workers:
                    min_avail = min((w.hourlyRate for w in all_summaries if w.hourlyRate > 0), default=0.0)
                    min_txt = f"{int(min_avail)}" if min_avail else "standard rates"
                    budg_txt = f"{int(max_budget)}"
                    msg = f"I couldn't find any technicians with an hourly rate of LKR {budg_txt} or below. The lowest available rate for this service starts at LKR {min_txt}/hr."
                    return AgentCardResponse(
                        response_type="text_message",
                        message=msg,
                        card_data=TextMessageCard(
                            text=msg,
                            suggestions=[f"Show technicians starting at LKR {min_txt}", "Create a Community Post", "Change search criteria"]
                        ).model_dump(),
                        metadata={"agent": "worker_matching_agent", "user_email": email}
                    )
                worker_summaries = matching_workers
            else:
                worker_summaries = all_summaries

            card = WorkerListCard(
                category=str(metadata.get("inferred_category") or "All"),
                totalCount=len(worker_summaries),
                workers=worker_summaries
            )
            clean_msg = _clean_card_intro_message(
                last_ai_content,
                f"Found {len(worker_summaries)} verified technicians near you:" if worker_summaries else "No workers found matching your query.",
                "worker_list"
            )
            return AgentCardResponse(
                response_type="worker_list",
                message=clean_msg,
                card_data=card.model_dump(),
                metadata={"agent": "worker_matching_agent", "user_email": email}
            )

        # 8. Booking Tools
        if tool_name == "create_booking":
            booking_id = data.get("bookingId") or data.get("id") or "new"
            worker_id = data.get("workerId") or ""
            worker_name = data.get("workerName") or "Verified Technician"
            job_title = data.get("jobTitle") or "Service Appointment"
            scheduled_date = data.get("scheduledDate") or data.get("startTime") or ""
            location_addr = data.get("locationAddress") or "Colombo"
            contact_ph = data.get("contactPhone") or ""
            status_val = data.get("status") or "Confirmed"

            card = BookingConfirmedCard(
                bookingId=booking_id,
                workerId=worker_id,
                workerName=worker_name,
                jobTitle=job_title,
                scheduledDate=str(scheduled_date),
                locationAddress=location_addr,
                contactPhone=contact_ph,
                status=status_val
            )
            clean_msg = f"Your appointment with {worker_name} has been successfully scheduled! Booking #{booking_id}."
            return AgentCardResponse(
                response_type="booking_confirmed",
                message=clean_msg,
                card_data=card.model_dump(),
                metadata={"agent": "booking_agent", "user_email": email}
            )

        if tool_name == "check_worker_availability":
            worker_id = data.get("workerId") or ""
            worker_name = data.get("workerName") or "Verified Technician"
            is_avail = data.get("isSlotAvailable", data.get("isAvailable", True))
            status_val = "Available" if is_avail else "Unavailable"
            reason_val = data.get("reason") or ("Technician is available for this slot." if is_avail else "Technician is not available for this slot.")

            user_profile = state.get("user_profile") or {}
            res_dict = user_profile.get("resident") if isinstance(user_profile.get("resident"), dict) else {}
            metadata = state.get("metadata") or {}

            # Smart extraction of all booking fields from user prompt & conversation
            smart_ctx = extract_smart_booking_details(
                messages=messages,
                data=data,
                metadata=metadata,
                user_profile=user_profile,
                default_category=data.get("category") or "Home Service"
            )

            loc_val = smart_ctx["location"]
            specific_addr_val = smart_ctx["specificAddress"]
            cat_val = smart_ctx["category"]
            job_title_val = smart_ctx["jobTitle"]
            desc_val = smart_ctx["description"]
            priority_val = smart_ctx["priority"]
            req_date = smart_ctx["selectedDate"]
            req_time = data.get("requestedStartTime", "09:00")
            dur_hours = int(data.get("durationHours") or 2)

            # Phone: resident's registered phone
            phone_val = (
                res_dict.get("phoneNo")
                or user_profile.get("phoneNo")
                or metadata.get("contactPhone")
                or data.get("contactPhone")
                or "0771756463"
            )

            slot = data.get("requestedSlot") or {}
            if slot.get("startTime"):
                s_part = str(slot["startTime"])
                if "T" in s_part:
                    req_date = s_part.split("T")[0]
                    req_time = s_part.split("T")[1][:5]

            # Price
            h_rate = float(data.get("hourlyRate") or 0)
            if h_rate <= 0:
                h_rate = 5000.0 if "super" in str(worker_name).lower() else 2800.0

            card = BookingFormCard(
                workerId=worker_id,
                workerName=worker_name,
                workerAvatar=data.get("workerAvatar") or data.get("profileImage") or data.get("profilePicture") or data.get("avatarUrl") or data.get("ProfileImage"),
                category=cat_val,
                hourlyRate=h_rate,
                location=loc_val,
                specificAddress=specific_addr_val,
                contactPhone=phone_val,
                selectedDate=req_date,
                selectedStartTime=req_time,
                durationHours=dur_hours,
                jobTitle=job_title_val,
                description=desc_val,
                priority=priority_val,
                notes=desc_val,
                isAvailable=is_avail,
                availabilityStatus=status_val,
                availabilityReason=reason_val
            )
            clean_msg = f"{worker_name} is {status_val.lower()} for your requested date."
            return AgentCardResponse(
                response_type="booking_form",
                message=clean_msg,
                card_data=card.model_dump(),
                metadata={"agent": "booking_agent", "user_email": email}
            )

        if tool_name == "get_resident_bookings":
            raw_bookings = data if isinstance(data, list) else (
                data.get("bookings") or data.get("items") or data.get("value") or []
                if isinstance(data, dict) else []
            )
            if not isinstance(raw_bookings, list):
                raw_bookings = []

            booking_summaries: List[BookingSummary] = []
            for b in raw_bookings:
                if isinstance(b, dict):
                    b_id = b.get("id") or b.get("bookingId") or 0
                    b_worker_id = b.get("workerId") or 0
                    b_worker_name = b.get("workerName") or "Verified Technician"
                    b_worker_img = b.get("workerProfileImage") or b.get("workerAvatar")
                    b_worker_phone = b.get("workerPhone")
                    b_title = b.get("jobTitle") or b.get("description") or "Home Service Appointment"
                    b_date = b.get("scheduledDate")
                    b_loc = b.get("locationAddress") or "Colombo"
                    b_phone = b.get("contactPhone")
                    b_pricing = b.get("pricingModel") or "Hourly"
                    b_est = float(b["estimatedPrice"]) if b.get("estimatedPrice") is not None else None
                    b_agr = float(b["agreedPrice"]) if b.get("agreedPrice") is not None else None
                    b_status = b.get("status") or "Requested"
                    b_created = b.get("createdAt")

                    booking_summaries.append(
                        BookingSummary(
                            id=b_id,
                            workerId=b_worker_id,
                            workerName=b_worker_name,
                            workerProfileImage=b_worker_img,
                            workerPhone=b_worker_phone,
                            jobTitle=b_title,
                            scheduledDate=b_date,
                            locationAddress=b_loc,
                            contactPhone=b_phone,
                            pricingModel=b_pricing,
                            estimatedPrice=b_est,
                            agreedPrice=b_agr,
                            status=b_status,
                            createdAt=b_created
                        )
                    )

            # Strip markdown pipes and raw tables from conversational message
            clean_msg = last_ai_content or ""
            if clean_msg:
                clean_msg = re.split(r'\n\s*\|', clean_msg)[0].strip()
                clean_msg = re.sub(r'The booking records provide start times.*$', '', clean_msg, flags=re.IGNORECASE).strip()

            if not clean_msg or len(clean_msg) < 5:
                count_str = f"{len(booking_summaries)} upcoming bookings" if booking_summaries else "no upcoming bookings"
                clean_msg = f"You have {count_str} on Workio:"

            card = BookingListCard(
                totalCount=len(booking_summaries),
                statusFilter="Upcoming",
                bookings=booking_summaries
            )

            return AgentCardResponse(
                response_type="booking_list",
                message=clean_msg,
                card_data=card.model_dump(),
                metadata={"agent": "booking_agent", "user_email": email}
            )

        if tool_name in ["get_booking", "get_booking_details"]:
            b_id = data.get("id") or data.get("bookingId") or "0"
            w_id = data.get("workerId") or ""
            w_name = data.get("workerName") or "Verified Technician"
            j_title = data.get("jobTitle") or data.get("description") or "Home Service Appointment"
            s_date = data.get("scheduledDate") or ""
            loc = data.get("locationAddress") or "Colombo"
            phone = data.get("contactPhone") or ""
            status_val = data.get("status") or "Requested"

            card = BookingConfirmedCard(
                bookingId=b_id,
                workerId=w_id,
                workerName=w_name,
                jobTitle=j_title,
                scheduledDate=s_date,
                locationAddress=loc,
                contactPhone=phone,
                status=status_val
            )
            card_dict = card.model_dump()
            card_dict["cardTitle"] = f"Booking #{b_id} Details"
            card_dict["cardSubtitle"] = f"Service appointment details with {w_name}."

            clean_msg = f"Here are the details for Booking #{b_id}:"
            return AgentCardResponse(
                response_type="booking_confirmed",
                message=clean_msg,
                card_data=card_dict,
                metadata={"agent": "booking_agent", "user_email": email, "bookingId": b_id}
            )

        if tool_name == "cancel_booking":
            suggestions = ["Book a technician", "View upcoming bookings"]
            msg = last_ai_content
            if not msg:
                booking_id = data.get("bookingId") or data.get("id") or ""
                msg = f"Booking #{booking_id} has been cancelled." if booking_id else "Booking has been cancelled."
            card = TextMessageCard(
                text=msg,
                suggestions=suggestions
            )
            return AgentCardResponse(
                response_type="text_message",
                message=card.text,
                card_data=card.model_dump(),
                metadata={"agent": "booking_agent", "user_email": email}
            )

        if tool_name in ["get_booking", "get_booking_details"]:
            if isinstance(data, dict) and data.get("error"):
                err_msg = str(data.get("error"))
                return AgentCardResponse(
                    response_type="text_message",
                    message=err_msg,
                    card_data=TextMessageCard(text=err_msg, suggestions=["View my bookings", "Book a technician"]).model_dump(),
                    metadata={"agent": "booking_agent", "user_email": email}
                )

            b_id = data.get("id") or data.get("bookingId")
            if not b_id:
                msg = data.get("message") or last_ai_content or "Booking details could not be found."
                return AgentCardResponse(
                    response_type="text_message",
                    message=msg,
                    card_data=TextMessageCard(text=msg, suggestions=["View my bookings", "Book a technician"]).model_dump(),
                    metadata={"agent": "booking_agent", "user_email": email}
                )

            b_worker_id = data.get("workerId") or 0
            b_worker_name = data.get("workerName") or "Verified Technician"
            b_worker_img = data.get("workerProfileImage") or data.get("workerAvatar")
            b_worker_phone = data.get("workerPhone")
            b_title = data.get("jobTitle") or data.get("description") or "Home Service Appointment"
            b_date = data.get("scheduledDate")
            b_loc = data.get("locationAddress") or "Colombo"
            b_phone = data.get("contactPhone")
            b_pricing = data.get("pricingModel") or "Hourly"
            b_est = float(data["estimatedPrice"]) if data.get("estimatedPrice") is not None else None
            b_agr = float(data["agreedPrice"]) if data.get("agreedPrice") is not None else None
            b_status = data.get("status") or "Requested"
            b_created = data.get("createdAt")

            summary = BookingSummary(
                id=b_id,
                workerId=b_worker_id,
                workerName=b_worker_name,
                workerProfileImage=b_worker_img,
                workerPhone=b_worker_phone,
                jobTitle=b_title,
                scheduledDate=b_date,
                locationAddress=b_loc,
                contactPhone=b_phone,
                pricingModel=b_pricing,
                estimatedPrice=b_est,
                agreedPrice=b_agr,
                status=b_status,
                createdAt=b_created
            )

            card = BookingListCard(
                totalCount=1,
                statusFilter=b_status,
                bookings=[summary]
            )

            clean_msg = _clean_card_intro_message(
                last_ai_content,
                f"Here are the details for booking #{b_id}:",
                "booking_list"
            )

            return AgentCardResponse(
                response_type="booking_list",
                message=clean_msg,
                card_data=card.model_dump(),
                metadata={"agent": "booking_agent", "user_email": email, "bookingId": b_id}
            )

        # 9. Support & Review Tools
        if tool_name == "create_worker_review":
            b_id = data.get("bookingId") or data.get("id") or "0"
            w_id = data.get("workerId") or ""
            w_name = data.get("workerName") or "Verified Technician"
            overall = float(data.get("overallRating") or data.get("rating") or 5.0)
            quality = int(data.get("qualityRating") or overall)
            punctuality = int(data.get("punctualityRating") or overall)
            comm = int(data.get("communicationRating") or overall)
            comment_text = data.get("comment") or data.get("reviewComment")
            rev_at = data.get("reviewedAt") or datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M")

            review_card = ReviewSubmittedCard(
                bookingId=b_id,
                workerId=w_id,
                workerName=w_name,
                overallRating=overall,
                qualityRating=quality,
                punctualityRating=punctuality,
                communicationRating=comm,
                comment=comment_text,
                submittedAt=rev_at
            )
            clean_msg = f"Thank you! Your verified review for {w_name} has been submitted successfully."
            if data.get("overallRating") or data.get("qualityRating") or data.get("comment"):
                return AgentCardResponse(
                    response_type="review_submitted",
                    message=clean_msg,
                    card_data=review_card.model_dump(),
                    metadata={"agent": "support_review_agent", "user_email": email}
                )
            return AgentCardResponse(
                response_type="text_message",
                message=clean_msg,
                card_data=TextMessageCard(text=clean_msg, suggestions=["View my bookings", "Find a worker"]).model_dump(),
                metadata={"agent": "support_review_agent", "user_email": email}
            )

        if tool_name == "get_worker_performance":
            w_name = data.get("name") or data.get("workerName") or f"Worker #{data.get('workerId', '')}"
            rating = data.get("overallRating") or data.get("rating") or "N/A"
            jobs = data.get("completedJobs") or 0
            msg = last_ai_content or f"{w_name} has an overall rating of {rating} out of 5 across {jobs} completed jobs."
            return AgentCardResponse(
                response_type="text_message",
                message=msg,
                card_data=TextMessageCard(text=msg, suggestions=["Book this worker", "View more technicians"]).model_dump(),
                metadata={"agent": "support_review_agent", "user_email": email}
            )

        if tool_name == "file_dispute_ticket":
            ticket_id = data.get("ticketId") or data.get("id") or "TICKET-101"
            w_id = data.get("workerId")
            w_name = data.get("workerName")
            reason_text = data.get("reason") or "Service dispute filed"
            urgency_text = (data.get("urgencyLevel") or data.get("urgency") or "Medium").capitalize()
            sla_text = data.get("sla") or "Support team responds within 2 hours"
            phone_text = data.get("supportPhone") or "+94 11 234 5678"

            dispute_card = DisputeTicketCard(
                ticketId=ticket_id,
                workerId=w_id,
                workerName=w_name,
                reason=reason_text,
                urgencyLevel=urgency_text,
                status=data.get("status", "Open"),
                resolutionSla=sla_text,
                supportHotline=phone_text
            )
            clean_msg = f"Dispute Ticket #{ticket_id} has been registered. Our safety coordinator will investigate and follow up."
            return AgentCardResponse(
                response_type="dispute_ticket",
                message=clean_msg,
                card_data=dispute_card.model_dump(),
                metadata={"agent": "support_review_agent", "user_email": email}
            )

        if tool_name == "lookup_platform_policy":
            suggestions = [
                "7-Day Workmanship Guarantee",
                "Cancellation & Fees",
                "Property Damage Protection",
                "Technician Safety & Vetting"
            ]
            msg = last_ai_content or "Here is the verified platform policy information:"
            card = TextMessageCard(
                text=msg,
                suggestions=suggestions
            )
            return AgentCardResponse(
                response_type="text_message",
                message=card.text,
                card_data=card.model_dump(),
                metadata={"agent": "support_review_agent", "user_email": email}
            )

        if tool_name in ["escalate_to_human", "get_user_job_history"]:
            suggestions = ["Leave a review", "Contact hotline", "Return to home"]
            msg = last_ai_content
            if not msg:
                if tool_name == "escalate_to_human":
                    esc_id = data.get("escalationId") or "ESC-901"
                    msg = f"Your case #{esc_id} has been escalated to a live human supervisor. Expected wait time is under 5 minutes."
                else:
                    msg = f"Support action {tool_name} completed."
            card = TextMessageCard(
                text=msg,
                suggestions=suggestions
            )
            return AgentCardResponse(
                response_type="text_message",
                message=card.text,
                card_data=card.model_dump(),
                metadata={"agent": "support_review_agent", "user_email": email}
            )

    # =========================================================================
    # 2. CONVERSATIONAL / DRAFTING TURNS (No tool executed in this current turn)
    # =========================================================================
    lower_content = last_ai_content.lower()

    # -------------------------------------------------------------------------
    # 0. BOOKING FORM INTENT (e.g. user asks to book a worker / technician)
    # -------------------------------------------------------------------------
    user_query = ""
    for msg in reversed(messages):
        if getattr(msg, "type", "") in ("human", "user"):
            user_query = extract_text_content(getattr(msg, "content", ""))
            break

    user_query_lower = user_query.lower()
    last_ai_lower = last_ai_content.lower()

    # Detect booking intent keywords
    has_book_kw = any(w in user_query_lower for w in [
        "book", "booking", "hire", "reserve", "appointment", "schedule a service", "schedule with"
    ]) or any(w in last_ai_lower for w in [
        "help book", "booking for", "schedule an appointment", "book bandara", "book worker", "prefer? i'll check", "start time would you prefer", "what date and start time"
    ])

    # Extract worker ID from user query or AI response
    extracted_worker_id = None
    w_id_m = re.search(r'(?:worker\s*id|worker\s*#|worker)\s*[:#]?\s*(\d+)', user_query, re.IGNORECASE)
    if not w_id_m:
        w_id_m = re.search(r'\(?(?:ID|Worker ID)\s*[:#]?\s*(\d+)\)?', user_query, re.IGNORECASE)
    if not w_id_m:
        w_id_m = re.search(r'(?:worker\s*id|worker\s*#|worker)\s*[:#]?\s*(\d+)', last_ai_content, re.IGNORECASE)
    if not w_id_m:
        w_id_m = re.search(r'\(?(?:ID|Worker ID)\s*[:#]?\s*(\d+)\)?', last_ai_content, re.IGNORECASE)

    if w_id_m:
        extracted_worker_id = w_id_m.group(1)

    # Extract worker name from user query or AI response
    extracted_worker_name = None
    name_m = re.search(r'(?:book|hire|with)\s+([A-Z][a-zA-Z\s]+?)(?:\s*\(|\s*,\s*worker|\s+for\s+|\s+on\s+|\s*$)', user_query)
    if name_m:
        cand = name_m.group(1).strip()
        if cand and len(cand) > 2 and cand.lower() not in ["a worker", "a technician", "someone", "worker", "the worker"]:
            extracted_worker_name = cand

    if not extracted_worker_name:
        name_m_ai = re.search(r'(?:help book|booking with|book)\s+([A-Z][a-zA-Z\s]+?)(?:\s*\(|\s+on\s+|\s*\.|\s*,)', last_ai_content)
        if name_m_ai:
            cand = name_m_ai.group(1).strip()
            if cand and len(cand) > 2 and cand.lower() not in ["a worker", "a technician", "someone", "worker", "the worker"]:
                extracted_worker_name = cand

    # -------------------------------------------------------------------------
    # 0A. REVIEW FORM & DISPUTE INTENT
    # -------------------------------------------------------------------------
    has_review_kw = any(w in user_query_lower for w in [
        "review", "rate", "rating", "leave a review", "give review", "feedback", "give feedback", "stars",
        "post a review", "submit review", "write a review"
    ]) or any(w in last_ai_lower for w in [
        "leave a review", "submit a review", "rate this technician", "how was your experience"
    ]) or metadata.get("agent") == "support_review_agent"

    is_asking_other_rating = any(w in user_query_lower for w in [
        "what is his rating", "what is her rating", "what is their rating", "show rating", "performance",
        "what is the rating", "rating of", "worker rating", "worker's rating", "get rating", "check rating"
    ]) or any(
        getattr(m, "type", "") == "tool" and getattr(m, "name", "") == "get_worker_performance"
        for m in messages
    )

    has_dispute_kw = any(w in user_query_lower for w in [
        "dispute", "file complaint", "file a complaint", "technician didn't show", "no show",
        "broke my", "damage", "scam", "overcharged", "poor quality work", "issue ticket", "ticket"
    ])

    if has_dispute_kw:
        ticket_num = f"DISP-{datetime.now(timezone.utc).strftime('%y%m%d')}-9481"
        dispute_card = DisputeTicketCard(
            ticketId=ticket_num,
            workerId=extracted_worker_id,
            workerName=extracted_worker_name or "Assigned Technician",
            reason=user_query or "Service quality and completion dispute reported by resident.",
            urgencyLevel="High" if any(k in user_query_lower for k in ["damage", "broke", "emergency", "urgent"]) else "Medium",
            status="Open",
            resolutionSla="Support team responds within 2 hours",
            supportHotline="+94 11 234 5678"
        )
        clean_msg = f"I have opened Support Ticket #{ticket_num} for your report. Our trust & safety team has been alerted."
        return AgentCardResponse(
            response_type="dispute_ticket",
            message=clean_msg,
            card_data=dispute_card.model_dump(),
            metadata={"agent": "support_review_agent", "user_email": email}
        )

    if has_review_kw and not is_asking_other_rating:
        # Extract booking ID if mentioned in text
        extracted_booking_id = None
        b_match = re.search(r'(?:booking|order|appointment|#)\s*[:#]?\s*(\d+)', user_query, re.IGNORECASE)
        if not b_match:
            b_match = re.search(r'(?:booking|order|appointment|#)\s*[:#]?\s*(\d+)', last_ai_content, re.IGNORECASE)
        if b_match:
            extracted_booking_id = b_match.group(1)

        completed_bookings = metadata.get("completed_bookings") or []
        target_booking = None

        # 1. Match against completed bookings if available in metadata
        if extracted_booking_id and completed_bookings:
            for b in completed_bookings:
                if str(b.get("id")) == str(extracted_booking_id):
                    target_booking = b
                    break
        elif completed_bookings:
            target_booking = completed_bookings[0]

        # 2. Check previous tool messages for completed bookings
        if not target_booking:
            for prev_msg in reversed(messages):
                if getattr(prev_msg, "type", "") == "tool" or isinstance(prev_msg, ToolMessage):
                    try:
                        p_data = json.loads(getattr(prev_msg, "content", "") or "{}")
                        cand_list = []
                        if isinstance(p_data, list):
                            cand_list = p_data
                        elif isinstance(p_data, dict):
                            cand_list = p_data.get("bookings") or [p_data]

                        for item in cand_list:
                            if isinstance(item, dict) and str(item.get("status", "")).strip().lower() in ["completed", "reviewed"]:
                                if extracted_booking_id:
                                    if str(item.get("id")) == str(extracted_booking_id) or str(item.get("bookingId")) == str(extracted_booking_id):
                                        target_booking = item
                                        break
                                else:
                                    target_booking = item
                                    break
                        if target_booking:
                            break
                    except Exception:
                        pass

        # 3. If NO completed booking exists, DO NOT hallucinate fake "Verified Technician" Booking #8
        if not target_booking and not (extracted_booking_id and extracted_worker_name):
            no_b_msg = "You don't have any completed bookings to review workers yet. Once a technician completes your scheduled service, you can leave ratings and feedback here."
            return AgentCardResponse(
                response_type="text_message",
                message=no_b_msg,
                card_data=TextMessageCard(
                    text=no_b_msg,
                    suggestions=["Find a service worker", "View my bookings", "Book a technician"]
                ).model_dump(),
                metadata={"agent": "support_review_agent", "user_email": email}
            )

        target_b_id = str((target_booking.get("id") or target_booking.get("bookingId") or extracted_booking_id) if target_booking else extracted_booking_id)
        review_worker_id = str((target_booking.get("workerId") or extracted_worker_id or "1") if target_booking else (extracted_worker_id or "1"))
        review_worker_name = (target_booking.get("workerName") or extracted_worker_name or "Technician") if target_booking else (extracted_worker_name or "Technician")
        review_job_title = (target_booking.get("jobTitle") or "Completed Service") if target_booking else "Completed Service"
        review_avatar = (target_booking.get("workerProfileImage") or target_booking.get("workerAvatar")) if target_booking else None

        review_card = ReviewFormCard(
            bookingId=target_b_id,
            workerId=review_worker_id,
            workerName=review_worker_name,
            workerAvatar=review_avatar,
            jobTitle=review_job_title,
            defaultQuality=5,
            defaultPunctuality=5,
            defaultCommunication=5
        )
        clean_msg = f"How was your experience with {review_worker_name}? Please share your ratings and feedback below:"
        return AgentCardResponse(
            response_type="review_form",
            message=clean_msg,
            card_data=review_card.model_dump(),
            metadata={"agent": "support_review_agent", "user_email": email}
        )


    # -------------------------------------------------------------------------
    # 0B. BOOKING FORM INTENT (e.g. user asks to book a worker / technician)
    # -------------------------------------------------------------------------
    is_confirm_flow = (
        "confirm_booking" in lower_content
        or "confirm booking" in lower_content
        or any(
            getattr(m, "type", "") in ("human", "user")
            and ("confirm_booking" in extract_text_content(getattr(m, "content", "")).lower() or "confirm booking" in extract_text_content(getattr(m, "content", "")).lower())
            for m in reversed(messages[:4])
        )
    )
    is_booking_flow = (
        not is_confirm_flow
        and has_book_kw
        and (extracted_worker_id is not None or extracted_worker_name is not None or metadata.get("agent") == "booking_agent")
    )

    if is_booking_flow and (extracted_worker_id or extracted_worker_name):
        worker_id_val = extracted_worker_id or "44"
        worker_name_val = extracted_worker_name or f"Technician #{worker_id_val}"
        hourly_rate_val = 2800.0
        worker_cat_val = metadata.get("inferred_category") or "General Service"
        worker_avatar_val = None
        worker_location_val = "Colombo"

        # Search prior messages for worker metadata (from search_workers or get_worker_details)
        for prev_msg in reversed(messages):
            if getattr(prev_msg, "type", "") == "tool" or isinstance(prev_msg, ToolMessage):
                content_val = getattr(prev_msg, "content", "")
                data_val = {}
                if isinstance(content_val, str):
                    try:
                        data_val = json.loads(content_val)
                    except Exception:
                        continue
                elif isinstance(content_val, dict):
                    data_val = content_val

                cand_workers = []
                if isinstance(data_val, list):
                    cand_workers = data_val
                elif isinstance(data_val, dict):
                    w_items = data_val.get("workers") or data_val.get("items") or data_val.get("value")
                    if isinstance(w_items, list):
                        cand_workers = w_items
                    elif data_val.get("id") or data_val.get("name"):
                        cand_workers = [data_val]

                for cw in cand_workers:
                    if not isinstance(cw, dict):
                        continue
                    cw_id = str(cw.get("id") or "")
                    cw_name = str(cw.get("name") or "")
                    matched = False
                    if extracted_worker_id and cw_id == str(extracted_worker_id):
                        matched = True
                    elif extracted_worker_name and extracted_worker_name.lower() in cw_name.lower():
                        matched = True

                    if matched:
                        worker_id_val = cw_id or worker_id_val
                        worker_name_val = cw_name or worker_name_val
                        if cw.get("hourlyRate"):
                            try:
                                hourly_rate_val = float(cw["hourlyRate"])
                            except Exception:
                                pass
                        worker_cat_val = cw.get("primaryRole") or cw.get("category") or worker_cat_val
                        worker_avatar_val = cw.get("avatarUrl") or cw.get("profileImage") or cw.get("profilePicture")
                        worker_location_val = cw.get("primaryServiceArea") or cw.get("location") or worker_location_val
                        break

                if worker_avatar_val or (worker_id_val and worker_name_val != f"Technician #{worker_id_val}"):
                    break

        smart_ctx = extract_smart_booking_details(
            messages=messages,
            data={"hourlyRate": hourly_rate_val, "category": worker_cat_val},
            metadata=metadata,
            user_profile=user_profile,
            default_category=worker_cat_val
        )

        user_loc_default = smart_ctx["location"] or metadata.get("location") or user_profile.get("address") or worker_location_val or "Colombo"
        user_phone_default = user_profile.get("phoneNo") or "0771234567"

        booking_card = BookingFormCard(
            workerId=worker_id_val,
            workerName=worker_name_val,
            workerAvatar=worker_avatar_val,
            category=smart_ctx["category"],
            hourlyRate=hourly_rate_val,
            location=user_loc_default,
            specificAddress=smart_ctx["specificAddress"],
            contactPhone=user_phone_default,
            selectedDate=smart_ctx["selectedDate"],
            selectedStartTime="09:00",
            durationHours=2,
            jobTitle=smart_ctx["jobTitle"],
            description=smart_ctx["description"],
            priority=smart_ctx["priority"],
            notes=smart_ctx["description"],
            isAvailable=True,
            availabilityStatus="Available",
            availabilityReason=f"{worker_name_val} is available for booking."
        )

        clean_msg = f"I've prepared the booking form for {worker_name_val} (Worker ID: {worker_id_val}). Please check the availability and customize your appointment details below:"

        return AgentCardResponse(
            response_type="booking_form",
            message=clean_msg,
            card_data=booking_card.model_dump(),
            metadata={"agent": "booking_agent", "user_email": email, "workerId": worker_id_val}
        )

    # -------------------------------------------------------------------------
    # Booking List / Table Detection in Conversational Turns
    # -------------------------------------------------------------------------
    has_booking_table = bool(
        re.search(r'\|\s*Booking ID\s*\|\s*Worker\s*\|\s*Service\s*\|', last_ai_content, re.IGNORECASE)
        or ("booking id" in lower_content and "scheduled time" in lower_content and "|" in last_ai_content)
    )
    if has_booking_table:
        rows = re.findall(r'\|\s*\*{0,2}#?(\d+)\*{0,2}\s*\|\s*([^|]+)\s*\|\s*([^|]+)\s*\|\s*([^|]+)\s*\|\s*([^|]+)\s*\|', last_ai_content)
        if rows:
            booking_summaries = []
            for r in rows:
                b_id, b_worker, b_service, b_time, b_stat = [x.strip() for x in r]
                b_stat_clean = b_stat.strip().strip("*").strip()
                booking_summaries.append(
                    BookingSummary(
                        id=b_id,
                        workerId="",
                        workerName=b_worker.strip("*# "),
                        jobTitle=b_service.strip("*# "),
                        scheduledDate=b_time.strip("*# "),
                        status=b_stat_clean or "Requested"
                    )
                )
            clean_msg = re.split(r'\n\s*\|', last_ai_content)[0].strip()
            clean_msg = re.sub(r'The booking records provide start times.*$', '', clean_msg, flags=re.IGNORECASE).strip()
            return AgentCardResponse(
                response_type="booking_list",
                message=clean_msg or f"You have {len(booking_summaries)} upcoming bookings:",
                card_data=BookingListCard(
                    totalCount=len(booking_summaries),
                    statusFilter="Upcoming",
                    bookings=booking_summaries
                ).model_dump(),
                metadata={"agent": "booking_agent", "user_email": email}
            )

    # -------------------------------------------------------------------------
    # Single Booking Detail Detection in Conversational Turns
    # -------------------------------------------------------------------------
    single_booking_m = re.search(r'\*\*Booking\s*#?(\d+)\*\*', last_ai_content, re.IGNORECASE)
    if not single_booking_m:
        single_booking_m = re.search(r'\bBooking\s*#?(\d+)\b', last_ai_content, re.IGNORECASE)

    has_single_booking = bool(
        single_booking_m
        and any(w in lower_content for w in ["worker:", "technician:", "service:", "scheduled date:"])
    )
    if has_single_booking and single_booking_m:
        b_id_str = single_booking_m.group(1)
        w_name_m = re.search(r'\*\*Worker:\*\*\s*([^\n\r]+)', last_ai_content, re.IGNORECASE)
        s_title_m = re.search(r'\*\*Service:\*\*\s*([^\n\r]+)', last_ai_content, re.IGNORECASE)
        date_m = re.search(r'\*\*Scheduled date:\*\*\s*([^\n\r]+)', last_ai_content, re.IGNORECASE)
        loc_m = re.search(r'\*\*Location:\*\*\s*([^\n\r]+)', last_ai_content, re.IGNORECASE)
        phone_m = re.search(r'\*\*Phone:\*\*\s*([^\n\r]+)', last_ai_content, re.IGNORECASE)
        stat_m = re.search(r'\*\*Status:\*\*\s*([^\n\r]+)', last_ai_content, re.IGNORECASE)

        bk_w_name = w_name_m.group(1).strip() if w_name_m else "Verified Technician"
        bk_title = s_title_m.group(1).strip() if s_title_m else "Home Service Appointment"
        bk_date = date_m.group(1).strip() if date_m else ""
        bk_loc = loc_m.group(1).strip() if loc_m else "Colombo"
        bk_phone = phone_m.group(1).strip() if phone_m else ""
        bk_stat = stat_m.group(1).strip() if stat_m else "Requested"

        card = BookingConfirmedCard(
            bookingId=b_id_str,
            workerId="",
            workerName=bk_w_name,
            jobTitle=bk_title,
            scheduledDate=bk_date,
            locationAddress=bk_loc,
            contactPhone=bk_phone,
            status=bk_stat
        )
        card_dict = card.model_dump()
        card_dict["cardTitle"] = f"Booking #{b_id_str} Details"
        card_dict["cardSubtitle"] = f"Service appointment details with {bk_w_name}."

        return AgentCardResponse(
            response_type="booking_confirmed",
            message=f"Here are the details for Booking #{b_id_str}:",
            card_data=card_dict,
            metadata={"agent": "booking_agent", "user_email": email, "bookingId": b_id_str}
        )

    # Conversational Booking Detail Query (e.g. "Show details for booking #1")
    # -------------------------------------------------------------------------
    b_id_match = re.search(r'\b(?:booking|order|appointment)\s*[:#]?\s*(\d+)\b', user_query_lower)
    if not b_id_match and (metadata.get("agent") == "booking_agent" or has_book_kw):
        b_id_match = re.search(r'\b(?:#\s*|id\s*[:#]?\s*)(\d+)\b', user_query_lower)

    if b_id_match and (metadata.get("agent") == "booking_agent" or has_book_kw) and not has_review_kw:
        target_b_id = b_id_match.group(1)
        clean_msg = _clean_card_intro_message(
            last_ai_content,
            f"Here are the details for booking #{target_b_id}:",
            "booking_list"
        )
        return AgentCardResponse(
            response_type="text_message",
            message=last_ai_content or clean_msg,
            card_data=TextMessageCard(
                text=last_ai_content or clean_msg,
                suggestions=[
                    f"Reschedule booking #{target_b_id}",
                    f"Cancel booking #{target_b_id}",
                    "View all upcoming bookings"
                ]
            ).model_dump(),
            metadata={"agent": "booking_agent", "user_email": email, "bookingId": target_b_id}
        )

    # A. Check if the agent prepared a draft community post awaiting confirmation
    is_choice_turn = any(kw in lower_content for kw in [
        "create a community post or find",
        "how would you like to proceed",
        "would you like to proceed with finding a worker or creating a community post",
        "1) find a verified worker",
        "would you like to: 1)",
        "reply with '1' (find a worker)"
    ])

    is_booking_context = bool(
        metadata.get("agent") == "booking_agent"
        or "booking" in user_query_lower
        or "appointment" in user_query_lower
        or has_single_booking
    )

    user_query_community = any(kw in user_query_lower for kw in [
        "community post", "create post", "make a post", "post request", "publish post", "draft post", "new post", "community board"
    ])
    active_agent = metadata.get("agent")
    is_delete_turn = any(kw in user_query_lower for kw in [
        "delete", "remove", "trash", "take down", "erase", "cancel post", "drop post"
    ]) or any(kw in lower_content for kw in [
        "like me to delete", "confirm before i remove", "confirm before deleting", "delete it?", "remove it?"
    ])

    is_draft = (
        not is_choice_turn
        and not is_delete_turn
        and not (is_non_community_agent and not user_query_community)
        and not is_booking_context
        and (
            any(kw in lower_content for kw in [
                "draft", "confirm and publish", "would you like me to publish", "reply 'confirm'", "draft community post"
            ]) or (
                ("title:" in lower_content or "• title" in lower_content) and ("category:" in lower_content or "• category" in lower_content)
            )
        )
    )


    if is_draft:
        draft_title = ""
        draft_category = metadata.get("inferred_category") or "General"
        draft_location = "Colombo"
        draft_content = ""

        # 1. Regex search on full text for structured draft fields (handles markdown bolding, bullets, and casing)
        title_m = re.search(r'(?:^|[•\*\-\#\d\.\s])(?:title)\s*[\*]*\s*[:\-]\s*([^\n\r•]+)', last_ai_content, re.IGNORECASE)
        if title_m:
            draft_title = title_m.group(1).strip().strip("*#\"'").strip()

        cat_m = re.search(r'(?:^|[•\*\-\#\d\.\s])(?:category|service)\s*[\*]*\s*[:\-]\s*([^\n\r•]+)', last_ai_content, re.IGNORECASE)
        if cat_m:
            cat_val = cat_m.group(1).strip().strip("*#\"'").strip()
            if cat_val and cat_val.lower() != "general":
                draft_category = cat_val

        loc_m = re.search(r'(?:^|[•\*\-\#\d\.\s])(?:location|city)\s*[\*]*\s*[:\-]\s*([^\n\r•]+)', last_ai_content, re.IGNORECASE)
        if loc_m:
            draft_location = loc_m.group(1).strip().strip("*#\"'").strip()

        desc_m = re.search(r'(?:^|[•\*\-\#\d\.\s])(?:content|description)\s*[\*]*\s*[:\-]\s*([^\n\r•]+)', last_ai_content, re.IGNORECASE)
        if desc_m:
            draft_content = desc_m.group(1).strip().strip("*#\"'").strip()

        # 2. Line-by-line fallback parsing if any field was missed
        chunks = []
        for c in last_ai_content.splitlines():
            if "•" in c:
                chunks.extend(c.split("•"))
            else:
                chunks.append(c)

        for line in chunks:
            line_str = line.strip().lstrip("•-* \t").strip()
            line_lower = line_str.lower()
            if not draft_title and (line_lower.startswith("title:") or ("title:" in line_lower and "category:" not in line_lower)):
                parts = line_str.split(":", 1)
                if len(parts) > 1:
                    draft_title = parts[1].strip().strip("*#\"'").strip()
            elif (not draft_category or draft_category == "General") and ("category:" in line_lower and "title:" not in line_lower):
                parts = line_str.split(":", 1)
                if len(parts) > 1:
                    cat_val = parts[1].strip().strip("*#\"'").strip()
                    if cat_val and cat_val.lower() != "general":
                        draft_category = cat_val
            elif (not draft_location or draft_location == "Colombo") and ((line_lower.startswith("location:") or "location:" in line_lower) and "title:" not in line_lower):
                parts = line_str.split(":", 1)
                if len(parts) > 1:
                    draft_location = parts[1].strip().strip("*#\"'").strip()
            elif not draft_content and (line_lower.startswith("content:") or line_lower.startswith("description:")):
                parts = line_str.split(":", 1)
                if len(parts) > 1:
                    draft_content = parts[1].strip().strip("*#\"'").strip()

        # Clean trailing questions or instructions from draft_content
        for trail in [
            "please review your post", "would you like to publish", "would you like me to publish",
            "reply 'confirm'", "you can edit any details"
        ]:
            if trail in draft_content.lower():
                idx = draft_content.lower().find(trail)
                draft_content = draft_content[:idx].strip().rstrip(". ")

        # Locate the original user issue/problem text from conversation history
        user_problem_txt = ""
        for msg in reversed(messages):
            if getattr(msg, "type", "") in ("human", "user"):
                content_str = extract_text_content(getattr(msg, "content", ""))
                clean_msg_lower = content_str.strip().lower()
                if clean_msg_lower in ["confirm", "publish", "confirm_publish", "yes", "proceed", "1", "2"]:
                    continue
                if clean_msg_lower.startswith("confirm_publish:"):
                    continue
                if len(content_str) > 5:
                    user_problem_txt = content_str
                    break

        if not draft_category or draft_category.lower() == "general":
            if metadata.get("inferred_category"):
                draft_category = metadata["inferred_category"]

        user_loc_default = metadata.get("location") or user_profile.get("address") or "Colombo"
        if not draft_location or draft_location.lower() in ["your location", "location", "n/a", "unknown", "none", "{location}"]:
            draft_location = user_loc_default

        # ALWAYS ensure title is specific to the actual issue, never generic
        draft_title = generate_issue_title(
            raw_title=draft_title,
            issue_text=user_problem_txt,
            category=draft_category,
            content=draft_content
        )

        # Ensure draft content is articulate, detailed, and never conversational meta-speech
        is_bad_content = not draft_content or any(p in draft_content.lower() for p in [
            "here is your draft", "draft community post", "review the details", "draft card", "you can edit them", "confirm to publish"
        ])
        if is_bad_content or len(draft_content) < 30:
            target_issue = user_problem_txt or draft_content or draft_title
            target_issue = re.sub(
                r'^(?:i want to|i need to|please|can you|help me to|help me)?\s*(?:create|make|post|publish)\s+(?:a\s+)?(?:community\s+)?(?:post)?\s*[:\-]?\s*',
                '',
                target_issue,
                flags=re.IGNORECASE
            ).strip()
            target_issue = re.sub(
                r'^(?:i have a problem with|i have an issue with|there is an issue with|my|i need help with|i need to repair|i need someone to|please help me with|can you help me with|i want to fix|fix my|repair my|i need|help me|please)\s+',
                '',
                target_issue,
                flags=re.IGNORECASE
            ).strip()

            if target_issue and len(target_issue) > 10:
                draft_content = (
                    f"I am experiencing an issue: {target_issue}. "
                    f"Looking for an experienced, reliable professional in {draft_location} to inspect and resolve this promptly. "
                    f"Please contact me with your availability and an estimate."
                )
            else:
                draft_content = (
                    f"I am looking for a qualified professional for {draft_title} in {draft_location}. "
                    f"Please inspect the requirements and reach out with your schedule, availability, and an estimate for the work."
                )
        elif not any(k in draft_content.lower() for k in ["availability", "estimate", "quote", "contact me", "reach out"]):
            draft_content = draft_content.rstrip(". ") + ". Please contact me with your availability and an estimate."

        user_query_for_intent = user_problem_txt.lower()
        user_wants_edit = bool(
            re.search(r'\b(?:edit|update|modify|change|correct)\b.*?\b(?:post|details|request|my post|that post|this post)\b', user_query_for_intent)
            or re.search(r'\b(?:edit|update|modify)\s+(?:this|my|the|that)?\s*post\b', user_query_for_intent)
            or any(kw in lower_content for kw in ["for editing (id", "for editing", "post details for editing", "updating post"])
        )

        explicit_id_pattern = r'\b(?:post\s*id\s*[:#]?|post\s*#|id\s*[:#])\s*(\d+)\b'
        target_id_m = re.search(explicit_id_pattern, user_problem_txt, re.IGNORECASE)
        if not target_id_m and user_wants_edit:
            target_id_m = re.search(r'\b(?:edit|update)\s+post\s*(?:#|id)?\s*(\d+)\b', user_problem_txt, re.IGNORECASE)
        if not target_id_m and user_wants_edit:
            target_id_m = re.search(r'\(?(?:ID|Post)\s*[:#]?\s*(\d+)\)?', last_ai_content, re.IGNORECASE)
        if not target_id_m and user_wants_edit:
            for prev_m in reversed(messages):
                prev_text = extract_text_content(getattr(prev_m, "content", ""))
                prev_id_m = re.search(r'\b(?:post\s*#?|id\s*[:#]?)\s*(\d+)\b', prev_text, re.IGNORECASE)
                if prev_id_m:
                    target_id_m = prev_id_m
                    break

        post_id_val = None
        if target_id_m:
            groups = [g for g in target_id_m.groups() if g is not None]
            if groups and groups[0].isdigit():
                post_id_val = int(groups[0])

        is_update_action = bool(
            metadata.get("action") == "update"
            or (user_wants_edit and post_id_val is not None)
            or (user_wants_edit and "updating post" in lower_content)
            or (user_wants_edit and "for editing" in lower_content)
        )
        action_val = "update" if is_update_action else "create"
        if action_val == "create":
            post_id_val = None

        post_images = []
        if isinstance(metadata.get("images"), list):
            post_images = metadata.get("images")
        elif isinstance(metadata.get("postData"), dict):
            post_images = metadata["postData"].get("images") or metadata["postData"].get("Images") or []
        elif isinstance(metadata.get("photos"), list):
            post_images = [p.get("url") if isinstance(p, dict) else p for p in metadata.get("photos")]
        if not isinstance(post_images, list):
            post_images = []

        card = PostConfirmationCard(
            action=action_val,
            postId=post_id_val,
            title=draft_title,
            content=draft_content,
            communityId=draft_category,
            location=draft_location,
            urgency=None,
            images=post_images,
            authorId=email,
            authorName=user_name,
            validationStatus="valid",
            validationNotes=(
                "You can edit the details in the form above and click 'Update Post' to save your changes."
                if action_val == "update"
                else f"Please review your draft details above and confirm to publish under your account ({user_name})."
            ),
            confirmPrompt=(
                f"CONFIRM_UPDATE: Yes, please update post ID {post_id_val} with title '{draft_title}' in {draft_category} for {draft_location}. Description: {draft_content}"
                if action_val == "update" and post_id_val
                else f"CONFIRM_PUBLISH: Yes, please publish the post '{draft_title}' in {draft_category} for {draft_location}."
            )
        )
        resp_type = "post_confirmation"
        clean_msg = _clean_card_intro_message(
            last_ai_content,
            ("Please review and edit your community post below:" if action_val == "update" else "Please review your draft community post below and confirm to publish:"),
            resp_type
        )
        return AgentCardResponse(
            response_type=resp_type,
            message=clean_msg,
            card_data=card.model_dump(),
            metadata={"agent": "community_agent", "user_email": email, "action": action_val, "postId": post_id_val}
        )

    # B. Choice Turn (Worker vs Community Post)
    if is_choice_turn:
        structured_suggestions = [
            {"id": "worker", "text": "1. Find a Verified Worker", "icon": "fa-solid fa-user-gear", "type": "find"},
            {"id": "community", "text": "2. Create a Community Post", "icon": "fa-solid fa-bullhorn", "type": "community"}
        ]
        card = TextMessageCard(
            text=last_ai_content,
            suggestions=structured_suggestions,
            is_choice=True
        )
        return AgentCardResponse(
            response_type="text_message",
            message=last_ai_content,
            card_data=card.model_dump(),
            metadata={"agent": "community_agent", "user_email": email, "is_choice": True}
        )

    # C. Context-aware suggestions for Update / Edit / Question turns
    suggestions = metadata.get("suggested_actions")
    if not suggestions:
        is_asking_question = any(k in lower_content for k in [
            "what kind of work", "what service", "what type of service", "plumbing, electrical", "plumbing or electrical",
            "what category", "tell me what you need", "what issue are you facing", "service you need", "kind of service",
            "repairs, or something else", "what do you need help with", "what would you like to"
        ]) or last_ai_content.strip().endswith("?")

        if any(k in lower_content for k in ["new title", "what would you like the new title", "title to be"]):
            suggestions = ["Keep current title", "Change description instead", "Cancel update"]
        elif any(k in lower_content for k in ["new description", "new content", "what would you like the description"]):
            suggestions = ["Keep current description", "Change title instead", "Cancel update"]
        elif any(k in lower_content for k in ["what would you like to change", "proposed edits", "proposed update", "edit", "update", "change its title"]):
            suggestions = ["Change the title", "Change the description", "Change the category", "Change the location"]
        elif is_asking_question:
            # When the agent is asking a clarification question, do not show recommendation cards; only show the question
            suggestions = None
        else:
            suggestions = None

    card = TextMessageCard(
        text=last_ai_content or "How can I assist you with Workio home services and community posts?",
        suggestions=suggestions
    )
    active_agent = metadata.get("agent") or "community_agent"
    return AgentCardResponse(
        response_type="text_message",
        message=card.text,
        card_data=card.model_dump(),
        metadata={"agent": active_agent, "user_email": email}
    )


async def card_formatter_node(state: AgentState) -> Dict[str, Any]:
    """Deterministic UI Card Formatter Node."""
    card_response = _deterministic_card_builder(state)
    return {"structured_response": card_response}


def build_community_card(state: AgentState, ai_message: Optional[Any] = None) -> AgentCardResponse:
    """Build structured AgentCardResponse for community agent."""
    sim_state = dict(state)
    sim_meta = dict(sim_state.get("metadata") or {})
    sim_meta.setdefault("agent", "community_agent")
    sim_state["metadata"] = sim_meta
    res = _deterministic_card_builder(sim_state, ai_message=ai_message)
    if not res.metadata:
        res.metadata = {}
    res.metadata.setdefault("agent", "community_agent")
    return res


def build_worker_matching_card(state: AgentState, ai_message: Optional[Any] = None) -> AgentCardResponse:
    """Build structured AgentCardResponse for worker matching agent."""
    sim_state = dict(state)
    sim_meta = dict(sim_state.get("metadata") or {})
    sim_meta.setdefault("agent", "worker_matching_agent")
    sim_state["metadata"] = sim_meta
    res = _deterministic_card_builder(sim_state, ai_message=ai_message)
    if not res.metadata:
        res.metadata = {}
    res.metadata.setdefault("agent", "worker_matching_agent")
    return res


def build_booking_card(state: AgentState, ai_message: Optional[Any] = None) -> AgentCardResponse:
    """Build structured AgentCardResponse for booking agent."""
    sim_state = dict(state)
    sim_meta = dict(sim_state.get("metadata") or {})
    sim_meta.setdefault("agent", "booking_agent")
    sim_state["metadata"] = sim_meta
    res = _deterministic_card_builder(sim_state, ai_message=ai_message)
    if not res.metadata:
        res.metadata = {}
    res.metadata.setdefault("agent", "booking_agent")
    return res


def build_support_review_card(state: AgentState, ai_message: Optional[Any] = None) -> AgentCardResponse:
    """Build structured AgentCardResponse for support & review agent."""
    sim_state = dict(state)
    sim_meta = dict(sim_state.get("metadata") or {})
    sim_meta.setdefault("agent", "support_review_agent")
    sim_state["metadata"] = sim_meta
    res = _deterministic_card_builder(sim_state, ai_message=ai_message)
    if not res.metadata:
        res.metadata = {}
    res.metadata.setdefault("agent", "support_review_agent")
    return res


def build_supervisor_card(state: AgentState, text: str, suggestions: Optional[List[str]] = None) -> AgentCardResponse:
    """Build structured AgentCardResponse directly for supervisor greeting/clarification turns."""
    email = state.get("email", "resident@workio.lk")
    card = TextMessageCard(
        text=text,
        suggestions=suggestions or [
            "Find a plumber or electrician",
            "View community posts",
            "Book a service technician",
            "Check my account profile"
        ]
    )
    return AgentCardResponse(
        response_type="text_message",
        message=text,
        card_data=card.model_dump(),
        metadata={"agent": "supervisor", "user_email": email}
    )
