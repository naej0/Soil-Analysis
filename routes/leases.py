from datetime import date

from fastapi import APIRouter, Body, File, HTTPException, Query, UploadFile

from models.common_models import ErrorResponse
from models.lease_models import (
    LeaseContractResponse,
    LeaseCreateRequest,
    LeaseCreateResponse,
    LeaseDetailResponse,
    LeaseListResponse,
    LeaseMediaUploadResponse,
)
from services.lease_service import (
    create_lease,
    get_lease,
    get_lease_contract,
    list_leases,
    upload_lease_media,
)


router = APIRouter(tags=["Land Leases"])


@router.post(
    "/leases",
    response_model=LeaseCreateResponse,
    summary="Create a land lease listing",
    description="Creates a land lease listing, computes pricing, and generates a lease contract.",
    responses={
        400: {"model": ErrorResponse, "description": "Missing price rate or invalid lease data."},
        422: {"model": ErrorResponse, "description": "Missing or invalid request fields."},
    },
)
def create_lease_route(
    payload: LeaseCreateRequest | None = Body(None),
    owner_name: str | None = Query(None),
    contact_number: str | None = Query(None),
    barangay: str | None = Query(None),
    soil_type: str | None = Query(None),
    area_hectares: float | None = Query(None),
    area_sqm: float | None = Query(None),
    price: float | None = Query(None),
    description: str | None = Query(None),
    rental_start_date: date | None = Query(None),
    duration_value: float | None = Query(None),
    duration_unit: str | None = Query(None),
    location_description: str | None = Query(None),
    lease_title: str | None = Query(None),
    user_id: int | None = Query(None),
):
    if payload is None:
        required_values = [
            owner_name,
            contact_number,
            barangay,
            soil_type,
            description,
        ]
        if any(value is None for value in required_values):
            raise HTTPException(status_code=422, detail="Provide JSON body or query parameters.")

        payload = LeaseCreateRequest(
            owner_name=owner_name,
            contact_number=contact_number,
            barangay=barangay,
            soil_type=soil_type,
            area_hectares=area_hectares,
            area_sqm=area_sqm,
            price=price,
            description=description,
            rental_start_date=rental_start_date,
            duration_value=duration_value,
            duration_unit=duration_unit,
            location_description=location_description,
            lease_title=lease_title,
            user_id=user_id,
        )

    return {
        "message": "Land lease created successfully",
        "lease": create_lease(payload),
    }


@router.get(
    "/leases",
    response_model=LeaseListResponse,
    summary="List land lease listings",
    description="Returns land lease records ordered from newest to oldest.",
)
def list_leases_route():
    return {"leases": list_leases()}


@router.get(
    "/leases/{lease_id}",
    response_model=LeaseDetailResponse,
    summary="Get a land lease listing",
    description="Returns one lease listing with related media and contract summary.",
    responses={404: {"model": ErrorResponse, "description": "Lease not found."}},
)
def get_lease_route(lease_id: int):
    return {"lease": get_lease(lease_id)}


@router.post(
    "/leases/{lease_id}/media",
    response_model=LeaseMediaUploadResponse,
    summary="Upload lease media",
    description="Uploads photos, videos, or shapefile ZIP archives for an existing lease.",
    responses={
        400: {"model": ErrorResponse, "description": "Invalid media upload."},
        404: {"model": ErrorResponse, "description": "Lease not found."},
    },
)
def upload_lease_media_route(
    lease_id: int,
    files: list[UploadFile] = File(...),
):
    return {
        "message": "Lease media uploaded successfully",
        "uploaded_media": upload_lease_media(lease_id, files),
    }


@router.get(
    "/leases/{lease_id}/contract",
    response_model=LeaseContractResponse,
    summary="Get a land lease contract",
    description="Returns the generated lease contract.",
    responses={404: {"model": ErrorResponse, "description": "Lease or contract not found."}},
)
def get_lease_contract_route(lease_id: int):
    return get_lease_contract(lease_id)
