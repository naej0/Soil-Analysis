from datetime import date
from typing import Optional
from fastapi import APIRouter, Body, File, HTTPException, Query, UploadFile, requests

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
    description="Creates a land lease record using the existing land_leases table, computed pricing, and an auto-generated contract.",
    responses={
        400: {"model": ErrorResponse, "description": "Missing price rate or invalid lease data."},
        422: {"model": ErrorResponse, "description": "Missing or invalid request fields."},
    },
)
async def create_lease_route(
    owner_name: str = Query(...),
    contact_number: str = Query(...),
    barangay: str = Query(...),
    soil_type: str = Query(...),
    area_hectares: Optional[float] = Query(None),
    area_sqm: Optional[float] = Query(None),
    price: Optional[float] = Query(None),
    description: Optional[str] = Query(None),
    rental_start_date: date = Query(...),
    duration_value: float = Query(1),
    duration_unit: str = Query(
        "months",
        description="Allowed values: day, days, month, months, year, years",
    ),
    location_description: Optional[str] = Query(None),
    lease_title: Optional[str] = Query(None),
    user_id: Optional[int] = Query(None),
):
    payload_data = {
        "owner_name": owner_name,
        "contact_number": contact_number,
        "barangay": barangay,
        "soil_type": soil_type,
        "rental_start_date": rental_start_date,
        "duration_value": duration_value,
        "duration_unit": duration_unit,
    }

    optional_fields = {
        "area_hectares": area_hectares,
        "area_sqm": area_sqm,
        "price": price,
        "description": description,
        "location_description": location_description,
        "lease_title": lease_title,
        "user_id": user_id,
    }

    for key, value in optional_fields.items():
        if value is not None:
            payload_data[key] = value

    payload = _build_payload(payload_data)
    lease = create_lease(payload, media_files=[])

    return {
        "message": "Land lease created successfully",
        "lease": lease,
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
