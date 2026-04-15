from fastapi import APIRouter, Body, HTTPException, Query

from models.common_models import ErrorResponse
from models.lease_models import LeaseCreateRequest, LeaseCreateResponse, LeaseListResponse
from services.lease_service import create_lease, list_leases


router = APIRouter(tags=["Land Leases"])


@router.post(
    "/leases",
    response_model=LeaseCreateResponse,
    summary="Create a land lease listing",
    description="Creates a new land lease listing for Surigao City using one of the five supported soil types.",
    responses={400: {"model": ErrorResponse, "description": "Unsupported soil type."}},
)
def create_lease_route(
    payload: LeaseCreateRequest | None = Body(None),
    owner_name: str | None = Query(None),
    contact_number: str | None = Query(None),
    barangay: str | None = Query(None),
    soil_type: str | None = Query(None),
    area_hectares: float | None = Query(None),
    price: float | None = Query(None),
    description: str | None = Query(None),
):
    if payload is None:
        required_values = [
            owner_name,
            contact_number,
            barangay,
            soil_type,
            area_hectares,
            price,
            description,
        ]
        if any(value is None for value in required_values):
            raise HTTPException(status_code=422, detail="Provide JSON body or query parameters")
        payload = LeaseCreateRequest(
            owner_name=owner_name,
            contact_number=contact_number,
            barangay=barangay,
            soil_type=soil_type,
            area_hectares=area_hectares,
            price=price,
            description=description,
        )
    lease = create_lease(payload)
    return {"message": "Land lease created successfully", "lease": lease}


@router.get(
    "/leases",
    response_model=LeaseListResponse,
    summary="List land lease listings",
    description="Returns all available land lease records ordered from newest to oldest.",
)
def list_leases_route():
    return {"leases": list_leases()}
