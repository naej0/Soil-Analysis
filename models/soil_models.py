from typing import Any

from pydantic import BaseModel, Field


class LocationQuery(BaseModel):
    lat: float = Field(..., description="Latitude within Surigao City")
    lng: float = Field(..., description="Longitude within Surigao City")


class SoilLocationResponse(BaseModel):
    soil_type: str
    soil_name: str
    barangay: str


class RecommendationItem(BaseModel):
    crop_name: str
    suitability: str
    notes: str | None = None


class AnalysisLocationResponse(BaseModel):
    location: dict
    soil: dict
    recommendations: list[RecommendationItem]


class GeoJSONResponse(BaseModel):
    type: str
    features: list[dict[str, Any]]
