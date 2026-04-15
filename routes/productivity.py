from fastapi import APIRouter, Body, HTTPException, Query

from models.common_models import ErrorResponse
from models.productivity_models import (
    ProductivityCreateRequest,
    ProductivityCreateResponse,
    ProductivityListResponse,
)
from services.productivity_service import (
    create_productivity_record,
    list_productivity_records,
)


router = APIRouter(tags=["Productivity"])


@router.post(
    "/productivity",
    response_model=ProductivityCreateResponse,
    summary="Create a productivity record",
    description="Stores a crop productivity record linked to a user and one of the five supported soil types.",
    responses={
        400: {"model": ErrorResponse, "description": "Unsupported soil type."},
        404: {"model": ErrorResponse, "description": "User not found."},
    },
)
def create_productivity(
    payload: ProductivityCreateRequest | None = Body(None),
    user_id: int | None = Query(None),
    soil_type: str | None = Query(None),
    crop_name: str | None = Query(None),
    area_hectares: float | None = Query(None),
    yield_amount: float | None = Query(None),
    notes: str = Query(""),
):
    if payload is None:
        required_values = [user_id, soil_type, crop_name, area_hectares, yield_amount]
        if any(value is None for value in required_values):
            raise HTTPException(status_code=422, detail="Provide JSON body or query parameters")
        payload = ProductivityCreateRequest(
            user_id=user_id,
            soil_type=soil_type,
            crop_name=crop_name,
            area_hectares=area_hectares,
            yield_amount=yield_amount,
            notes=notes,
        )
    record = create_productivity_record(payload)
    return {"message": "Productivity record created successfully", "record": record}


@router.get(
    "/productivity/{user_id}",
    response_model=ProductivityListResponse,
    summary="Get productivity records by user",
    description="Returns the productivity history for a specific user, ordered from newest to oldest.",
    responses={404: {"model": ErrorResponse, "description": "User not found."}},
)
def get_productivity(user_id: int):
    return {"records": list_productivity_records(user_id)}
