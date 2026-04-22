from pydantic import BaseModel

from models.soil_models import RecommendationItem


class RecommendationResponse(BaseModel):
    soil_type: str
    recommendations: list[RecommendationItem]
