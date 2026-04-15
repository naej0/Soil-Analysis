from pydantic import BaseModel

from models.soil_models import RecommendationItem


class ClimateQueryResponse(BaseModel):
    location: dict
    climate: dict


class ClimateAdvisoryResponse(BaseModel):
    location: dict
    current: dict
    advisory: list[str]
    forecast: dict


class DashboardResponse(BaseModel):
    location: dict
    soil: dict
    climate: dict
    advisory: list[str]
    recommendations: list[RecommendationItem]
