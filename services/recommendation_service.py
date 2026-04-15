from fastapi import HTTPException

from config import SUPPORTED_SOIL_TYPES
from db import get_cursor


def normalize_soil_type(soil_type: str) -> str:
    normalized_input = soil_type.strip().lower()
    for supported in SUPPORTED_SOIL_TYPES:
        if supported.lower() == normalized_input:
            return supported
    raise HTTPException(
        status_code=400,
        detail={
            "message": "Unsupported soil type",
            "supported_soil_types": list(SUPPORTED_SOIL_TYPES),
        },
    )


def get_recommendations_by_soil_type(soil_type: str) -> list[dict]:
    canonical_soil_type = normalize_soil_type(soil_type)

    with get_cursor() as (_, cursor):
        cursor.execute(
            """
            SELECT crop_name, suitability, notes
            FROM crop_recommendations
            WHERE soil_type = %s
            ORDER BY
              CASE suitability
                WHEN 'High' THEN 1
                WHEN 'Medium' THEN 2
                WHEN 'Low' THEN 3
                ELSE 4
              END,
              crop_name;
            """,
            (canonical_soil_type,),
        )
        rows = cursor.fetchall()

    return [
        {
            "crop_name": row[0],
            "suitability": row[1],
            "notes": row[2],
        }
        for row in rows
    ]
