from fastapi import HTTPException

from db import get_cursor
from services.recommendation_service import normalize_soil_type


def create_productivity_record(payload) -> dict:
    canonical_soil_type = normalize_soil_type(payload.soil_type)

    with get_cursor() as (_, cursor):
        cursor.execute("SELECT id FROM users WHERE id = %s;", (payload.user_id,))
        user_exists = cursor.fetchone()
        if not user_exists:
            raise HTTPException(status_code=404, detail="User not found")

        cursor.execute(
            """
            INSERT INTO productivity_records (
                user_id,
                soil_type,
                crop_name,
                area_hectares,
                yield_amount,
                notes
            )
            VALUES (%s, %s, %s, %s, %s, %s)
            RETURNING id, user_id, soil_type, crop_name,
                      area_hectares, yield_amount, notes, created_at;
            """,
            (
                payload.user_id,
                canonical_soil_type,
                payload.crop_name,
                payload.area_hectares,
                payload.yield_amount,
                payload.notes,
            ),
        )
        record = cursor.fetchone()

    return {
        "id": record[0],
        "user_id": record[1],
        "soil_type": record[2],
        "crop_name": record[3],
        "area_hectares": float(record[4]),
        "yield_amount": float(record[5]),
        "notes": record[6],
        "created_at": record[7],
    }


def list_productivity_records(user_id: int) -> list[dict]:
    with get_cursor() as (_, cursor):
        cursor.execute("SELECT id FROM users WHERE id = %s;", (user_id,))
        user_exists = cursor.fetchone()
        if not user_exists:
            raise HTTPException(status_code=404, detail="User not found")

        cursor.execute(
            """
            SELECT id, user_id, soil_type, crop_name, area_hectares,
                   yield_amount, notes, created_at
            FROM productivity_records
            WHERE user_id = %s
            ORDER BY created_at DESC;
            """,
            (user_id,),
        )
        rows = cursor.fetchall()

    return [
        {
            "id": row[0],
            "user_id": row[1],
            "soil_type": row[2],
            "crop_name": row[3],
            "area_hectares": float(row[4]),
            "yield_amount": float(row[5]),
            "notes": row[6],
            "created_at": row[7],
        }
        for row in rows
    ]
