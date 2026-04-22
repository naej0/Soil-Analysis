from fastapi import APIRouter, HTTPException, Query

from models.common_models import ErrorResponse
from models.soil_models import (
    AnalysisLocationResponse,
    GeoJSONResponse,
    SoilLocationResponse,
)
from services.soil_service import (
    get_analysis_by_location,
    get_soil_by_location,
    get_soil_polygons_geojson,
)


router = APIRouter(tags=["Soil and GIS"])


@router.get(
    "/soil/by-location",
    response_model=SoilLocationResponse,
    summary="Get soil by coordinates",
    description="Returns the mapped soil type, soil name, and barangay for a latitude/longitude point in Surigao City.",
    responses={404: {"model": ErrorResponse, "description": "No soil polygon matched the coordinates."}},
)
def soil_by_location(
    lat: float = Query(..., description="Latitude within Surigao City"),
    lng: float = Query(..., description="Longitude within Surigao City"),
):
    soil_data = get_soil_by_location(lat, lng)
    if not soil_data:
        raise HTTPException(status_code=404, detail="No soil data found for this location")

    return {
        "soil_type": soil_data["soil_type"],
        "soil_name": soil_data["soil_name"],
        "barangay": soil_data["barangay"],
    }


@router.get(
    "/soil/polygons",
    response_model=GeoJSONResponse,
    summary="Get soil polygons",
    description="Returns the Surigao City soil map as GeoJSON for GIS and mobile map rendering.",
)
def soil_polygons():
    return get_soil_polygons_geojson()


@router.get(
    "/analysis/by-location",
    response_model=AnalysisLocationResponse,
    summary="Analyze a location",
    description="Combines soil lookup and crop recommendations for a single location in Surigao City.",
    responses={404: {"model": ErrorResponse, "description": "No soil polygon matched the coordinates."}},
)
def analysis_by_location(
    lat: float = Query(..., description="Latitude within Surigao City"),
    lng: float = Query(..., description="Longitude within Surigao City"),
):
    return get_analysis_by_location(lat, lng)
