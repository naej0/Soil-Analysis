from fastapi import APIRouter, Body

from models.assistant_models import AssistantChatRequest, AssistantChatResponse
from services.assistant_service import chat_with_assistant


router = APIRouter(prefix="/assistant", tags=["Assistant"])


@router.post(
    "/chat",
    response_model=AssistantChatResponse,
    summary="Chat with the agriculture assistant",
    description="Returns a short grounded answer using only the local agriculture assistant knowledge base.",
)
def chat(payload: AssistantChatRequest = Body(...)):
    return chat_with_assistant(payload.question, payload.context, payload.history)
