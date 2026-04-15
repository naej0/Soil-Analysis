from db import get_cursor
from services.recommendation_service import normalize_soil_type


def create_lease(payload) -> dict:
    canonical_soil_type = normalize_soil_type(payload.soil_type)

    with get_cursor() as (_, cursor):
        cursor.execute(
            """
            INSERT INTO land_leases (
                owner_name,
                contact_number,
                barangay,
                soil_type,
                area_hectares,
                price,
                description
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            RETURNING id, owner_name, contact_number, barangay, soil_type,
                      area_hectares, price, description, status, created_at;
            """,
            (
                payload.owner_name,
                payload.contact_number,
                payload.barangay,
                canonical_soil_type,
                payload.area_hectares,
                payload.price,
                payload.description,
            ),
        )
        lease = cursor.fetchone()

    return {
        "id": lease[0],
        "owner_name": lease[1],
        "contact_number": lease[2],
        "barangay": lease[3],
        "soil_type": lease[4],
        "area_hectares": float(lease[5]),
        "price": float(lease[6]),
        "description": lease[7],
        "status": lease[8],
        "created_at": lease[9],
    }


def list_leases() -> list[dict]:
    with get_cursor() as (_, cursor):
        cursor.execute(
            """
            SELECT id, owner_name, contact_number, barangay, soil_type,
                   area_hectares, price, description, status, created_at
            FROM land_leases
            ORDER BY created_at DESC;
            """
        )
        rows = cursor.fetchall()

    return [
        {
            "id": row[0],
            "owner_name": row[1],
            "contact_number": row[2],
            "barangay": row[3],
            "soil_type": row[4],
            "area_hectares": float(row[5]),
            "price": float(row[6]),
            "description": row[7],
            "status": row[8],
            "created_at": row[9],
        }
        for row in rows
    ]
