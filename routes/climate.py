from fastapi import APIRouter, HTTPException, Query

from models.climate_models import (
    ClimateAdvisoryResponse,
    ClimateQueryResponse,
    DashboardResponse,
)
from models.common_models import ErrorResponse
from services.climate_service import (
    build_advisory,
    build_advisory_from_data,
    build_current_climate,
    build_current_climate_from_data,
    fetch_weather_data,
)
from services.soil_service import get_soil_by_location


router = APIRouter(tags=["Climate and Dashboard"])


@router.get(
    "/climate/current",
    response_model=ClimateQueryResponse,
    summary="Get current weather conditions",
    description="Returns live current weather conditions for Surigao City coordinates using the Open-Meteo API.",
    responses={502: {"model": ErrorResponse, "description": "Weather provider request failed."}},
)
def climate_current(
    lat: float = Query(..., description="Latitude within Surigao City"),
    lng: float = Query(..., description="Longitude within Surigao City"),
):
    return build_current_climate(lat, lng)


@router.get(
    "/climate/advisory",
    response_model=ClimateAdvisoryResponse,
    summary="Get climate advisory",
    description="Builds a simple farming advisory from live weather and short-range forecast data for Surigao City coordinates.",
    responses={502: {"model": ErrorResponse, "description": "Weather provider request failed."}},
)
def climate_advisory(
    lat: float = Query(..., description="Latitude within Surigao City"),
    lng: float = Query(..., description="Longitude within Surigao City"),
):
    return build_advisory(lat, lng)


@router.get(
    "/dashboard/by-location",
    response_model=DashboardResponse,
    summary="Get dashboard data by coordinates",
    description="Returns soil, crop recommendations, current weather, and advisory data for one location in Surigao City.",
    responses={
        404: {"model": ErrorResponse, "description": "No soil polygon matched the coordinates."},
        502: {"model": ErrorResponse, "description": "Weather provider request failed."},
    },
)
def dashboard_by_location(
    lat: float = Query(..., description="Latitude within Surigao City"),
    lng: float = Query(..., description="Longitude within Surigao City"),
):
    soil_data = get_soil_by_location(lat, lng)
    if not soil_data:
        raise HTTPException(status_code=404, detail="No soil data found for this location")

    weather_data = fetch_weather_data(lat, lng)
    climate = build_current_climate_from_data(lat, lng, weather_data)
    advisory = build_advisory_from_data(lat, lng, weather_data)

    return {
        "location": {
            "lat": lat,
            "lng": lng,
            "barangay": soil_data["barangay"],
        },
        "soil": {
            "soil_type": soil_data["soil_type"],
            "soil_name": soil_data["soil_name"],
        },
        "climate": climate["climate"],
        "advisory": advisory["advisory"],
        "recommendations": soil_data["recommendations"],
    }
