from json import JSONDecodeError
from datetime import date
from typing import Optional
from fastapi import APIRouter, Body, File, HTTPException, Query, UploadFile, Request
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
    description="Creates a land lease record using the existing land_leases table, optional lease media, computed pricing, and an auto-generated contract.",
    responses={
        400: {"model": ErrorResponse, "description": "Invalid soil type, price rate, duration unit, or upload."},
        422: {"model": ErrorResponse, "description": "Missing or invalid lease fields."},
        500: {"model": ErrorResponse, "description": "Lease creation failed unexpectedly."},
    },
)
async def create_lease_route(request: Request):
    try:
        payload_data, media_files = await _parse_create_request(request)
        payload = _build_payload(payload_data)
        lease = create_lease(payload, media_files=media_files)

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
        raise HTTPException(status_code=422, detail=exc.errors()) from exc


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