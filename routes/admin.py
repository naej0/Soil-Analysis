from passlib import apps

from typing import Any

from fastapi import APIRouter, Body, Depends, Header, HTTPException, Query
from pydantic import BaseModel
from db import get_cursor


router = APIRouter(prefix="/admin", tags=["Admin"])


def _clean_text(value: Any) -> str | None:
    if value is None:
        return None

    text = str(value).strip()
    return text or None


def _payload_text(payload: dict | None, key: str) -> str | None:
    if not isinstance(payload, dict):
        return None
    return _clean_text(payload.get(key))


def _rows_to_dicts(rows) -> list[dict]:
    return [dict(row) for row in rows]


def require_admin(
    x_admin_user_id: int | None = Header(None, alias="X-Admin-User-Id"),
    admin_user_id: int | None = Query(None),
) -> dict:
    acting_user_id = x_admin_user_id if x_admin_user_id is not None else admin_user_id
    if acting_user_id is None:
        raise HTTPException(status_code=401, detail="Admin user ID is required")

    with get_cursor(dict_cursor=True) as (_, cursor):
        cursor.execute(
            """
            SELECT id, full_name, email, role, is_active, is_restricted
            FROM users
            WHERE id = %s;
            """,
            (acting_user_id,),
        )
        admin_user = cursor.fetchone()

    if not admin_user:
        raise HTTPException(status_code=401, detail="Admin user not found")

    admin_user = dict(admin_user)
    if (admin_user.get("role") or "").strip().lower() != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")
    if admin_user.get("is_active") is False:
        raise HTTPException(status_code=403, detail="Admin account is inactive")
    if admin_user.get("is_restricted") is True:
        raise HTTPException(status_code=403, detail="Admin account is restricted")

    return admin_user


def _get_user_or_404(cursor, user_id: int):
    cursor.execute(
        """
        SELECT id, full_name, email, role, is_active, is_restricted,
               restriction_reason, restricted_at, restricted_by,
               created_at, updated_at
        FROM users
        WHERE id = %s;
        """,
        (user_id,),
    )
    user = cursor.fetchone()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


def _get_lease_or_404(cursor, lease_id: int):
    cursor.execute(
        """
        SELECT id, owner_name, contact_number, barangay, soil_type,
               area_hectares, price, description, status, created_at,
               updated_at, user_id, is_flagged, flag_reason,
               moderated_by, moderated_at
        FROM land_leases
        WHERE id = %s;
        """,
        (lease_id,),
    )
    lease = cursor.fetchone()
    if not lease:
        raise HTTPException(status_code=404, detail="Lease not found")
    return lease


@router.get("/dashboard")
def get_admin_dashboard(_: dict = Depends(require_admin)):
    with get_cursor(dict_cursor=True) as (_, cursor):
        cursor.execute(
            """
            SELECT
                (SELECT COUNT(*) FROM users) AS total_users,
                (SELECT COUNT(*) FROM users WHERE LOWER(COALESCE(role, '')) = 'admin') AS admin_users,
                (SELECT COUNT(*) FROM users WHERE COALESCE(is_active, TRUE) IS TRUE) AS active_users,
                (SELECT COUNT(*) FROM users WHERE COALESCE(is_restricted, FALSE) IS TRUE) AS restricted_users,
                (SELECT COUNT(*) FROM land_leases) AS total_leases,
                (SELECT COUNT(*) FROM land_leases WHERE LOWER(COALESCE(status, 'active')) = 'active') AS active_leases,
                (SELECT COUNT(*) FROM land_leases WHERE LOWER(COALESCE(status, '')) = 'hidden') AS hidden_leases,
                (SELECT COUNT(*) FROM land_leases WHERE COALESCE(is_flagged, FALSE) IS TRUE) AS flagged_leases,
                (SELECT COUNT(*) FROM productivity_records) AS total_productivity_records,
                (SELECT COUNT(*) FROM soil_analysis_logs) AS total_soil_analysis_logs;
            """
        )
        summary = dict(cursor.fetchone())

    return {
        "users": {
            "total": summary["total_users"],
            "admins": summary["admin_users"],
            "active": summary["active_users"],
            "restricted": summary["restricted_users"],
        },
        "leases": {
            "total": summary["total_leases"],
            "active": summary["active_leases"],
            "hidden": summary["hidden_leases"],
            "flagged": summary["flagged_leases"],
        },
        "productivity": {
            "total_records": summary["total_productivity_records"],
        },
        "soil_analysis_logs": {
            "total_logs": summary["total_soil_analysis_logs"],
        },
    }


@router.get("/users")
def get_admin_users(_: dict = Depends(require_admin)):
    with get_cursor(dict_cursor=True) as (_, cursor):
        cursor.execute(
            """
            SELECT id, full_name, email, role, is_active, is_restricted,
                   restriction_reason, restricted_at, restricted_by,
                   created_at, updated_at
            FROM users
            ORDER BY created_at DESC NULLS LAST, id DESC;
            """
        )
        users = cursor.fetchall()

    return {"users": _rows_to_dicts(users)}


@router.patch("/users/{user_id}/restrict")
def restrict_user(
    user_id: int,
    payload: dict | None = Body(None),
    reason: str | None = Query(None),
    admin_user: dict = Depends(require_admin),
):
    if admin_user["id"] == user_id:
        raise HTTPException(status_code=400, detail="Admin users cannot restrict their own account")

    restriction_reason = (
        _payload_text(payload, "reason")
        or _payload_text(payload, "restriction_reason")
        or _clean_text(reason)
        or "Restricted by admin"
    )

    with get_cursor(dict_cursor=True) as (_, cursor):
        _get_user_or_404(cursor, user_id)
        cursor.execute(
            """
            UPDATE users
            SET is_active = FALSE,
                is_restricted = TRUE,
                restriction_reason = %s,
                restricted_at = NOW(),
                restricted_by = %s,
                updated_at = NOW()
            WHERE id = %s
            RETURNING id, full_name, email, role, is_active, is_restricted,
                      restriction_reason, restricted_at, restricted_by,
                      created_at, updated_at;
            """,
            (restriction_reason, admin_user["id"], user_id),
        )
        updated_user = cursor.fetchone()

    return {"message": "User restricted successfully", "user": dict(updated_user)}


@router.patch("/users/{user_id}/reactivate")
def reactivate_user(user_id: int, _: dict = Depends(require_admin)):
    with get_cursor(dict_cursor=True) as (_, cursor):
        _get_user_or_404(cursor, user_id)
        cursor.execute(
            """
            UPDATE users
            SET is_active = TRUE,
                is_restricted = FALSE,
                restriction_reason = NULL,
                restricted_at = NULL,
                restricted_by = NULL,
                updated_at = NOW()
            WHERE id = %s
            RETURNING id, full_name, email, role, is_active, is_restricted,
                      restriction_reason, restricted_at, restricted_by,
                      created_at, updated_at;
            """,
            (user_id,),
        )
        updated_user = cursor.fetchone()

    return {"message": "User reactivated successfully", "user": dict(updated_user)}


@router.get("/leases")
def get_admin_leases(_: dict = Depends(require_admin)):
    with get_cursor(dict_cursor=True) as (_, cursor):
        cursor.execute(
            """
            SELECT id, owner_name, contact_number, barangay, soil_type,
                   area_hectares, price, description, status, created_at,
                   updated_at, user_id, is_flagged, flag_reason,
                   moderated_by, moderated_at
            FROM land_leases
            ORDER BY created_at DESC NULLS LAST, id DESC;
            """
        )
        leases = cursor.fetchall()

    return {"leases": _rows_to_dicts(leases)}


@router.patch("/leases/{lease_id}/hide")
def hide_lease(lease_id: int, admin_user: dict = Depends(require_admin)):
    with get_cursor(dict_cursor=True) as (_, cursor):
        _get_lease_or_404(cursor, lease_id)
        cursor.execute(
            """
            UPDATE land_leases
            SET status = 'hidden',
                moderated_by = %s,
                moderated_at = NOW(),
                updated_at = NOW()
            WHERE id = %s
            RETURNING id, owner_name, contact_number, barangay, soil_type,
                      area_hectares, price, description, status, created_at,
                      updated_at, user_id, is_flagged, flag_reason,
                      moderated_by, moderated_at;
            """,
            (admin_user["id"], lease_id),
        )
        updated_lease = cursor.fetchone()

    return {"message": "Lease hidden successfully", "lease": dict(updated_lease)}


@router.patch("/leases/{lease_id}/flag")
def flag_lease(
    lease_id: int,
    payload: dict | None = Body(None),
    reason: str | None = Query(None),
    admin_user: dict = Depends(require_admin),
):
    flag_reason = (
        _payload_text(payload, "reason")
        or _payload_text(payload, "flag_reason")
        or _clean_text(reason)
        or "Flagged by admin"
    )

    with get_cursor(dict_cursor=True) as (_, cursor):
        _get_lease_or_404(cursor, lease_id)
        cursor.execute(
            """
            UPDATE land_leases
            SET status = 'flagged',
                is_flagged = TRUE,
                flag_reason = %s,
                moderated_by = %s,
                moderated_at = NOW(),
                updated_at = NOW()
            WHERE id = %s
            RETURNING id, owner_name, contact_number, barangay, soil_type,
                      area_hectares, price, description, status, created_at,
                      updated_at, user_id, is_flagged, flag_reason,
                      moderated_by, moderated_at;
            """,
            (flag_reason, admin_user["id"], lease_id),
        )
        updated_lease = cursor.fetchone()

    return {"message": "Lease flagged successfully", "lease": dict(updated_lease)}


@router.patch("/leases/{lease_id}/restore")
def restore_lease(lease_id: int, admin_user: dict = Depends(require_admin)):
    with get_cursor(dict_cursor=True) as (_, cursor):
        _get_lease_or_404(cursor, lease_id)
        cursor.execute(
            """
            UPDATE land_leases
            SET status = 'active',
                is_flagged = FALSE,
                flag_reason = NULL,
                moderated_by = %s,
                moderated_at = NOW(),
                updated_at = NOW()
            WHERE id = %s
            RETURNING id, owner_name, contact_number, barangay, soil_type,
                      area_hectares, price, description, status, created_at,
                      updated_at, user_id, is_flagged, flag_reason,
                      moderated_by, moderated_at;
            """,
            (admin_user["id"], lease_id),
        )
        updated_lease = cursor.fetchone()

    return {"message": "Lease restored successfully", "lease": dict(updated_lease)}


@router.get("/productivity")
def get_admin_productivity(_: dict = Depends(require_admin)):
    with get_cursor(dict_cursor=True) as (_, cursor):
        cursor.execute(
            """
            SELECT id, user_id, soil_type, crop_name, area_hectares,
                   yield_amount, notes, status, reviewed_by, reviewed_at,
                   created_at, updated_at
            FROM productivity_records
            ORDER BY created_at DESC NULLS LAST, id DESC;
            """
        )
        records = cursor.fetchall()

    return {"records": _rows_to_dicts(records)}


@router.get("/soil-analysis-logs")
def get_admin_soil_analysis_logs(_: dict = Depends(require_admin)):
    with get_cursor(dict_cursor=True) as (_, cursor):
        cursor.execute(
            """
            SELECT id, user_id, lat, lng, soil_type, soil_name, barangay,
                   created_at, predicted_soil_type, confidence,
                   estimated_productivity_level, fertilizer_recommendation,
                   soil_management_advice, crop_recommendations,
                   original_file_name, image_path, updated_at
            FROM soil_analysis_logs
            ORDER BY created_at DESC NULLS LAST, id DESC;
            """
        )
        logs = cursor.fetchall()

    return {"logs": _rows_to_dicts(logs)}
