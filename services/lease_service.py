from __future__ import annotations

import calendar
from datetime import date, datetime, timedelta
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from pathlib import Path
from uuid import uuid4

from fastapi import HTTPException, UploadFile

from config import SUPPORTED_SOIL_TYPES, UPLOAD_DIR
from db import get_cursor


LEASE_UPLOAD_DIR = UPLOAD_DIR / "leases"

PHOTO_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
VIDEO_EXTENSIONS = {".mp4", ".mov", ".webm"}
SHAPEFILE_EXTENSIONS = {".zip"}

MEDIA_EXTENSION_MAP = {
    **{extension: ("photo", "photos") for extension in PHOTO_EXTENSIONS},
    **{extension: ("video", "videos") for extension in VIDEO_EXTENSIONS},
    **{extension: ("shapefile", "shapefiles") for extension in SHAPEFILE_EXTENSIONS},
}


def create_lease(payload) -> dict:
    with get_cursor(dict_cursor=True) as (_, cursor):
        soil_type = _normalize_soil_type(payload.soil_type)
        pricing = _build_pricing(cursor, payload, soil_type)

        cursor.execute(
            """
            INSERT INTO land_leases (
                owner_name,
                contact_number,
                barangay,
                soil_type,
                area_hectares,
                area_sqm,
                price,
                description,
                status,
                user_id,
                is_flagged,
                rental_start_date,
                rental_end_date,
                duration_value,
                duration_unit,
                duration_months,
                price_per_sqm,
                total_lease_price,
                location_description,
                contract_status,
                lease_title,
                availability_start_date,
                availability_end_date
            )
            VALUES (
                %(owner_name)s,
                %(contact_number)s,
                %(barangay)s,
                %(soil_type)s,
                %(area_hectares)s,
                %(area_sqm)s,
                %(price)s,
                %(description)s,
                %(status)s,
                %(user_id)s,
                %(is_flagged)s,
                %(rental_start_date)s,
                %(rental_end_date)s,
                %(duration_value)s,
                %(duration_unit)s,
                %(duration_months)s,
                %(price_per_sqm)s,
                %(total_lease_price)s,
                %(location_description)s,
                %(contract_status)s,
                %(lease_title)s,
                %(availability_start_date)s,
                %(availability_end_date)s
            )
            RETURNING
                id,
                owner_name,
                contact_number,
                barangay,
                soil_type,
                area_hectares,
                area_sqm,
                price,
                description,
                status,
                created_at,
                rental_start_date,
                rental_end_date,
                duration_value,
                duration_unit,
                duration_months,
                price_per_sqm,
                total_lease_price,
                location_description,
                contract_status,
                lease_title,
                availability_start_date,
                availability_end_date;
            """,
            {
                "owner_name": _required_text(payload.owner_name, "owner_name"),
                "contact_number": _required_text(payload.contact_number, "contact_number"),
                "barangay": _required_text(payload.barangay, "barangay"),
                "soil_type": soil_type,
                "area_hectares": pricing["area_hectares"],
                "area_sqm": pricing["area_sqm"],
                "price": pricing["total_lease_price"],
                "description": _required_text(payload.description, "description"),
                "status": "active",
                "user_id": payload.user_id,
                "is_flagged": False,
                "rental_start_date": pricing["rental_start_date"],
                "rental_end_date": pricing["rental_end_date"],
                "duration_value": pricing["duration_value"],
                "duration_unit": pricing["duration_unit"],
                "duration_months": pricing["duration_months"],
                "price_per_sqm": pricing["price_per_sqm"],
                "total_lease_price": pricing["total_lease_price"],
                "location_description": _optional_text(payload.location_description),
                "contract_status": "generated",
                "lease_title": _optional_text(payload.lease_title),
                "availability_start_date": pricing["rental_start_date"],
                "availability_end_date": pricing["rental_end_date"],
            },
        )
        lease = dict(cursor.fetchone())
        contract = _create_lease_contract(cursor, lease)

    return _serialize_lease(lease, contract=contract)


def list_leases() -> list[dict]:
    with get_cursor(dict_cursor=True) as (_, cursor):
        cursor.execute(
            """
            SELECT
                id,
                owner_name,
                contact_number,
                barangay,
                soil_type,
                area_hectares,
                area_sqm,
                price,
                description,
                status,
                created_at,
                rental_start_date,
                rental_end_date,
                duration_value,
                duration_unit,
                duration_months,
                price_per_sqm,
                total_lease_price,
                location_description,
                contract_status,
                lease_title,
                availability_start_date,
                availability_end_date
            FROM land_leases
            ORDER BY created_at DESC;
            """
        )
        rows = cursor.fetchall()

    return [_serialize_lease(dict(row)) for row in rows]


def get_lease(lease_id: int) -> dict:
    with get_cursor(dict_cursor=True) as (_, cursor):
        lease = _fetch_lease_or_404(cursor, lease_id)
        media = _fetch_media(cursor, lease_id)
        contract = _fetch_contract_summary(cursor, lease_id)

    return _serialize_lease(lease, media=media, contract=contract)


def upload_lease_media(lease_id: int, files: list[UploadFile]) -> list[dict]:
    if not files:
        raise HTTPException(status_code=400, detail="Upload at least one lease media file.")

    saved_paths: list[Path] = []

    try:
        with get_cursor(dict_cursor=True) as (_, cursor):
            _fetch_lease_or_404(cursor, lease_id)
            uploaded_media = []

            for upload_file in files:
                file_type, folder_name, extension = _classify_upload(upload_file)
                original_file_name = Path((upload_file.filename or "").strip()).name
                saved_file_name = f"{uuid4().hex}{extension}"
                destination = LEASE_UPLOAD_DIR / folder_name / saved_file_name
                stored_path = Path("uploads") / "leases" / folder_name / saved_file_name

                file_bytes = upload_file.file.read()
                if not file_bytes:
                    raise HTTPException(
                        status_code=400,
                        detail=f"{original_file_name} is empty.",
                    )

                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(file_bytes)
                saved_paths.append(destination)

                cursor.execute(
                    """
                    INSERT INTO lease_media (
                        land_lease_id,
                        file_type,
                        original_file_name,
                        saved_file_name,
                        file_path,
                        file_extension,
                        content_type,
                        size_bytes
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    RETURNING
                        id,
                        land_lease_id,
                        file_type,
                        original_file_name,
                        saved_file_name,
                        file_path,
                        file_extension,
                        content_type,
                        size_bytes,
                        uploaded_at;
                    """,
                    (
                        lease_id,
                        file_type,
                        original_file_name,
                        saved_file_name,
                        stored_path.as_posix(),
                        extension,
                        upload_file.content_type or "application/octet-stream",
                        len(file_bytes),
                    ),
                )
                uploaded_media.append(_serialize_media(dict(cursor.fetchone())))

        return uploaded_media
    except Exception:
        for path in saved_paths:
            try:
                path.unlink(missing_ok=True)
            except Exception:
                pass
        raise


def get_lease_contract(lease_id: int) -> dict:
    with get_cursor(dict_cursor=True) as (_, cursor):
        _fetch_lease_or_404(cursor, lease_id)
        cursor.execute(
            """
            SELECT
                contract_number,
                contract_body,
                price_per_sqm,
                total_lease_price,
                generated_at
            FROM lease_contracts
            WHERE land_lease_id = %s
            ORDER BY generated_at DESC, id DESC
            LIMIT 1;
            """,
            (lease_id,),
        )
        contract = cursor.fetchone()

    if not contract:
        raise HTTPException(status_code=404, detail="No generated contract found for this lease.")

    return _serialize_contract_body(dict(contract))


def _build_pricing(cursor, payload, soil_type: str) -> dict:
    area_hectares = _optional_positive_decimal(payload.area_hectares, "area_hectares")
    area_sqm = _optional_positive_decimal(payload.area_sqm, "area_sqm")

    if area_sqm is None and area_hectares is not None:
        area_sqm = area_hectares * Decimal("10000")
    if area_hectares is None and area_sqm is not None:
        area_hectares = area_sqm / Decimal("10000")
    if area_sqm is None or area_hectares is None:
        raise HTTPException(status_code=422, detail="Provide either area_hectares or area_sqm.")

    rental_start_date = payload.rental_start_date or date.today()
    duration_value = _optional_positive_decimal(payload.duration_value, "duration_value") or Decimal("1")
    duration_unit = _normalize_duration_unit(payload.duration_unit or "months")
    duration_months = _convert_duration_to_months(duration_value, duration_unit)
    rental_end_date = _compute_rental_end_date(rental_start_date, duration_value, duration_unit)

    price_per_sqm = _fetch_price_per_sqm(cursor, soil_type)
    legacy_total_price = _optional_non_negative_decimal(payload.price, "price")

    if price_per_sqm is None:
        if legacy_total_price is None:
            raise HTTPException(
                status_code=400,
                detail=f"No active lease price rate found for soil type '{soil_type}'.",
            )
        total_lease_price = legacy_total_price
        price_per_sqm = total_lease_price / (area_sqm * duration_months)
    else:
        total_lease_price = area_sqm * price_per_sqm * duration_months

    return {
        "area_hectares": _round_decimal(area_hectares, "0.0001"),
        "area_sqm": _round_decimal(area_sqm, "0.01"),
        "rental_start_date": rental_start_date,
        "rental_end_date": rental_end_date,
        "duration_value": _round_decimal(duration_value, "0.01"),
        "duration_unit": duration_unit,
        "duration_months": _round_decimal(duration_months, "0.0001"),
        "price_per_sqm": _round_decimal(price_per_sqm, "0.0001"),
        "total_lease_price": _round_decimal(total_lease_price, "0.01"),
    }


def _fetch_price_per_sqm(cursor, soil_type: str) -> Decimal | None:
    price_column = _price_rate_column(cursor)
    cursor.execute(
        f"""
        SELECT {price_column} AS price_per_sqm
        FROM lease_soil_price_rates
        WHERE LOWER(TRIM(soil_type)) = LOWER(TRIM(%s))
          AND is_active = TRUE
        ORDER BY id DESC
        LIMIT 1;
        """,
        (soil_type,),
    )
    row = cursor.fetchone()
    return row["price_per_sqm"] if row else None


def _price_rate_column(cursor) -> str:
    cursor.execute(
        """
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'lease_soil_price_rates'
          AND column_name IN ('price_per_sqm_per_month', 'price_per_sqm');
        """
    )
    columns = {row["column_name"] for row in cursor.fetchall()}
    if "price_per_sqm_per_month" in columns:
        return "price_per_sqm_per_month"
    if "price_per_sqm" in columns:
        return "price_per_sqm"
    raise HTTPException(
        status_code=500,
        detail="lease_soil_price_rates must have price_per_sqm_per_month or price_per_sqm.",
    )


def _create_lease_contract(cursor, lease: dict) -> dict:
    contract_number = f"LC-{date.today().year}-{lease['id']:06d}"
    contract_body = _generate_contract_body(lease, contract_number)

    cursor.execute(
        """
        INSERT INTO lease_contracts (
            land_lease_id,
            contract_number,
            contract_body,
            price_per_sqm,
            total_lease_price
        )
        VALUES (%s, %s, %s, %s, %s)
        RETURNING
            id,
            land_lease_id,
            contract_number,
            price_per_sqm,
            total_lease_price,
            generated_at;
        """,
        (
            lease["id"],
            contract_number,
            contract_body,
            lease["price_per_sqm"],
            lease["total_lease_price"],
        ),
    )
    return _serialize_contract_summary(dict(cursor.fetchone()))


def _generate_contract_body(lease: dict, contract_number: str) -> str:
    return "\n".join(
        [
            "LAND LEASE CONTRACT",
            "",
            f"Contract Number: {contract_number}",
            f"Lease Title: {lease.get('lease_title') or 'Untitled Lease'}",
            f"Landowner: {lease['owner_name']}",
            f"Contact Number: {lease['contact_number']}",
            f"Barangay: {lease['barangay']}",
            f"Location Description: {lease.get('location_description') or 'Not specified'}",
            f"Soil Type: {lease['soil_type']}",
            f"Area: {_format_decimal(lease['area_sqm'])} sqm ({_format_decimal(lease['area_hectares'])} hectares)",
            f"Rental Start Date: {lease['rental_start_date']}",
            f"Rental End Date: {lease['rental_end_date']}",
            f"Duration: {_format_decimal(lease['duration_value'])} {lease['duration_unit']} ({_format_decimal(lease['duration_months'])} months)",
            f"Price Per Sqm Per Month: PHP {_format_decimal(lease['price_per_sqm'])}",
            f"Total Lease Price: PHP {_format_decimal(lease['total_lease_price'])}",
            "",
            "This generated contract records the lease listing details submitted through the Lease Marketplace. "
            "The parties should verify land boundaries, payment schedule, responsibilities, and legal terms before signing.",
        ]
    )


def _fetch_lease_or_404(cursor, lease_id: int) -> dict:
    cursor.execute(
        """
        SELECT
            id,
            owner_name,
            contact_number,
            barangay,
            soil_type,
            area_hectares,
            area_sqm,
            price,
            description,
            status,
            created_at,
            rental_start_date,
            rental_end_date,
            duration_value,
            duration_unit,
            duration_months,
            price_per_sqm,
            total_lease_price,
            location_description,
            contract_status,
            lease_title,
            availability_start_date,
            availability_end_date
        FROM land_leases
        WHERE id = %s
        LIMIT 1;
        """,
        (lease_id,),
    )
    lease = cursor.fetchone()
    if not lease:
        raise HTTPException(status_code=404, detail="Lease record not found.")
    return dict(lease)


def _fetch_media(cursor, lease_id: int) -> list[dict]:
    cursor.execute(
        """
        SELECT
            id,
            land_lease_id,
            file_type,
            original_file_name,
            saved_file_name,
            file_path,
            file_extension,
            content_type,
            size_bytes,
            uploaded_at
        FROM lease_media
        WHERE land_lease_id = %s
        ORDER BY uploaded_at DESC, id DESC;
        """,
        (lease_id,),
    )
    return [_serialize_media(dict(row)) for row in cursor.fetchall()]


def _fetch_contract_summary(cursor, lease_id: int) -> dict | None:
    cursor.execute(
        """
        SELECT
            id,
            land_lease_id,
            contract_number,
            price_per_sqm,
            total_lease_price,
            generated_at
        FROM lease_contracts
        WHERE land_lease_id = %s
        ORDER BY generated_at DESC, id DESC
        LIMIT 1;
        """,
        (lease_id,),
    )
    row = cursor.fetchone()
    return _serialize_contract_summary(dict(row)) if row else None


def _serialize_lease(
    lease: dict,
    *,
    media: list[dict] | None = None,
    contract: dict | None = None,
) -> dict:
    return {
        "id": lease["id"],
        "owner_name": lease["owner_name"],
        "contact_number": lease["contact_number"],
        "barangay": lease["barangay"],
        "soil_type": lease["soil_type"],
        "area_hectares": _to_float(lease.get("area_hectares")),
        "area_sqm": _to_float(lease.get("area_sqm")),
        "price": _to_float(lease.get("price")),
        "description": lease.get("description") or "",
        "status": lease.get("status"),
        "created_at": lease.get("created_at"),
        "rental_start_date": lease.get("rental_start_date"),
        "rental_end_date": lease.get("rental_end_date"),
        "duration_value": _to_float(lease.get("duration_value")),
        "duration_unit": lease.get("duration_unit"),
        "duration_months": _to_float(lease.get("duration_months")),
        "price_per_sqm": _to_float(lease.get("price_per_sqm")),
        "total_lease_price": _to_float(lease.get("total_lease_price")),
        "location_description": lease.get("location_description"),
        "contract_status": lease.get("contract_status"),
        "lease_title": lease.get("lease_title"),
        "availability_start_date": lease.get("availability_start_date"),
        "availability_end_date": lease.get("availability_end_date"),
        "contract_number": contract["contract_number"] if contract else None,
        "media": media or [],
        "contract": contract,
    }


def _serialize_media(media: dict) -> dict:
    return {
        "id": media["id"],
        "land_lease_id": media["land_lease_id"],
        "file_type": media["file_type"],
        "original_file_name": media["original_file_name"],
        "saved_file_name": media["saved_file_name"],
        "file_path": media["file_path"],
        "file_extension": media["file_extension"],
        "content_type": media.get("content_type"),
        "size_bytes": media["size_bytes"],
        "uploaded_at": media.get("uploaded_at"),
    }


def _serialize_contract_summary(contract: dict) -> dict:
    return {
        "id": contract["id"],
        "land_lease_id": contract["land_lease_id"],
        "contract_number": contract["contract_number"],
        "price_per_sqm": _to_float(contract.get("price_per_sqm")),
        "total_lease_price": _to_float(contract.get("total_lease_price")),
        "generated_at": contract.get("generated_at"),
    }


def _serialize_contract_body(contract: dict) -> dict:
    return {
        "contract_number": contract["contract_number"],
        "contract_body": contract["contract_body"],
        "price_per_sqm": _to_float(contract.get("price_per_sqm")),
        "total_lease_price": _to_float(contract.get("total_lease_price")),
        "generated_at": contract.get("generated_at"),
    }


def _classify_upload(upload_file: UploadFile) -> tuple[str, str, str]:
    original_file_name = Path((upload_file.filename or "").strip()).name
    if not original_file_name:
        raise HTTPException(status_code=400, detail="Uploaded file must include a file name.")

    extension = Path(original_file_name).suffix.lower()
    media_info = MEDIA_EXTENSION_MAP.get(extension)
    if media_info is None:
        raise HTTPException(
            status_code=400,
            detail={
                "message": "Unsupported lease media file extension.",
                "allowed": {
                    "photo": sorted(PHOTO_EXTENSIONS),
                    "video": sorted(VIDEO_EXTENSIONS),
                    "shapefile": sorted(SHAPEFILE_EXTENSIONS),
                },
            },
        )
    return media_info[0], media_info[1], extension


def _normalize_soil_type(soil_type: str) -> str:
    cleaned = _required_text(soil_type, "soil_type")
    for supported_soil_type in SUPPORTED_SOIL_TYPES:
        if cleaned.lower() == supported_soil_type.lower():
            return supported_soil_type
    return cleaned


def _normalize_duration_unit(duration_unit: str | None) -> str:
    unit = (duration_unit or "month").strip().lower()

    unit_map = {
        "day": "days",
        "days": "days",
        "month": "months",
        "months": "months",
        "year": "years",
        "years": "years",
    }

    normalized = unit_map.get(unit)

    if normalized is None:
        raise HTTPException(
            status_code=422,
            detail="duration_unit must be one of: day, days, month, months, year, years."
        )

    return normalized


def _convert_duration_to_months(duration_value: Decimal, duration_unit: str) -> Decimal:
    if duration_unit == "days":
        return duration_value / Decimal("30")
    if duration_unit == "months":
        return duration_value
    if duration_unit == "years":
        return duration_value * Decimal("12")
    raise HTTPException(
        status_code=422,
        detail="duration_unit must be one of: day, days, month, months, year, years.",
    )


def _compute_rental_end_date(rental_start_date: date, duration_value, duration_unit: str | None) -> date:
    unit = _normalize_duration_unit(duration_unit)

    try:
        value = Decimal(str(duration_value or 1))
    except Exception:
        raise HTTPException(status_code=422, detail="duration_value must be a valid number.")

    if value <= 0:
        raise HTTPException(status_code=422, detail="duration_value must be greater than zero.")

    whole_value = int(value)

    if unit == "days":
        return rental_start_date + timedelta(days=whole_value)

    if unit == "months":
        return _add_months(rental_start_date, whole_value)

    if unit == "years":
        return _add_months(rental_start_date, whole_value * 12)

    raise HTTPException(
        status_code=422,
        detail="duration_unit must be one of: day, days, month, months, year, years."
    )


def _add_months(start_date: date, months: int) -> date:
    month_index = start_date.month - 1 + months
    year = start_date.year + month_index // 12
    month = month_index % 12 + 1
    day = min(start_date.day, calendar.monthrange(year, month)[1])
    return date(year, month, day)


def _add_years(start_date: date, years: Decimal) -> date:
    if years == years.to_integral_value():
        year = start_date.year + int(years)
        day = min(start_date.day, calendar.monthrange(year, start_date.month)[1])
        return date(year, start_date.month, day)
    return start_date + timedelta(days=_rounded_int(years * Decimal("365")))


def _rounded_int(value: Decimal) -> int:
    return int(value.to_integral_value(rounding=ROUND_HALF_UP))


def _required_text(value: str | None, field_name: str) -> str:
    cleaned = (value or "").strip()
    if not cleaned:
        raise HTTPException(status_code=422, detail=f"{field_name} is required.")
    return cleaned


def _optional_text(value: str | None) -> str | None:
    cleaned = (value or "").strip()
    return cleaned or None


def _optional_positive_decimal(value, field_name: str) -> Decimal | None:
    decimal_value = _optional_decimal(value, field_name)
    if decimal_value is not None and decimal_value <= 0:
        raise HTTPException(status_code=422, detail=f"{field_name} must be greater than zero.")
    return decimal_value


def _optional_non_negative_decimal(value, field_name: str) -> Decimal | None:
    decimal_value = _optional_decimal(value, field_name)
    if decimal_value is not None and decimal_value < 0:
        raise HTTPException(status_code=422, detail=f"{field_name} must be zero or greater.")
    return decimal_value


def _optional_decimal(value, field_name: str) -> Decimal | None:
    if value is None or value == "":
        return None
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError) as exc:
        raise HTTPException(status_code=422, detail=f"{field_name} must be a valid number.") from exc


def _round_decimal(value: Decimal, pattern: str) -> Decimal:
    return value.quantize(Decimal(pattern), rounding=ROUND_HALF_UP)


def _to_float(value) -> float | None:
    if value is None:
        return None
    return float(value)


def _format_decimal(value) -> str:
    if value is None:
        return "0"
    return format(Decimal(str(value)).normalize(), "f")
