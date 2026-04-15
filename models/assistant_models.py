from typing import Any

from pydantic import BaseModel


class AssistantChatRequest(BaseModel):
    question: str
    context: dict[str, Any] | None = None
    history: list[dict[str, Any] | str] | None = None


class AssistantChatResponse(BaseModel):
    status: str
    answer: str
    matched_topics: list[str]
    used_context: dict[str, Any] | None = None
    message: str
