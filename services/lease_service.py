from __future__ import annotations

import calendar
from io import BytesIO
import re
from datetime import date, datetime, timedelta
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from pathlib import Path
from uuid import uuid4
from xml.sax.saxutils import escape

from fastapi import HTTPException, UploadFile
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from config import SUPPORTED_SOIL_TYPES, UPLOAD_DIR
from db import get_cursor


LEASE_UPLOAD_DIR = UPLOAD_DIR / "leases"

PHOTO_EXTENSIONS = {  ".jpg",
    ".jpeg",
    ".png",
    ".webp",
    ".heic",
    ".heif",
    ".bmp",
    ".gif",
    ".tif",
    ".tiff",}

VIDEO_EXTENSIONS = {".mp4", ".mov", ".webm"}
SHAPEFILE_EXTENSIONS = {".zip"}

MEDIA_EXTENSION_MAP = {
    **{extension: ("photo", "photos") for extension in PHOTO_EXTENSIONS},
    **{extension: ("video", "videos") for extension in VIDEO_EXTENSIONS},
    **{extension: ("shapefile", "shapefiles") for extension in SHAPEFILE_EXTENSIONS},
}

VALID_LEASE_PAYMENT_STATUSES = {"unpaid", "partial", "paid", "overdue"}
VALID_LEASE_RENTAL_STATUSES = {"pending", "approved", "rejected", "active", "completed", "cancelled"}

LEASE_RENTAL_REQUEST_COLUMNS = [
    "id",
    "land_lease_id",
    "renter_user_id",
    "renter_name",
    "renter_contact",
    "rental_status",
    "payment_status",
    "total_amount",
    "amount_paid",
    "balance_amount",
    "payment_due_date",
    "requested_at",
    "approved_at",
    "approved_by",
    "updated_at",
]



def create_lease(payload) -> dict:
    with get_cursor(dict_cursor=True) as (_, cursor):
        _ensure_lease_schema(cursor)

        soil_type = _normalize_soil_type(payload.soil_type)
        pricing = _build_pricing(cursor, payload, soil_type)

        cursor.execute(
            """
            INSERT INTO public.land_leases (
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
        _ensure_lease_schema(cursor)

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
            FROM public.land_leases
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
            FROM public.lease_contracts
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


def get_lease_contract_pdf(lease_id: int) -> bytes:
    with get_cursor(dict_cursor=True) as (_, cursor):
        lease = _fetch_lease_or_404(cursor, lease_id)
        cursor.execute(
            """
            SELECT
                contract_number,
                contract_body,
                price_per_sqm,
                total_lease_price,
                generated_at
            FROM public.lease_contracts
            WHERE land_lease_id = %s
            ORDER BY generated_at DESC, id DESC
            LIMIT 1;
            """,
            (lease_id,),
        )
        contract = cursor.fetchone()

    if not contract:
        raise HTTPException(status_code=404, detail="No generated contract found for this lease.")

    return _build_lease_contract_pdf(lease, _serialize_contract_body(dict(contract)))


def create_lease_rental_request(lease_id: int, payload) -> dict:
    with get_cursor(dict_cursor=True) as (_, cursor):
        _ensure_lease_schema(cursor)
        lease = _fetch_lease_or_404(cursor, lease_id)
        renter_user = _fetch_renter_user_or_404(cursor, payload.renter_user_id)

        total_amount = _decimal_or_zero(lease.get("total_lease_price"))
        amount_paid = Decimal("0")
        balance_amount = total_amount
        renter_name = _optional_text(payload.renter_name) or renter_user.get("full_name")
        renter_contact = _optional_text(payload.renter_contact)

        cursor.execute(
            f"""
            INSERT INTO public.lease_rental_requests (
                land_lease_id,
                renter_user_id,
                renter_name,
                renter_contact,
                rental_status,
                payment_status,
                total_amount,
                amount_paid,
                balance_amount,
                payment_due_date
            )
            VALUES (%s, %s, %s, %s, 'pending', 'unpaid', %s, %s, %s, %s)
            RETURNING {', '.join(LEASE_RENTAL_REQUEST_COLUMNS)};
            """,
            (
                lease_id,
                payload.renter_user_id,
                renter_name,
                renter_contact,
                total_amount,
                amount_paid,
                balance_amount,
                payload.payment_due_date,
            ),
        )
        rental_request = cursor.fetchone()

    return _serialize_rental_request(dict(rental_request))


def get_lease_rental_requests(lease_id: int) -> list[dict]:
    with get_cursor(dict_cursor=True) as (_, cursor):
        _ensure_lease_schema(cursor)
        _fetch_lease_or_404(cursor, lease_id)
        cursor.execute(
            f"""
            SELECT {', '.join(LEASE_RENTAL_REQUEST_COLUMNS)}
            FROM public.lease_rental_requests
            WHERE land_lease_id = %s
            ORDER BY requested_at DESC NULLS LAST, id DESC;
            """,
            (lease_id,),
        )
        rows = cursor.fetchall()

    return [_serialize_rental_request(dict(row)) for row in rows]


def get_admin_lease_payments() -> list[dict]:
    with get_cursor(dict_cursor=True) as (_, cursor):
        _ensure_lease_schema(cursor)
        cursor.execute(
            """
            SELECT
                rr.id,
                rr.land_lease_id,
                ll.lease_title,
                ll.owner_name AS landowner_name,
                rr.renter_user_id,
                COALESCE(rr.renter_name, u.full_name) AS renter_name,
                rr.renter_contact,
                rr.total_amount,
                rr.amount_paid,
                rr.balance_amount,
                rr.payment_status,
                rr.rental_status,
                rr.payment_due_date,
                rr.requested_at,
                rr.approved_at,
                rr.approved_by
            FROM public.lease_rental_requests rr
            JOIN public.land_leases ll ON ll.id = rr.land_lease_id
            LEFT JOIN public.users u ON u.id = rr.renter_user_id
            ORDER BY rr.requested_at DESC NULLS LAST, rr.id DESC;
            """
        )
        rows = cursor.fetchall()

    return [_serialize_admin_lease_payment(dict(row)) for row in rows]


def update_lease_rental_payment(rental_id: int, payload) -> dict:
    requested_status = _normalize_payment_status(getattr(payload, "payment_status", None))

    with get_cursor(dict_cursor=True) as (_, cursor):
        _ensure_lease_schema(cursor)
        rental_request = _fetch_rental_request_or_404(cursor, rental_id)

        total_amount = _decimal_or_zero(rental_request.get("total_amount"))
        amount_paid = _optional_non_negative_decimal(
            getattr(payload, "amount_paid", None),
            "amount_paid",
        )
        if amount_paid is None:
            amount_paid = _decimal_or_zero(rental_request.get("amount_paid"))

        balance_amount = total_amount - amount_paid
        if balance_amount < 0:
            balance_amount = Decimal("0")

        if amount_paid >= total_amount:
            payment_status = "paid"
            balance_amount = Decimal("0")
        elif requested_status:
            payment_status = requested_status
        elif amount_paid > 0:
            payment_status = "partial"
        else:
            payment_status = "unpaid"

        cursor.execute(
            f"""
            UPDATE public.lease_rental_requests
            SET
                amount_paid = %s,
                balance_amount = %s,
                payment_status = %s,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = %s
            RETURNING {', '.join(LEASE_RENTAL_REQUEST_COLUMNS)};
            """,
            (
                _round_decimal(amount_paid, "0.01"),
                _round_decimal(balance_amount, "0.01"),
                payment_status,
                rental_id,
            ),
        )
        updated_request = cursor.fetchone()

    return _serialize_rental_request(dict(updated_request))


def update_lease_rental_status(rental_id: int, payload) -> dict:
    rental_status = _normalize_rental_status(payload.rental_status)

    with get_cursor(dict_cursor=True) as (_, cursor):
        _ensure_lease_schema(cursor)
        _fetch_rental_request_or_404(cursor, rental_id)

        set_parts = [
            "rental_status = %s",
            "updated_at = CURRENT_TIMESTAMP",
        ]
        params = [rental_status]

        if rental_status == "approved":
            set_parts.append("approved_at = CURRENT_TIMESTAMP")
            set_parts.append("approved_by = %s")
            params.append(payload.approved_by)

        params.append(rental_id)
        cursor.execute(
            f"""
            UPDATE public.lease_rental_requests
            SET {', '.join(set_parts)}
            WHERE id = %s
            RETURNING {', '.join(LEASE_RENTAL_REQUEST_COLUMNS)};
            """,
            tuple(params),
        )
        updated_request = cursor.fetchone()

    return _serialize_rental_request(dict(updated_request))


def _ensure_lease_schema(cursor) -> None:
    """
    Ensures the Lease Marketplace tables/columns exist in the exact database
    connection used by the running backend.
    """

    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS land_leases (
            id SERIAL PRIMARY KEY,
            owner_name VARCHAR(150),
            contact_number VARCHAR(50),
            barangay VARCHAR(100),
            soil_type VARCHAR(100),
            area_hectares NUMERIC,
            price NUMERIC,
            description TEXT,
            status VARCHAR(50) DEFAULT 'active',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            user_id INTEGER,
            is_flagged BOOLEAN DEFAULT FALSE,
            flag_reason TEXT,
            moderated_by INTEGER,
            moderated_at TIMESTAMP
        );

        ALTER TABLE land_leases ADD COLUMN IF NOT EXISTS area_sqm NUMERIC;
        ALTER TABLE land_leases ADD COLUMN IF NOT EXISTS rental_start_date DATE;
        ALTER TABLE land_leases ADD COLUMN IF NOT EXISTS rental_end_date DATE;
        ALTER TABLE land_leases ADD COLUMN IF NOT EXISTS duration_value INTEGER;
        ALTER TABLE land_leases ADD COLUMN IF NOT EXISTS duration_unit VARCHAR(30);
        ALTER TABLE land_leases ADD COLUMN IF NOT EXISTS duration_months NUMERIC;
        ALTER TABLE land_leases ADD COLUMN IF NOT EXISTS price_per_sqm NUMERIC;
        ALTER TABLE land_leases ADD COLUMN IF NOT EXISTS total_lease_price NUMERIC;
        ALTER TABLE land_leases ADD COLUMN IF NOT EXISTS location_description TEXT;
        ALTER TABLE land_leases ADD COLUMN IF NOT EXISTS contract_status VARCHAR(50);
        ALTER TABLE land_leases ADD COLUMN IF NOT EXISTS lease_title VARCHAR(200);
        ALTER TABLE land_leases ADD COLUMN IF NOT EXISTS availability_start_date DATE;
        ALTER TABLE land_leases ADD COLUMN IF NOT EXISTS availability_end_date DATE;

        CREATE TABLE IF NOT EXISTS lease_soil_price_rates (
            id SERIAL PRIMARY KEY,
            soil_type VARCHAR(80),
            price_per_sqm_per_month NUMERIC(12,2),
            price_per_sqm NUMERIC(12,2),
            is_active BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        ALTER TABLE lease_soil_price_rates ADD COLUMN IF NOT EXISTS id SERIAL;
        ALTER TABLE lease_soil_price_rates ADD COLUMN IF NOT EXISTS soil_type VARCHAR(80);
        ALTER TABLE lease_soil_price_rates ADD COLUMN IF NOT EXISTS price_per_sqm_per_month NUMERIC(12,2);
        ALTER TABLE lease_soil_price_rates ADD COLUMN IF NOT EXISTS price_per_sqm NUMERIC(12,2);
        ALTER TABLE lease_soil_price_rates ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE;
        ALTER TABLE lease_soil_price_rates ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
        ALTER TABLE lease_soil_price_rates ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

        CREATE TABLE IF NOT EXISTS lease_contracts (
            id SERIAL PRIMARY KEY,
            land_lease_id INTEGER,
            contract_number VARCHAR(80),
            contract_body TEXT,
            price_per_sqm NUMERIC,
            total_lease_price NUMERIC,
            generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        ALTER TABLE lease_contracts ADD COLUMN IF NOT EXISTS land_lease_id INTEGER;
        ALTER TABLE lease_contracts ADD COLUMN IF NOT EXISTS contract_number VARCHAR(80);
        ALTER TABLE lease_contracts ADD COLUMN IF NOT EXISTS contract_body TEXT;
        ALTER TABLE lease_contracts ADD COLUMN IF NOT EXISTS price_per_sqm NUMERIC;
        ALTER TABLE lease_contracts ADD COLUMN IF NOT EXISTS total_lease_price NUMERIC;
        ALTER TABLE lease_contracts ADD COLUMN IF NOT EXISTS generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

        CREATE TABLE IF NOT EXISTS lease_media (
            id SERIAL PRIMARY KEY,
            land_lease_id INTEGER,
            file_type VARCHAR(50),
            original_file_name VARCHAR(255),
            saved_file_name VARCHAR(255),
            file_path TEXT,
            file_extension VARCHAR(20),
            content_type VARCHAR(120),
            size_bytes INTEGER,
            uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        ALTER TABLE lease_media ADD COLUMN IF NOT EXISTS land_lease_id INTEGER;
        ALTER TABLE lease_media ADD COLUMN IF NOT EXISTS file_type VARCHAR(50);
        ALTER TABLE lease_media ADD COLUMN IF NOT EXISTS original_file_name VARCHAR(255);
        ALTER TABLE lease_media ADD COLUMN IF NOT EXISTS saved_file_name VARCHAR(255);
        ALTER TABLE lease_media ADD COLUMN IF NOT EXISTS file_path TEXT;
        ALTER TABLE lease_media ADD COLUMN IF NOT EXISTS file_extension VARCHAR(20);
        ALTER TABLE lease_media ADD COLUMN IF NOT EXISTS content_type VARCHAR(120);
        ALTER TABLE lease_media ADD COLUMN IF NOT EXISTS size_bytes INTEGER;
        ALTER TABLE lease_media ADD COLUMN IF NOT EXISTS uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

        CREATE TABLE IF NOT EXISTS lease_rental_requests (
            id SERIAL PRIMARY KEY,
            land_lease_id INTEGER NOT NULL,
            renter_user_id INTEGER NOT NULL,
            renter_name VARCHAR(150),
            renter_contact VARCHAR(50),
            rental_status VARCHAR(50) DEFAULT 'pending',
            payment_status VARCHAR(50) DEFAULT 'unpaid',
            total_amount NUMERIC DEFAULT 0,
            amount_paid NUMERIC DEFAULT 0,
            balance_amount NUMERIC DEFAULT 0,
            payment_due_date DATE,
            requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            approved_at TIMESTAMP NULL,
            approved_by INTEGER NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        ALTER TABLE lease_rental_requests ADD COLUMN IF NOT EXISTS id SERIAL;
        ALTER TABLE lease_rental_requests ADD COLUMN IF NOT EXISTS land_lease_id INTEGER;
        ALTER TABLE lease_rental_requests ADD COLUMN IF NOT EXISTS renter_user_id INTEGER;
        ALTER TABLE lease_rental_requests ADD COLUMN IF NOT EXISTS renter_name VARCHAR(150);
        ALTER TABLE lease_rental_requests ADD COLUMN IF NOT EXISTS renter_contact VARCHAR(50);
        ALTER TABLE lease_rental_requests ADD COLUMN IF NOT EXISTS rental_status VARCHAR(50) DEFAULT 'pending';
        ALTER TABLE lease_rental_requests ADD COLUMN IF NOT EXISTS payment_status VARCHAR(50) DEFAULT 'unpaid';
        ALTER TABLE lease_rental_requests ADD COLUMN IF NOT EXISTS total_amount NUMERIC DEFAULT 0;
        ALTER TABLE lease_rental_requests ADD COLUMN IF NOT EXISTS amount_paid NUMERIC DEFAULT 0;
        ALTER TABLE lease_rental_requests ADD COLUMN IF NOT EXISTS balance_amount NUMERIC DEFAULT 0;
        ALTER TABLE lease_rental_requests ADD COLUMN IF NOT EXISTS payment_due_date DATE;
        ALTER TABLE lease_rental_requests ADD COLUMN IF NOT EXISTS requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
        ALTER TABLE lease_rental_requests ADD COLUMN IF NOT EXISTS approved_at TIMESTAMP NULL;
        ALTER TABLE lease_rental_requests ADD COLUMN IF NOT EXISTS approved_by INTEGER NULL;
        ALTER TABLE lease_rental_requests ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
        """
    )

    cursor.execute(
        """
        WITH default_rates(soil_type, rate) AS (
            VALUES
                ('Clay', 2.00),
                ('Clay Loam', 2.50),
                ('Loam', 3.00),
                ('Rock Land', 1.00),
                ('Silty Clay', 2.20)
        )
        UPDATE lease_soil_price_rates r
        SET
            price_per_sqm_per_month = d.rate,
            price_per_sqm = d.rate,
            is_active = TRUE,
            updated_at = CURRENT_TIMESTAMP
        FROM default_rates d
        WHERE LOWER(TRIM(r.soil_type)) = LOWER(TRIM(d.soil_type));
        """
    )

    cursor.execute(
        """
        WITH default_rates(soil_type, rate) AS (
            VALUES
                ('Clay', 2.00),
                ('Clay Loam', 2.50),
                ('Loam', 3.00),
                ('Rock Land', 1.00),
                ('Silty Clay', 2.20)
        )
        INSERT INTO lease_soil_price_rates (
            soil_type,
            price_per_sqm_per_month,
            price_per_sqm,
            is_active
        )
        SELECT
            d.soil_type,
            d.rate,
            d.rate,
            TRUE
        FROM default_rates d
        WHERE NOT EXISTS (
            SELECT 1
            FROM lease_soil_price_rates r
            WHERE LOWER(TRIM(r.soil_type)) = LOWER(TRIM(d.soil_type))
        );
        """
    )

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


LEASE_SOIL_PRICE_FALLBACK = {
    "clay": Decimal("2.00"),
    "clay loam": Decimal("2.50"),
    "loam": Decimal("3.00"),
    "rock land": Decimal("1.00"),
    "silty clay": Decimal("2.20"),
}


def _fetch_price_per_sqm(cursor, soil_type: str) -> Decimal | None:
    normalized_soil_type = (soil_type or "").strip().lower()

    queries = [
        """
        SELECT price_per_sqm_per_month AS price_per_sqm
        FROM public.lease_soil_price_rates
        WHERE LOWER(TRIM(soil_type)) = LOWER(TRIM(%s))
          AND COALESCE(is_active, TRUE) = TRUE
        ORDER BY id DESC
        LIMIT 1;
        """,
        """
        SELECT price_per_sqm AS price_per_sqm
        FROM public.lease_soil_price_rates
        WHERE LOWER(TRIM(soil_type)) = LOWER(TRIM(%s))
          AND COALESCE(is_active, TRUE) = TRUE
        ORDER BY id DESC
        LIMIT 1;
        """,
    ]

    for query in queries:
        try:
            cursor.execute(query, (soil_type,))
            row = cursor.fetchone()

            if row and row.get("price_per_sqm") is not None:
                return Decimal(str(row["price_per_sqm"]))

        except Exception:
            try:
                cursor.connection.rollback()
            except Exception:
                pass

    return LEASE_SOIL_PRICE_FALLBACK.get(normalized_soil_type)


def _create_lease_contract(cursor, lease: dict) -> dict:
    contract_number = f"LC-{date.today().year}-{lease['id']:06d}"
    contract_body = _generate_contract_body(lease, contract_number)

    cursor.execute(
        """
        INSERT INTO public.lease_contracts (
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


def _build_lease_contract_pdf(lease: dict, contract: dict) -> bytes:
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        rightMargin=0.75 * inch,
        leftMargin=0.75 * inch,
        topMargin=0.75 * inch,
        bottomMargin=0.7 * inch,
        title="KASUNDUAN SA PAGPAPAUPA NG LUPA",
    )

    styles = _lease_pdf_styles()
    elements = [
        Paragraph("KASUNDUAN SA PAGPAPAUPA NG LUPA", styles["LeaseTitle"]),
        Spacer(1, 0.16 * inch),
        Paragraph(
            "Ang kasunduang ito ay nagpapatunay sa mga pangunahing detalye ng pagpapaupa "
            "ng lupang pang-agrikultura. The renter details are left blank until a renter "
            "is confirmed and both parties are ready to sign.",
            styles["Body"],
        ),
        Spacer(1, 0.18 * inch),
        Paragraph("Mga Detalye ng Kontrata", styles["SectionHeading"]),
        Spacer(1, 0.08 * inch),
        _lease_details_table(lease, contract, styles),
        Spacer(1, 0.2 * inch),
        Paragraph("Mga Tuntunin at Kundisyon", styles["SectionHeading"]),
        Spacer(1, 0.08 * inch),
    ]

    terms = [
        "The land shall be used only for lawful agricultural or agreed purposes.",
        "The renter shall pay the agreed amount according to the payment schedule.",
        "The renter shall maintain the land and avoid causing damage.",
        "The landowner shall allow the renter to use the land during the agreed rental period.",
        "Both parties should verify boundaries, responsibilities, and legal terms before signing.",
    ]

    for index, term in enumerate(terms, start=1):
        elements.append(Paragraph(f"{index}. {_pdf_text(term)}", styles["BodyJustified"]))
        elements.append(Spacer(1, 0.05 * inch))

    elements.extend(
        [
            Spacer(1, 0.18 * inch),
            Paragraph("Lagda ng mga Partido", styles["SectionHeading"]),
            Spacer(1, 0.1 * inch),
            _signature_table(lease, styles),
        ]
    )

    doc.build(elements, onFirstPage=_draw_pdf_footer, onLaterPages=_draw_pdf_footer)
    pdf_bytes = buffer.getvalue()
    buffer.close()
    return pdf_bytes


def _lease_pdf_styles() -> dict:
    base_styles = getSampleStyleSheet()
    return {
        "LeaseTitle": ParagraphStyle(
            "LeaseTitle",
            parent=base_styles["Title"],
            alignment=TA_CENTER,
            fontName="Helvetica-Bold",
            fontSize=16,
            leading=20,
            spaceAfter=6,
            textColor=colors.HexColor("#1f2933"),
        ),
        "SectionHeading": ParagraphStyle(
            "SectionHeading",
            parent=base_styles["Heading2"],
            fontName="Helvetica-Bold",
            fontSize=11,
            leading=14,
            spaceBefore=4,
            spaceAfter=4,
            textColor=colors.HexColor("#1f2933"),
        ),
        "Body": ParagraphStyle(
            "Body",
            parent=base_styles["BodyText"],
            fontName="Helvetica",
            fontSize=9.5,
            leading=13,
            textColor=colors.HexColor("#202124"),
        ),
        "BodyJustified": ParagraphStyle(
            "BodyJustified",
            parent=base_styles["BodyText"],
            alignment=TA_JUSTIFY,
            fontName="Helvetica",
            fontSize=9.5,
            leading=13,
            textColor=colors.HexColor("#202124"),
        ),
        "FieldLabel": ParagraphStyle(
            "FieldLabel",
            parent=base_styles["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=8.8,
            leading=11,
            textColor=colors.HexColor("#1f2933"),
        ),
        "FieldValue": ParagraphStyle(
            "FieldValue",
            parent=base_styles["BodyText"],
            fontName="Helvetica",
            fontSize=8.8,
            leading=11,
            textColor=colors.HexColor("#202124"),
        ),
        "SignatureHeader": ParagraphStyle(
            "SignatureHeader",
            parent=base_styles["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=9,
            leading=12,
            textColor=colors.HexColor("#1f2933"),
        ),
    }


def _lease_details_table(lease: dict, contract: dict, styles: dict) -> Table:
    details = [
        ("Contract Number", contract.get("contract_number")),
        ("Lease Title", lease.get("lease_title") or "Untitled Lease"),
        ("Landowner / Nagpapa-upa", lease.get("owner_name")),
        ("Contact Number", lease.get("contact_number")),
        ("Barangay", lease.get("barangay")),
        ("Location Description", lease.get("location_description") or "Not specified"),
        ("Soil Type", lease.get("soil_type")),
        ("Area in sqm", f"{_format_decimal(lease.get('area_sqm'))} sqm"),
        ("Rental Start Date", _format_pdf_date(lease.get("rental_start_date"))),
        ("Rental End Date", _format_pdf_date(lease.get("rental_end_date"))),
        ("Duration", _format_lease_duration(lease)),
        ("Price per sqm", f"PHP {_format_money(contract.get('price_per_sqm'))} per month"),
        ("Total Lease Price", f"PHP {_format_money(contract.get('total_lease_price'))}"),
    ]
    rows = [
        [
            Paragraph(_pdf_text(label), styles["FieldLabel"]),
            Paragraph(_pdf_text(value), styles["FieldValue"]),
        ]
        for label, value in details
    ]
    table = Table(rows, colWidths=[1.95 * inch, 4.05 * inch], hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#b8c2cc")),
                ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#f3f6f8")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 7),
                ("RIGHTPADDING", (0, 0), (-1, -1), 7),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    return table


def _signature_table(lease: dict, styles: dict) -> Table:
    owner_name = lease.get("owner_name") or "______________________"
    rows = [
        [
            Paragraph("<b>NAGPAPA-UPA / LANDOWNER</b>", styles["SignatureHeader"]),
            Paragraph("<b>UMUUPA / RENTER</b>", styles["SignatureHeader"]),
        ],
        [
            Paragraph(f"Name: {_pdf_text(owner_name)}", styles["FieldValue"]),
            Paragraph("Name: ______________________", styles["FieldValue"]),
        ],
        [
            Paragraph("Signature: ______________________", styles["FieldValue"]),
            Paragraph("Signature: ______________________", styles["FieldValue"]),
        ],
        [
            Paragraph("Date: ______________________", styles["FieldValue"]),
            Paragraph("Date: ______________________", styles["FieldValue"]),
        ],
        [
            Paragraph("Witness 1: ______________________", styles["FieldValue"]),
            Paragraph("Witness 2: ______________________", styles["FieldValue"]),
        ],
    ]
    table = Table(rows, colWidths=[3 * inch, 3 * inch], hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("BOX", (0, 0), (-1, -1), 0.45, colors.HexColor("#8f9aa3")),
                ("INNERGRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#c7d0d8")),
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#f3f6f8")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    return table


def _draw_pdf_footer(canvas, doc) -> None:
    canvas.saveState()
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(colors.HexColor("#667085"))
    canvas.drawString(0.75 * inch, 0.42 * inch, "Generated Lease Marketplace Contract")
    canvas.drawRightString(A4[0] - (0.75 * inch), 0.42 * inch, f"Page {doc.page}")
    canvas.restoreState()


def _format_pdf_date(value) -> str:
    if isinstance(value, (date, datetime)):
        return value.strftime("%B %d, %Y")
    return str(value or "Not specified")


def _format_lease_duration(lease: dict) -> str:
    duration_value = _format_decimal(lease.get("duration_value"))
    duration_unit = lease.get("duration_unit") or "months"
    duration_months = _format_decimal(lease.get("duration_months"))
    return f"{duration_value} {duration_unit} ({duration_months} months)"


def _format_money(value) -> str:
    if value is None:
        return "0.00"
    return f"{Decimal(str(value)):,.2f}"


def _pdf_text(value) -> str:
    return escape(str(value if value is not None else "Not specified"))


def _fetch_renter_user_or_404(cursor, renter_user_id: int) -> dict:
    user_columns = _get_table_columns(cursor, "users")
    if not user_columns:
        raise HTTPException(status_code=500, detail="users table not found.")

    select_columns = [
        column
        for column in ["id", "full_name", "email", "is_active", "is_restricted"]
        if column in user_columns
    ]
    if "id" not in select_columns:
        raise HTTPException(status_code=500, detail="users table is missing id column.")

    cursor.execute(
        f"SELECT {', '.join(select_columns)} FROM public.users WHERE id = %s LIMIT 1;",
        (renter_user_id,),
    )
    renter_user = cursor.fetchone()
    if not renter_user:
        raise HTTPException(status_code=404, detail="Renter user not found.")

    renter_user = dict(renter_user)
    if "is_active" in user_columns and renter_user.get("is_active") is False:
        raise HTTPException(status_code=400, detail="Renter user account is inactive.")
    if "is_restricted" in user_columns and renter_user.get("is_restricted") is True:
        raise HTTPException(status_code=400, detail="Renter user account is restricted.")

    return renter_user


def _fetch_rental_request_or_404(cursor, rental_id: int) -> dict:
    cursor.execute(
        f"""
        SELECT {', '.join(LEASE_RENTAL_REQUEST_COLUMNS)}
        FROM public.lease_rental_requests
        WHERE id = %s
        LIMIT 1;
        """,
        (rental_id,),
    )
    rental_request = cursor.fetchone()
    if not rental_request:
        raise HTTPException(status_code=404, detail="Lease rental request not found.")
    return dict(rental_request)


def _get_table_columns(cursor, table_name: str) -> set[str]:
    cursor.execute(
        """
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = %s
        ORDER BY ordinal_position;
        """,
        (table_name,),
    )
    return {row["column_name"] if isinstance(row, dict) else row[0] for row in cursor.fetchall()}


def _normalize_payment_status(payment_status: str | None) -> str | None:
    status = _optional_text(payment_status)
    if status is None:
        return None

    normalized = status.lower()
    if normalized not in VALID_LEASE_PAYMENT_STATUSES:
        allowed = ", ".join(sorted(VALID_LEASE_PAYMENT_STATUSES))
        raise HTTPException(status_code=400, detail=f"payment_status must be one of: {allowed}.")
    return normalized


def _normalize_rental_status(rental_status: str | None) -> str:
    status = _optional_text(rental_status)
    if status is None:
        allowed = ", ".join(sorted(VALID_LEASE_RENTAL_STATUSES))
        raise HTTPException(status_code=400, detail=f"rental_status must be one of: {allowed}.")

    normalized = status.lower()
    if normalized not in VALID_LEASE_RENTAL_STATUSES:
        allowed = ", ".join(sorted(VALID_LEASE_RENTAL_STATUSES))
        raise HTTPException(status_code=400, detail=f"rental_status must be one of: {allowed}.")
    return normalized


def _decimal_or_zero(value) -> Decimal:
    if value is None:
        return Decimal("0")
    return Decimal(str(value))


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
        FROM public.land_leases
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
        FROM public.lease_media
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
        FROM public.lease_contracts
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


def _serialize_rental_request(rental_request: dict) -> dict:
    return {
        "id": rental_request["id"],
        "land_lease_id": rental_request["land_lease_id"],
        "renter_user_id": rental_request["renter_user_id"],
        "renter_name": rental_request.get("renter_name"),
        "renter_contact": rental_request.get("renter_contact"),
        "rental_status": rental_request.get("rental_status"),
        "payment_status": rental_request.get("payment_status"),
        "total_amount": _to_float(rental_request.get("total_amount")),
        "amount_paid": _to_float(rental_request.get("amount_paid")),
        "balance_amount": _to_float(rental_request.get("balance_amount")),
        "payment_due_date": rental_request.get("payment_due_date"),
        "requested_at": rental_request.get("requested_at"),
        "approved_at": rental_request.get("approved_at"),
        "approved_by": rental_request.get("approved_by"),
        "updated_at": rental_request.get("updated_at"),
    }


def _serialize_admin_lease_payment(row: dict) -> dict:
    return {
        "id": row["id"],
        "rental_id": row["id"],
        "land_lease_id": row["land_lease_id"],
        "lease_title": row.get("lease_title"),
        "landowner_name": row.get("landowner_name"),
        "renter_user_id": row["renter_user_id"],
        "renter_name": row.get("renter_name"),
        "renter_contact": row.get("renter_contact"),
        "total_amount": _to_float(row.get("total_amount")),
        "amount_paid": _to_float(row.get("amount_paid")),
        "balance_amount": _to_float(row.get("balance_amount")),
        "payment_status": row.get("payment_status"),
        "rental_status": row.get("rental_status"),
        "payment_due_date": row.get("payment_due_date"),
        "requested_at": row.get("requested_at"),
        "approved_at": row.get("approved_at"),
        "approved_by": row.get("approved_by"),
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

_ALLOWED_DURATION_UNITS = {
    "day": "days",
    "days": "days",
    "daily": "days",
    "month": "months",
    "months": "months",
    "monthly": "months",
    "month(s)": "months",
    "year": "years",
    "years": "years",
    "yearly": "years",
    "annual": "years",
    "annually": "years",
}


def _normalize_duration_unit(duration_unit: str | None) -> str:
    raw_value = str(duration_unit or "months").strip().lower()

    # Remove hidden characters, spaces, quotes, dots, dashes, etc.
    normalized_key = re.sub(r"[^a-z]", "", raw_value)

    unit_map = {
        "day": "days",
        "days": "days",
        "daily": "days",

        "month": "months",
        "months": "months",
        "monthly": "months",
        "mo": "months",
        "mos": "months",

        "year": "years",
        "years": "years",
        "yearly": "years",
        "yr": "years",
        "yrs": "years",
    }

    normalized = unit_map.get(normalized_key)

    if normalized is None:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid duration_unit received: '{duration_unit}'. Use only: day, days, month, months, year, or years."
        )

    return normalized


def _convert_duration_to_months(duration_value: Decimal, duration_unit: str | None) -> Decimal:
    unit = _normalize_duration_unit(duration_unit)

    if unit == "days":
        return duration_value / Decimal("30")

    if unit == "months":
        return duration_value

    if unit == "years":
        return duration_value * Decimal("12")

    raise HTTPException(
        status_code=422,
        detail="duration_unit must be one of: day, days, month, months, year, years.",
    )


def _compute_rental_end_date(rental_start_date: date, duration_value, duration_unit: str | None) -> date:
    unit = _normalize_duration_unit(duration_unit)

    try:
        value = Decimal(str(duration_value or 1))
    except Exception as exc:
        raise HTTPException(status_code=422, detail="duration_value must be a valid number.") from exc

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
        detail="duration_unit must be one of: day, days, month, months, year, years.",
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
