from json import JSONDecodeError
from datetime import date
from typing import Optional
from fastapi import APIRouter, File, HTTPException, Query, UploadFile, Request
from fastapi.encoders import jsonable_encoder
from pydantic import ValidationError
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
    summary="Create a land lease listing",
    description="Creates a land lease record using the existing land_leases table, computed pricing, and an auto-generated contract.",
    responses={
        400: {"model": ErrorResponse, "description": "Missing price rate or invalid lease data."},
        422: {"model": ErrorResponse, "description": "Missing or invalid request fields."},
        500: {"model": ErrorResponse, "description": "Lease creation failed unexpectedly."},
    },
)
def create_lease_route(
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
    duration_unit: str = Query("months"),
    location_description: Optional[str] = Query(None),
    lease_title: Optional[str] = Query(None),
    user_id: Optional[int] = Query(None),
):
    try:
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
        lease = create_lease(payload)

        return jsonable_encoder({
          "message": "Land lease created successfully",
            "lease": lease,
        })

    except HTTPException:
        raise

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Lease creation failed: {str(exc)}"
        ) from exc

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
    summary="Upload lease media",
    description="Uploads one lease photo, video, or shapefile file for an existing land lease.",
)
async def upload_lease_media_route(
    lease_id: int,
    file: UploadFile = File(
        ...,
        description="Upload one lease photo, video, or shapefile file",
    ),
):
    uploaded_media = upload_lease_media(lease_id, [file])

    return {
        "message": "Lease media uploaded successfully",
        "media": uploaded_media,
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

async def _parse_create_request(request: Request) -> tuple[dict, list]:
    content_type = request.headers.get("content-type", "").lower()
    media_files = []

    if content_type.startswith("multipart/form-data") or content_type.startswith("application/x-www-form-urlencoded"):
        form = await request.form()
        payload_data = {}

        for key, value in form.multi_items():
            if _is_upload_file(value):
                media_files.append(value)
            else:
                payload_data[key] = value

        return _clean_payload_data(payload_data), media_files

    if content_type.startswith("application/json"):
        try:
            body = await request.json()
        except JSONDecodeError as exc:
            raise HTTPException(status_code=422, detail="Invalid JSON body.") from exc

        if body is None:
            body = {}

        if not isinstance(body, dict):
            raise HTTPException(status_code=422, detail="JSON body must be an object.")

        return _clean_payload_data(body), media_files

    return _clean_payload_data(dict(request.query_params)), media_files


def _build_payload(payload_data: dict) -> LeaseCreateRequest:
    try:
        return LeaseCreateRequest(**payload_data)
    except ValidationError as exc:
        safe_errors = []

        for error in exc.errors():
            error.pop("input", None)
            error.pop("url", None)
            safe_errors.append(error)

        raise HTTPException(
            status_code=422,
            detail=jsonable_encoder(safe_errors),
        ) from exc


def _clean_payload_data(payload_data: dict) -> dict:
    cleaned = {}

    for key, value in payload_data.items():
        if isinstance(value, str):
            stripped = value.strip()
            if stripped == "":
                continue
            cleaned[key] = stripped
        else:
            cleaned[key] = value

    return cleaned


def _is_upload_file(value) -> bool:
    return hasattr(value, "filename") and hasattr(value, "file")