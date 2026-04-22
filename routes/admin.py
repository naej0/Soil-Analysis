from typing import Any, Optional

from fastapi import APIRouter, Body, Depends, Header, HTTPException, Query

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
    return [dict(row) for row in (rows or [])]


def _table_exists(cursor, table_name: str) -> bool:
    cursor.execute(
        """
        SELECT EXISTS (
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name = %s
        ) AS exists;
        """,
        (table_name,),
    )
    row = cursor.fetchone()
    if not row:
        return False
    if isinstance(row, dict):
        return bool(row.get("exists"))
    return bool(row[0])


def _get_columns(cursor, table_name: str) -> set[str]:
    cursor.execute(
        """
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = %s
        ORDER BY ordinal_position;
        """,
        (table_name,),
    )
    rows = cursor.fetchall()
    columns: set[str] = set()
    for row in rows:
        if isinstance(row, dict):
            columns.add(row["column_name"])
        else:
            columns.add(row[0])
    return columns


def _existing_columns(cursor, table_name: str, preferred_columns: list[str]) -> tuple[list[str], set[str]]:
    columns = _get_columns(cursor, table_name)
    return [column for column in preferred_columns if column in columns], columns


def _build_order_by(columns: set[str]) -> str:
    if "created_at" in columns and "id" in columns:
        return " ORDER BY created_at DESC NULLS LAST, id DESC"
    if "updated_at" in columns and "id" in columns:
        return " ORDER BY updated_at DESC NULLS LAST, id DESC"
    if "id" in columns:
        return " ORDER BY id DESC"
    return ""


def _fetch_table_rows(cursor, table_name: str, preferred_columns: list[str]) -> list[dict]:
    if not _table_exists(cursor, table_name):
        return []

    select_columns, existing = _existing_columns(cursor, table_name, preferred_columns)
    if not select_columns:
        return []

    query = f"SELECT {', '.join(select_columns)} FROM {table_name}{_build_order_by(existing)};"
    cursor.execute(query)
    return _rows_to_dicts(cursor.fetchall())


def _fetch_record_by_id(cursor, table_name: str, record_id: int, preferred_columns: list[str]) -> dict:
    if not _table_exists(cursor, table_name):
        raise HTTPException(status_code=404, detail=f"{table_name} table not found")

    select_columns, _ = _existing_columns(cursor, table_name, preferred_columns)
    if "id" not in select_columns:
        raise HTTPException(status_code=500, detail=f"{table_name} table is missing id column")

    cursor.execute(
        f"SELECT {', '.join(select_columns)} FROM {table_name} WHERE id = %s LIMIT 1;",
        (record_id,),
    )
    row = cursor.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail=f"{table_name} record not found")
    return dict(row)


def _fetch_count(cursor, sql: str, params: tuple = ()) -> int:
    cursor.execute(sql, params)
    row = cursor.fetchone()
    if not row:
        return 0
    if isinstance(row, dict):
        return int(row.get("count") or 0)
    return int(row[0] or 0)


def require_admin(
    x_admin_user_id: Optional[int] = Header(None, alias="X-Admin-User-Id"),
    admin_user_id: Optional[int] = Query(None),
    admin_id: Optional[int] = Query(None),
) -> dict:
    acting_user_id = x_admin_user_id or admin_user_id or admin_id
    if acting_user_id is None:
        raise HTTPException(status_code=401, detail="Admin user ID is required")

    with get_cursor(dict_cursor=True) as (_, cursor):
        if not _table_exists(cursor, "users"):
            raise HTTPException(status_code=500, detail="users table not found")

        select_columns, existing = _existing_columns(
            cursor,
            "users",
            ["id", "full_name", "email", "role", "is_active", "is_restricted"],
        )
        if "id" not in select_columns:
            raise HTTPException(status_code=500, detail="users table is missing id column")

        cursor.execute(
            f"SELECT {', '.join(select_columns)} FROM users WHERE id = %s LIMIT 1;",
            (acting_user_id,),
        )
        admin_user = cursor.fetchone()

    if not admin_user:
        raise HTTPException(status_code=401, detail="Admin user not found")

    admin_user = dict(admin_user)

    if "role" in existing and (admin_user.get("role") or "").strip().lower() != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")
    if "is_active" in existing and admin_user.get("is_active") is False:
        raise HTTPException(status_code=403, detail="Admin account is inactive")
    if "is_restricted" in existing and admin_user.get("is_restricted") is True:
        raise HTTPException(status_code=403, detail="Admin account is restricted")

    return admin_user


@router.get("/dashboard")
def get_admin_dashboard(_: dict = Depends(require_admin)):
    with get_cursor(dict_cursor=True) as (_, cursor):
        total_users = 0
        admin_users = 0
        active_users = 0
        restricted_users = 0

        if _table_exists(cursor, "users"):
            user_columns = _get_columns(cursor, "users")
            total_users = _fetch_count(cursor, "SELECT COUNT(*) AS count FROM users")

            if "role" in user_columns:
                admin_users = _fetch_count(
                    cursor,
                    "SELECT COUNT(*) AS count FROM users WHERE LOWER(COALESCE(role, '')) = 'admin'",
                )

            if "is_active" in user_columns:
                active_users = _fetch_count(
                    cursor,
                    "SELECT COUNT(*) AS count FROM users WHERE COALESCE(is_active, TRUE) = TRUE",
                )
            else:
                active_users = total_users

            if "is_restricted" in user_columns:
                restricted_users = _fetch_count(
                    cursor,
                    "SELECT COUNT(*) AS count FROM users WHERE COALESCE(is_restricted, FALSE) = TRUE",
                )

        total_lease_listings = 0
        active_lease_listings = 0
        hidden_lease_listings = 0
        flagged_lease_listings = 0

        if _table_exists(cursor, "land_leases"):
            lease_columns = _get_columns(cursor, "land_leases")
            total_lease_listings = _fetch_count(cursor, "SELECT COUNT(*) AS count FROM land_leases")

            if "status" in lease_columns:
                active_lease_listings = _fetch_count(
                    cursor,
                    """
                    SELECT COUNT(*) AS count
                    FROM land_leases
                    WHERE LOWER(COALESCE(status, 'active')) = 'active'
                    """,
                )
                hidden_lease_listings = _fetch_count(
                    cursor,
                    """
                    SELECT COUNT(*) AS count
                    FROM land_leases
                    WHERE LOWER(COALESCE(status, '')) = 'hidden'
                    """,
                )
            else:
                active_lease_listings = total_lease_listings

            if "is_hidden" in lease_columns:
                hidden_lease_listings = _fetch_count(
                    cursor,
                    "SELECT COUNT(*) AS count FROM land_leases WHERE COALESCE(is_hidden, FALSE) = TRUE",
                )
                active_lease_listings = max(total_lease_listings - hidden_lease_listings, 0)

            if "is_flagged" in lease_columns:
                flagged_lease_listings = _fetch_count(
                    cursor,
                    "SELECT COUNT(*) AS count FROM land_leases WHERE COALESCE(is_flagged, FALSE) = TRUE",
                )

        total_productivity_records = 0
        if _table_exists(cursor, "productivity_records"):
            total_productivity_records = _fetch_count(
                cursor,
                "SELECT COUNT(*) AS count FROM productivity_records",
            )

        total_soil_analyses = 0
        common_soil_types: list[dict] = []
        if _table_exists(cursor, "soil_analysis_logs"):
            log_columns = _get_columns(cursor, "soil_analysis_logs")
            total_soil_analyses = _fetch_count(
                cursor,
                "SELECT COUNT(*) AS count FROM soil_analysis_logs",
            )

            soil_column = None
            if "predicted_soil_type" in log_columns:
                soil_column = "predicted_soil_type"
            elif "soil_type" in log_columns:
                soil_column = "soil_type"
            elif "soil_name" in log_columns:
                soil_column = "soil_name"

            if soil_column:
                cursor.execute(
                    f"""
                    SELECT {soil_column} AS soil_type, COUNT(*) AS total
                    FROM soil_analysis_logs
                    WHERE {soil_column} IS NOT NULL AND TRIM(CAST({soil_column} AS TEXT)) <> ''
                    GROUP BY {soil_column}
                    ORDER BY total DESC, {soil_column} ASC
                    LIMIT 5;
                    """
                )
                common_soil_types = _rows_to_dicts(cursor.fetchall())

    return {
        "total_users": total_users,
        "admin_users": admin_users,
        "active_users": active_users,
        "restricted_users": restricted_users,
        "total_lease_listings": total_lease_listings,
        "active_lease_listings": active_lease_listings,
        "hidden_lease_listings": hidden_lease_listings,
        "flagged_lease_listings": flagged_lease_listings,
        "total_productivity_records": total_productivity_records,
        "total_soil_analyses": total_soil_analyses,
        "common_soil_types": common_soil_types,
    }


@router.get("/users")
def get_admin_users(_: dict = Depends(require_admin)):
    user_columns = [
        "id",
        "full_name",
        "email",
        "role",
        "is_active",
        "is_restricted",
        "restriction_reason",
        "restricted_at",
        "restricted_by",
        "created_at",
        "updated_at",
    ]
    with get_cursor(dict_cursor=True) as (_, cursor):
        users = _fetch_table_rows(cursor, "users", user_columns)
    return {"users": users}


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

    user_columns = [
        "id",
        "full_name",
        "email",
        "role",
        "is_active",
        "is_restricted",
        "restriction_reason",
        "restricted_at",
        "restricted_by",
        "created_at",
        "updated_at",
    ]

    with get_cursor(dict_cursor=True) as (_, cursor):
        _fetch_record_by_id(cursor, "users", user_id, user_columns)
        existing = _get_columns(cursor, "users")

        set_parts = []
        params: list[Any] = []

        if "is_active" in existing:
            set_parts.append("is_active = FALSE")
        if "is_restricted" in existing:
            set_parts.append("is_restricted = TRUE")
        if "restriction_reason" in existing:
            set_parts.append("restriction_reason = %s")
            params.append(restriction_reason)
        if "restricted_at" in existing:
            set_parts.append("restricted_at = NOW()")
        if "restricted_by" in existing:
            set_parts.append("restricted_by = %s")
            params.append(admin_user["id"])
        if "updated_at" in existing:
            set_parts.append("updated_at = NOW()")

        if not set_parts:
            raise HTTPException(status_code=500, detail="users table does not support restriction fields")

        return_columns = [column for column in user_columns if column in existing]
        params.append(user_id)

        cursor.execute(
            f"""
            UPDATE users
            SET {', '.join(set_parts)}
            WHERE id = %s
            RETURNING {', '.join(return_columns)};
            """,
            tuple(params),
        )
        updated_user = cursor.fetchone()

    return {"message": "User restricted successfully", "user": dict(updated_user)}


@router.patch("/users/{user_id}/reactivate")
def reactivate_user(user_id: int, _: dict = Depends(require_admin)):
    user_columns = [
        "id",
        "full_name",
        "email",
        "role",
        "is_active",
        "is_restricted",
        "restriction_reason",
        "restricted_at",
        "restricted_by",
        "created_at",
        "updated_at",
    ]

    with get_cursor(dict_cursor=True) as (_, cursor):
        _fetch_record_by_id(cursor, "users", user_id, user_columns)
        existing = _get_columns(cursor, "users")

        set_parts = []
        if "is_active" in existing:
            set_parts.append("is_active = TRUE")
        if "is_restricted" in existing:
            set_parts.append("is_restricted = FALSE")
        if "restriction_reason" in existing:
            set_parts.append("restriction_reason = NULL")
        if "restricted_at" in existing:
            set_parts.append("restricted_at = NULL")
        if "restricted_by" in existing:
            set_parts.append("restricted_by = NULL")
        if "updated_at" in existing:
            set_parts.append("updated_at = NOW()")

        if not set_parts:
            raise HTTPException(status_code=500, detail="users table does not support reactivation fields")

        return_columns = [column for column in user_columns if column in existing]

        cursor.execute(
            f"""
            UPDATE users
            SET {', '.join(set_parts)}
            WHERE id = %s
            RETURNING {', '.join(return_columns)};
            """,
            (user_id,),
        )
        updated_user = cursor.fetchone()

    return {"message": "User reactivated successfully", "user": dict(updated_user)}


@router.get("/leases")
def get_admin_leases(_: dict = Depends(require_admin)):
    lease_columns = [
        "id",
        "owner_name",
        "contact_number",
        "barangay",
        "soil_type",
        "area_hectares",
        "price",
        "description",
        "status",
        "created_at",
        "updated_at",
        "user_id",
        "is_hidden",
        "is_flagged",
        "flag_reason",
        "moderated_by",
        "moderated_at",
    ]
    with get_cursor(dict_cursor=True) as (_, cursor):
        leases = _fetch_table_rows(cursor, "land_leases", lease_columns)
    return {"leases": leases}


@router.patch("/leases/{lease_id}/hide")
def hide_lease(lease_id: int, admin_user: dict = Depends(require_admin)):
    lease_columns = [
        "id",
        "owner_name",
        "contact_number",
        "barangay",
        "soil_type",
        "area_hectares",
        "price",
        "description",
        "status",
        "created_at",
        "updated_at",
        "user_id",
        "is_hidden",
        "is_flagged",
        "flag_reason",
        "moderated_by",
        "moderated_at",
    ]

    with get_cursor(dict_cursor=True) as (_, cursor):
        _fetch_record_by_id(cursor, "land_leases", lease_id, lease_columns)
        existing = _get_columns(cursor, "land_leases")

        set_parts = []
        params: list[Any] = []

        if "status" in existing:
            set_parts.append("status = 'hidden'")
        if "is_hidden" in existing:
            set_parts.append("is_hidden = TRUE")
        if "moderated_by" in existing:
            set_parts.append("moderated_by = %s")
            params.append(admin_user["id"])
        if "moderated_at" in existing:
            set_parts.append("moderated_at = NOW()")
        if "updated_at" in existing:
            set_parts.append("updated_at = NOW()")

        if not set_parts:
            raise HTTPException(status_code=500, detail="land_leases table does not support hide fields")

        return_columns = [column for column in lease_columns if column in existing]
        params.append(lease_id)

        cursor.execute(
            f"""
            UPDATE land_leases
            SET {', '.join(set_parts)}
            WHERE id = %s
            RETURNING {', '.join(return_columns)};
            """,
            tuple(params),
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

    lease_columns = [
        "id",
        "owner_name",
        "contact_number",
        "barangay",
        "soil_type",
        "area_hectares",
        "price",
        "description",
        "status",
        "created_at",
        "updated_at",
        "user_id",
        "is_hidden",
        "is_flagged",
        "flag_reason",
        "moderated_by",
        "moderated_at",
    ]

    with get_cursor(dict_cursor=True) as (_, cursor):
        _fetch_record_by_id(cursor, "land_leases", lease_id, lease_columns)
        existing = _get_columns(cursor, "land_leases")

        set_parts = []
        params: list[Any] = []

        if "status" in existing:
            set_parts.append("status = 'flagged'")
        if "is_flagged" in existing:
            set_parts.append("is_flagged = TRUE")
        if "flag_reason" in existing:
            set_parts.append("flag_reason = %s")
            params.append(flag_reason)
        if "moderated_by" in existing:
            set_parts.append("moderated_by = %s")
            params.append(admin_user["id"])
        if "moderated_at" in existing:
            set_parts.append("moderated_at = NOW()")
        if "updated_at" in existing:
            set_parts.append("updated_at = NOW()")

        if not set_parts:
            raise HTTPException(status_code=500, detail="land_leases table does not support flag fields")

        return_columns = [column for column in lease_columns if column in existing]
        params.append(lease_id)

        cursor.execute(
            f"""
            UPDATE land_leases
            SET {', '.join(set_parts)}
            WHERE id = %s
            RETURNING {', '.join(return_columns)};
            """,
            tuple(params),
        )
        updated_lease = cursor.fetchone()

    return {"message": "Lease flagged successfully", "lease": dict(updated_lease)}


@router.patch("/leases/{lease_id}/restore")
def restore_lease(lease_id: int, admin_user: dict = Depends(require_admin)):
    lease_columns = [
        "id",
        "owner_name",
        "contact_number",
        "barangay",
        "soil_type",
        "area_hectares",
        "price",
        "description",
        "status",
        "created_at",
        "updated_at",
        "user_id",
        "is_hidden",
        "is_flagged",
        "flag_reason",
        "moderated_by",
        "moderated_at",
    ]

    with get_cursor(dict_cursor=True) as (_, cursor):
        _fetch_record_by_id(cursor, "land_leases", lease_id, lease_columns)
        existing = _get_columns(cursor, "land_leases")

        set_parts = []
        params: list[Any] = []

        if "status" in existing:
            set_parts.append("status = 'active'")
        if "is_hidden" in existing:
            set_parts.append("is_hidden = FALSE")
        if "is_flagged" in existing:
            set_parts.append("is_flagged = FALSE")
        if "flag_reason" in existing:
            set_parts.append("flag_reason = NULL")
        if "moderated_by" in existing:
            set_parts.append("moderated_by = %s")
            params.append(admin_user["id"])
        if "moderated_at" in existing:
            set_parts.append("moderated_at = NOW()")
        if "updated_at" in existing:
            set_parts.append("updated_at = NOW()")

        if not set_parts:
            raise HTTPException(status_code=500, detail="land_leases table does not support restore fields")

        return_columns = [column for column in lease_columns if column in existing]
        params.append(lease_id)

        cursor.execute(
            f"""
            UPDATE land_leases
            SET {', '.join(set_parts)}
            WHERE id = %s
            RETURNING {', '.join(return_columns)};
            """,
            tuple(params),
        )
        updated_lease = cursor.fetchone()

    return {"message": "Lease restored successfully", "lease": dict(updated_lease)}


@router.get("/productivity")
def get_admin_productivity(_: dict = Depends(require_admin)):
    productivity_columns = [
        "id",
        "user_id",
        "soil_type",
        "crop_name",
        "area_hectares",
        "yield_amount",
        "notes",
        "status",
        "reviewed_by",
        "reviewed_at",
        "created_at",
        "updated_at",
    ]
    with get_cursor(dict_cursor=True) as (_, cursor):
        records = _fetch_table_rows(cursor, "productivity_records", productivity_columns)
    return {"productivity_records": records}


@router.get("/soil-analysis-logs")
def get_admin_soil_analysis_logs(_: dict = Depends(require_admin)):
    log_columns = [
        "id",
        "user_id",
        "lat",
        "lng",
        "soil_type",
        "soil_name",
        "barangay",
        "created_at",
        "predicted_soil_type",
        "confidence",
        "estimated_productivity_level",
        "fertilizer_recommendation",
        "soil_management_advice",
        "crop_recommendations",
        "original_file_name",
        "image_path",
        "updated_at",
    ]
    with get_cursor(dict_cursor=True) as (_, cursor):
        logs = _fetch_table_rows(cursor, "soil_analysis_logs", log_columns)
    return {"soil_analysis_logs": logs}