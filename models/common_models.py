from typing import Any

from pydantic import BaseModel


class MessageResponse(BaseModel):
    message: str


class HealthResponse(BaseModel):
    message: str


class ErrorResponse(BaseModel):
    detail: Any


class AssistantSource(BaseModel):
    title: str
    type: str
    reference: str | None = None


class AssistantResponse(BaseModel):
    status: str
    question: str
    answer: str
    sources: list[AssistantSource]
    metadata: dict[str, Any]
