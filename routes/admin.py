from functools import lru_cache
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from pydantic import BaseModel

from db import get_cursor, get_db_connection

router = APIRouter(prefix="/admin", tags=["Admin"])


class RestrictRequest(BaseModel):
    admin_id: int
    violation_type: str = "policy_violation"
    reason: str


class ReactivateRequest(BaseModel):
    admin_id: int


class LeaseModerationRequest(BaseModel):
    admin_id: int
    reason: Optional[str] = None


@lru_cache(maxsize=64)
def _get_columns(table_name: str) -> set[str]:
    try:
        with get_cursor() as cursor:
            cursor.execute(
                """
                SELECT column_name
                FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = %s
                """,
                (table_name,),
            )
            rows = cursor.fetchall() or []
    except Exception:
        return set()

    columns: set[str] = set()
    for row in rows:
        if isinstance(row, dict):
            columns.add(str(row.get("column_name")))
        else:
            columns.add(str(row[0]))
    return columns


def _table_exists(table_name: str) -> bool:
    return bool(_get_columns(table_name))


def _row_to_dict(cursor: Any, row: Any) -> Optional[Dict[str, Any]]:
    if row is None:
        return None
    if isinstance(row, dict):
        return dict(row)
    columns = [desc[0] for desc in cursor.description]
    return dict(zip(columns, row))


def _rows_to_dicts(cursor: Any, rows: List[Any]) -> List[Dict[str, Any]]:
    if not rows:
        return []
    if isinstance(rows[0], dict):
        return [dict(row) for row in rows]
    columns = [desc[0] for desc in cursor.description]
    return [dict(zip(columns, row)) for row in rows]


def _fetch_one(query: str, params: tuple = ()) -> Optional[Dict[str, Any]]:
    with get_cursor() as cursor:
        cursor.execute(query, params)
        return _row_to_dict(cursor, cursor.fetchone())


def _fetch_all(query: str, params: tuple = ()) -> List[Dict[str, Any]]:
    with get_cursor() as cursor:
        cursor.execute(query, params)
        return _rows_to_dicts(cursor, cursor.fetchall() or [])


def _pick(columns: set[str], candidates: List[str]) -> Optional[str]:
    for candidate in candidates:
        if candidate in columns:
            return candidate
    return None


def _expr(
    columns: set[str],
    candidates: List[str],
    alias: str,
    default_sql: str = "NULL",
    coalesce_sql: Optional[str] = None,
) -> str:
    column = _pick(columns, candidates)
    if column:
        if coalesce_sql is not None:
            return f"COALESCE({column}, {coalesce_sql}) AS {alias}"
        return f"{column} AS {alias}"
    return f"{default_sql} AS {alias}"


def _location_expr(columns: set[str]) -> str:
    direct = _pick(columns, ["location", "address"])
    if direct:
        return f"{direct} AS location"

    parts = [
        column
        for column in ["barangay", "municipality", "city", "province"]
        if column in columns
    ]
    if parts:
        joined = ", ".join(parts)
        return f"NULLIF(CONCAT_WS(', ', {joined}), '') AS location"

    return "NULL AS location"


def _safe_count(table_name: str, where_sql: Optional[str] = None, params: tuple = ()) -> int:
    if not _table_exists(table_name):
        return 0

    query = f"SELECT COUNT(*) AS count FROM {table_name}"
    if where_sql:
        query += f" WHERE {where_sql}"

    row = _fetch_one(query, params)
    return int((row or {}).get("count", 0) or 0)


def get_admin_user_id(
    admin_user_id: Optional[int] = Query(None),
    x_admin_user_id: Optional[str] = Header(None),
) -> int:
    if admin_user_id is not None:
        return admin_user_id

    if x_admin_user_id:
        try:
            return int(x_admin_user_id)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail="Invalid X-Admin-User-Id header.") from exc

    raise HTTPException(status_code=400, detail="Admin user ID is required.")


def require_admin(admin_user_id: int = Depends(get_admin_user_id)) -> int:
    user_columns = _get_columns("users")

    if not user_columns or "id" not in user_columns:
        return admin_user_id

    if "is_admin" in user_columns:
        query = "SELECT id FROM users WHERE id = %s AND COALESCE(is_admin, FALSE) = TRUE"
        row = _fetch_one(query, (admin_user_id,))
        if not row:
            raise HTTPException(status_code=403, detail="Admin access required.")
        return admin_user_id

    if "role" in user_columns:
        query = """
            SELECT id
            FROM users
            WHERE id = %s
              AND LOWER(COALESCE(role, '')) IN ('admin', 'administrator')
        """
        row = _fetch_one(query, (admin_user_id,))
        if not row:
            raise HTTPException(status_code=403, detail="Admin access required.")
        return admin_user_id

    row = _fetch_one("SELECT id FROM users WHERE id = %s", (admin_user_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Admin user not found.")

    return admin_user_id


@router.get("/dashboard")
def get_admin_dashboard(_: dict = Depends(require_admin)):
    with get_cursor(dict_cursor=True) as (_, cursor):
        cursor.execute(
            """
            SELECT
                (SELECT COUNT(*) FROM users) AS total_users,
                (SELECT COUNT(*) FROM users WHERE COALESCE(is_active, TRUE) IS TRUE) AS active_users,
                (SELECT COUNT(*) FROM users WHERE COALESCE(is_restricted, FALSE) IS TRUE) AS restricted_users,
                (SELECT COUNT(*) FROM land_leases) AS total_lease_listings,
                (SELECT COUNT(*) FROM land_leases WHERE LOWER(COALESCE(status, 'active')) = 'active') AS active_lease_listings,
                (SELECT COUNT(*) FROM land_leases WHERE COALESCE(is_flagged, FALSE) IS TRUE OR LOWER(COALESCE(status, '')) = 'flagged') AS flagged_lease_listings,
                (SELECT COUNT(*) FROM productivity_records) AS total_productivity_records,
                (SELECT COUNT(*) FROM soil_analysis_logs) AS total_soil_analyses;
            """
        )
        summary = dict(cursor.fetchone())

        cursor.execute(
            """
            SELECT soil_type, COUNT(*) AS count
            FROM soil_analysis_logs
            WHERE soil_type IS NOT NULL AND TRIM(soil_type) <> ''
            GROUP BY soil_type
            ORDER BY count DESC, soil_type ASC
            LIMIT 5;
            """
        )
        common_rows = cursor.fetchall()

    return {
        "total_users": summary["total_users"],
        "active_users": summary["active_users"],
        "restricted_users": summary["restricted_users"],
        "total_lease_listings": summary["total_lease_listings"],
        "active_lease_listings": summary["active_lease_listings"],
        "flagged_lease_listings": summary["flagged_lease_listings"],
        "total_productivity_records": summary["total_productivity_records"],
        "total_soil_analyses": summary["total_soil_analyses"],
        "common_soil_types": [
            {
                "soil_type": row["soil_type"],
                "count": row["count"],
            }
            for row in common_rows
        ],
    }


@router.get("/users")
def get_users(admin_user_id: int = Depends(require_admin)):
    user_columns = _get_columns("users")
    if not user_columns:
        return {"users": []}

    if "id" not in user_columns:
        raise HTTPException(status_code=500, detail="users.id column is missing.")

    order_column = "created_at" if "created_at" in user_columns else "id"

    query = f"""
        SELECT
            id,
            {_expr(user_columns, ['email'], 'email')},
            {_expr(user_columns, ['first_name', 'firstname', 'given_name'], 'first_name')},
            {_expr(user_columns, ['last_name', 'lastname', 'surname', 'family_name'], 'last_name')},
            {_expr(user_columns, ['profile_picture', 'profile_image', 'avatar', 'image_path'], 'profile_picture')},
            {_expr(user_columns, ['is_active'], 'is_active', 'TRUE', 'TRUE')},
            {_expr(user_columns, ['is_restricted'], 'is_restricted', 'FALSE', 'FALSE')},
            {_expr(user_columns, ['created_at'], 'created_at')}
        FROM users
        ORDER BY {order_column} DESC NULLS LAST, id DESC
    """

    return {"users": _fetch_all(query)}


@router.patch("/users/{user_id}/restrict")
def restrict_user(
    user_id: int,
    request: RestrictRequest,
    admin_user_id: int = Depends(require_admin),
):
    if request.admin_id != admin_user_id:
        raise HTTPException(status_code=403, detail="Admin mismatch.")

    user_columns = _get_columns("users")
    if not user_columns:
        raise HTTPException(status_code=500, detail="users table not found.")

    updates: List[str] = []

    if "is_restricted" in user_columns:
        updates.append("is_restricted = TRUE")
    if "is_active" in user_columns:
        updates.append("is_active = FALSE")
    if "updated_at" in user_columns:
        updates.append("updated_at = NOW()")

    if not updates:
        raise HTTPException(
            status_code=500,
            detail="No supported restriction columns found on users table.",
        )

    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute(f"UPDATE users SET {', '.join(updates)} WHERE id = %s", (user_id,))
            if cursor.rowcount == 0:
                raise HTTPException(status_code=404, detail="User not found.")

            violation_columns = _get_columns("user_violations")
            if violation_columns:
                insert_columns: List[str] = ["user_id"]
                insert_values: List[str] = ["%s"]
                insert_params: List[Any] = [user_id]

                optional_values = {
                    "admin_id": admin_user_id,
                    "violation_type": request.violation_type,
                    "reason": request.reason,
                    "status": "restricted" if "status" in violation_columns else None,
                    "created_at": "NOW()",
                    "updated_at": "NOW()",
                }

                for column, value in optional_values.items():
                    if column not in violation_columns or value is None:
                        continue
                    insert_columns.append(column)
                    if value == "NOW()":
                        insert_values.append("NOW()")
                    else:
                        insert_values.append("%s")
                        insert_params.append(value)

                cursor.execute(
                    f"""
                    INSERT INTO user_violations ({', '.join(insert_columns)})
                    VALUES ({', '.join(insert_values)})
                    """,
                    tuple(insert_params),
                )

        conn.commit()
    except HTTPException:
        conn.rollback()
        raise
    except Exception as exc:
        conn.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to restrict user: {exc}") from exc
    finally:
        conn.close()

    return {"message": "User restricted successfully."}


@router.patch("/users/{user_id}/reactivate")
def reactivate_user(
    user_id: int,
    request: ReactivateRequest,
    admin_user_id: int = Depends(require_admin),
):
    if request.admin_id != admin_user_id:
        raise HTTPException(status_code=403, detail="Admin mismatch.")

    user_columns = _get_columns("users")
    if not user_columns:
        raise HTTPException(status_code=500, detail="users table not found.")

    updates: List[str] = []
    if "is_restricted" in user_columns:
        updates.append("is_restricted = FALSE")
    if "is_active" in user_columns:
        updates.append("is_active = TRUE")
    if "updated_at" in user_columns:
        updates.append("updated_at = NOW()")

    if not updates:
        raise HTTPException(
            status_code=500,
            detail="No supported reactivation columns found on users table.",
        )

    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute(f"UPDATE users SET {', '.join(updates)} WHERE id = %s", (user_id,))
            if cursor.rowcount == 0:
                raise HTTPException(status_code=404, detail="User not found.")

            violation_columns = _get_columns("user_violations")
            if violation_columns and "user_id" in violation_columns:
                violation_updates: List[str] = []
                params: List[Any] = []

                if "status" in violation_columns:
                    violation_updates.append("status = %s")
                    params.append("resolved")
                if "resolved_at" in violation_columns:
                    violation_updates.append("resolved_at = NOW()")
                if "updated_at" in violation_columns:
                    violation_updates.append("updated_at = NOW()")

                if violation_updates:
                    params.append(user_id)
                    cursor.execute(
                        f"""
                        UPDATE user_violations
                        SET {', '.join(violation_updates)}
                        WHERE user_id = %s
                        """,
                        tuple(params),
                    )

        conn.commit()
    except HTTPException:
        conn.rollback()
        raise
    except Exception as exc:
        conn.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to reactivate user: {exc}") from exc
    finally:
        conn.close()

    return {"message": "User reactivated successfully."}


@router.get("/leases")
def get_leases(admin_user_id: int = Depends(require_admin)):
    lease_columns = _get_columns("land_leases")
    if not lease_columns:
        return {"leases": []}

    if "id" not in lease_columns:
        raise HTTPException(status_code=500, detail="land_leases.id column is missing.")

    order_column = "created_at" if "created_at" in lease_columns else "id"

    query = f"""
        SELECT
            id,
            {_expr(lease_columns, ['user_id'], 'user_id')},
            {_expr(lease_columns, ['title', 'lease_title', 'listing_title', 'name', 'crop_name'], 'title')},
            {_location_expr(lease_columns)},
            {_expr(lease_columns, ['contact_person', 'owner_name', 'lessor_name'], 'contact_person')},
            {_expr(lease_columns, ['contact_number', 'phone_number', 'mobile_number'], 'contact_number')},
            {_expr(lease_columns, ['is_active'], 'is_active', 'TRUE', 'TRUE')},
            {_expr(lease_columns, ['hidden_by_admin'], 'hidden_by_admin', 'FALSE', 'FALSE')},
            {_expr(lease_columns, ['is_flagged'], 'is_flagged', 'FALSE', 'FALSE')},
            {_expr(lease_columns, ['status'], 'status')},
            {_expr(lease_columns, ['created_at'], 'created_at')}
        FROM land_leases
        ORDER BY {order_column} DESC NULLS LAST, id DESC
    """

    return {"leases": _fetch_all(query)}


@router.patch("/leases/{lease_id}/hide")
def hide_lease(
    lease_id: int,
    request: LeaseModerationRequest,
    admin_user_id: int = Depends(require_admin),
):
    if request.admin_id != admin_user_id:
        raise HTTPException(status_code=403, detail="Admin mismatch.")

    lease_columns = _get_columns("land_leases")
    if not lease_columns:
        raise HTTPException(status_code=500, detail="land_leases table not found.")

    updates: List[str] = []
    if "hidden_by_admin" in lease_columns:
        updates.append("hidden_by_admin = TRUE")
    if "is_active" in lease_columns:
        updates.append("is_active = FALSE")
    if "status" in lease_columns:
        updates.append("status = 'hidden'")
    if "updated_at" in lease_columns:
        updates.append("updated_at = NOW()")

    if not updates:
        raise HTTPException(
            status_code=500,
            detail="No supported moderation columns found on land_leases table.",
        )

    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute(f"UPDATE land_leases SET {', '.join(updates)} WHERE id = %s", (lease_id,))
            if cursor.rowcount == 0:
                raise HTTPException(status_code=404, detail="Lease not found.")
        conn.commit()
    except HTTPException:
        conn.rollback()
        raise
    except Exception as exc:
        conn.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to hide lease: {exc}") from exc
    finally:
        conn.close()

    return {"message": "Lease hidden successfully."}


@router.patch("/leases/{lease_id}/flag")
def flag_lease(
    lease_id: int,
    request: LeaseModerationRequest,
    admin_user_id: int = Depends(require_admin),
):
    if request.admin_id != admin_user_id:
        raise HTTPException(status_code=403, detail="Admin mismatch.")

    lease_columns = _get_columns("land_leases")
    if not lease_columns:
        raise HTTPException(status_code=500, detail="land_leases table not found.")

    updates: List[str] = []
    if "is_flagged" in lease_columns:
        updates.append("is_flagged = TRUE")
    if "status" in lease_columns:
        updates.append("status = 'flagged'")
    if "updated_at" in lease_columns:
        updates.append("updated_at = NOW()")

    if not updates:
        raise HTTPException(
            status_code=500,
            detail="No supported moderation columns found on land_leases table.",
        )

    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute(f"UPDATE land_leases SET {', '.join(updates)} WHERE id = %s", (lease_id,))
            if cursor.rowcount == 0:
                raise HTTPException(status_code=404, detail="Lease not found.")
        conn.commit()
    except HTTPException:
        conn.rollback()
        raise
    except Exception as exc:
        conn.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to flag lease: {exc}") from exc
    finally:
        conn.close()

    return {"message": "Lease flagged successfully."}


@router.patch("/leases/{lease_id}/restore")
def restore_lease(
    lease_id: int,
    request: LeaseModerationRequest,
    admin_user_id: int = Depends(require_admin),
):
    if request.admin_id != admin_user_id:
        raise HTTPException(status_code=403, detail="Admin mismatch.")

    lease_columns = _get_columns("land_leases")
    if not lease_columns:
        raise HTTPException(status_code=500, detail="land_leases table not found.")

    updates: List[str] = []
    if "hidden_by_admin" in lease_columns:
        updates.append("hidden_by_admin = FALSE")
    if "is_flagged" in lease_columns:
        updates.append("is_flagged = FALSE")
    if "is_active" in lease_columns:
        updates.append("is_active = TRUE")
    if "status" in lease_columns:
        updates.append("status = 'active'")
    if "updated_at" in lease_columns:
        updates.append("updated_at = NOW()")

    if not updates:
        raise HTTPException(
            status_code=500,
            detail="No supported moderation columns found on land_leases table.",
        )

    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute(f"UPDATE land_leases SET {', '.join(updates)} WHERE id = %s", (lease_id,))
            if cursor.rowcount == 0:
                raise HTTPException(status_code=404, detail="Lease not found.")
        conn.commit()
    except HTTPException:
        conn.rollback()
        raise
    except Exception as exc:
        conn.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to restore lease: {exc}") from exc
    finally:
        conn.close()

    return {"message": "Lease restored successfully."}


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

    return {"productivity_records": _rows_to_dicts(records)}


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

    return {"soil_analysis_logs": _rows_to_dicts(logs)}