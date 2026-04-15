from datetime import datetime

from pydantic import BaseModel, Field


class AITopPrediction(BaseModel):
    soil_type: str
    confidence: float


class AIUploadResponse(BaseModel):
    message: str
    file_name: str
    original_file_name: str
    content_type: str
    size_bytes: int


class AIPredictRequest(BaseModel):
    file_name: str
    user_id: int | None = None
    lat: float | None = None
    lng: float | None = None
    barangay: str | None = None
    soil_name: str | None = None
    original_file_name: str | None = None


class AIPredictResponse(BaseModel):
    status: str
    file_name: str
    prediction: str | None = None
    confidence: float | None = None
    top_predictions: list[AITopPrediction] = Field(default_factory=list)
    supported_soil_types: list[str] = Field(default_factory=list)
    message: str
    created_at: datetime | None = None