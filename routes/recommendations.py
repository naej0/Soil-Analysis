from fastapi import APIRouter, Query

from models.common_models import ErrorResponse
from models.recommendation_models import RecommendationResponse
from services.recommendation_service import (
    get_recommendations_by_soil_type,
    normalize_soil_type,
)


router = APIRouter(tags=["Recommendations"])


@router.get(
    "/recommendations/by-soil",
    response_model=RecommendationResponse,
    summary="Get crop recommendations by soil type",
    description="Returns crop recommendations for one of the five supported Surigao City soil types, ordered by suitability: High, Medium, then Low.",
    responses={400: {"model": ErrorResponse, "description": "Unsupported soil type."}},
)
def recommendations_by_soil(
    soil_type: str = Query(..., description="One of the five supported soil types"),
):
    canonical_soil_type = normalize_soil_type(soil_type)
    return {
        "soil_type": canonical_soil_type,
        "recommendations": get_recommendations_by_soil_type(canonical_soil_type),
    }
