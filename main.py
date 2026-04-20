from fastapi import FastAPI, HTTPException, Query
from typing import Optional, List, Dict, Any
from fastapi.middleware.cors import CORSMiddleware
import os
import psycopg2
from psycopg2.extras import RealDictCursor
import requests
from routes.admin import router as admin_router
from routes.ai import router as ai_router
from routes.assistant import router as assistant_router

app = FastAPI()
app.include_router(admin_router)
app.include_router(ai_router)
app.include_router(assistant_router)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def get_connection():
    return psycopg2.connect(
        dbname="postgres",
        user="postgres",
        password="SoilCrop123",
        host="localhost",
        port="5432"
    )

def get_db_connection():
    return psycopg2.connect(
        os.getenv("DATABASE_URL"),
        cursor_factory=RealDictCursor
    )

@app.get("/")
def home():
    return {"message": "Soil API is working"}


@app.get("/soil/by-location")
def get_soil(lat: float, lng: float):
    conn = None
    cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor()

        query = """
        SELECT soil_type, soil_name, barangay
        FROM soil_polygons
        WHERE ST_Contains(
            geom,
            ST_SetSRID(ST_Point(%s, %s), 4326)
        )
        LIMIT 1;
        """

        cursor.execute(query, (lng, lat))
        result = cursor.fetchone()

        if result:
            return {
                "soil_type": result[0],
                "soil_name": result[1],
                "barangay": result[2]
            }

        return {"message": "No soil data found for this location"}

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.get("/recommendations/by-soil")
def get_recommendations(soil_type: str):
    conn = None
    cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor()

        query = """
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
        """

        cursor.execute(query, (soil_type,))
        rows = cursor.fetchall()

        return {
            "soil_type": soil_type,
            "recommendations": [
                {
                    "crop_name": row[0],
                    "suitability": row[1],
                    "notes": row[2]
                }
                for row in rows
            ]
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

def fetch_soil_productivity_basis(cursor, soil_type: str):
    query = """
    SELECT
        st.id AS soil_type_id,
        st.soil_type_name,
        st.description AS soil_description,
        pl.id AS productivity_level_id,
        pl.productivity_level,
        pl.display_order,
        spb.nutrient_retention,
        spb.drainage_condition,
        spb.compaction_risk,
        spb.water_holding_capacity,
        spb.basis_explanation,
        spb.source_title,
        spb.source_organization,
        spb.source_year,
        spb.source_link
    FROM soil_productivity_basis spb
    INNER JOIN soil_types st
        ON st.id = spb.soil_type_id
    INNER JOIN productivity_levels pl
        ON pl.id = spb.productivity_level_id
    WHERE LOWER(st.soil_type_name) = LOWER(%s)
      AND spb.is_active = TRUE
    ORDER BY pl.display_order ASC
    LIMIT 1;
    """
    cursor.execute(query, (soil_type,))
    return cursor.fetchone()



def fetch_fertilizer_catalog(cursor):
    query = """
    SELECT
        id,
        fertilizer_code,
        common_name,
        display_name,
        aliases,
        n_value,
        p_value,
        k_value,
        category,
        note
    FROM fertilizers
    WHERE is_active = TRUE
    ORDER BY fertilizer_code ASC;
    """
    cursor.execute(query)
    return cursor.fetchall()


def fetch_fertilizer_recommendations(cursor, soil_type: str, productivity_level: Optional[str] = None, crop_name: Optional[str] = None):
    query = """
    SELECT
        st.soil_type_name,
        c.crop_name,
        pl.productivity_level,
        f.id AS fertilizer_id,
        f.fertilizer_code,
        f.common_name,
        f.display_name,
        f.aliases,
        f.n_value,
        f.p_value,
        f.k_value,
        f.category,
        f.note,
        frr.priority_order,
        frr.recommendation_role,
        frr.display_label,
        frr.guidance_text,
        frr.application_rate_text,
        frr.application_timing_text,
        frr.reason_basis,
        frr.source_title,
        frr.source_organization,
        frr.source_year,
        frr.source_link
    FROM fertilizer_recommendation_rules frr
    INNER JOIN soil_types st
        ON st.id = frr.soil_type_id
    INNER JOIN crops c
        ON c.id = frr.crop_id
    INNER JOIN productivity_levels pl
        ON pl.id = frr.productivity_level_id
    INNER JOIN fertilizers f
        ON f.id = frr.fertilizer_id
    WHERE LOWER(st.soil_type_name) = LOWER(%s)
      AND frr.is_active = TRUE
      AND f.is_active = TRUE
      AND (%s IS NULL OR LOWER(pl.productivity_level) = LOWER(%s))
      AND (%s IS NULL OR LOWER(c.crop_name) = LOWER(%s))
    ORDER BY
        c.crop_name ASC,
        pl.display_order ASC,
        frr.priority_order ASC,
        f.fertilizer_code ASC;
    """
    cursor.execute(query, (
        soil_type,
        productivity_level, productivity_level,
        crop_name, crop_name
    ))
    return cursor.fetchall()


def fetch_soil_type_row(cursor, soil_type_name: str):
    query = """
    SELECT
        id,
        soil_type_name,
        description
    FROM soil_types
    WHERE LOWER(soil_type_name) = LOWER(%s)
    LIMIT 1;
    """
    cursor.execute(query, (soil_type_name,))
    return cursor.fetchone()


def serialize_productivity_basis_row(row):
    if not row:
        return None

    return {
        "soil_type_id": row["soil_type_id"],
        "soil_type_name": row["soil_type_name"],
        "soil_description": row["soil_description"],
        "productivity_level_id": row["productivity_level_id"],
        "productivity_level": row["productivity_level"],
        "display_order": row["display_order"],
        "nutrient_retention": row["nutrient_retention"],
        "drainage_condition": row["drainage_condition"],
        "compaction_risk": row["compaction_risk"],
        "water_holding_capacity": row["water_holding_capacity"],
        "basis_explanation": row["basis_explanation"],
    }


def serialize_fertilizer_item_row(row):
    fertilizer_id = row.get("fertilizer_id", row.get("id"))
    n_value = row.get("n_value")
    p_value = row.get("p_value")
    k_value = row.get("k_value")

    return {
        "id": fertilizer_id,
        "fertilizer_code": row.get("fertilizer_code"),
        "common_name": row.get("common_name"),
        "display_name": row.get("display_name"),
        "aliases": row.get("aliases"),
        "n_value": float(n_value) if n_value is not None else None,
        "p_value": float(p_value) if p_value is not None else None,
        "k_value": float(k_value) if k_value is not None else None,
        "category": row.get("category"),
        "note": row.get("note"),
    }


def fetch_support_crop_recommendations(cursor, soil_type_name: str, crop_name: Optional[str] = None):
    query = """
    SELECT
        crop_name,
        suitability,
        notes
    FROM crop_recommendations
    WHERE LOWER(soil_type) = LOWER(%s)
      AND (%s IS NULL OR LOWER(crop_name) = LOWER(%s))
    ORDER BY
      CASE suitability
        WHEN 'High' THEN 1
        WHEN 'Medium' THEN 2
        WHEN 'Moderate' THEN 2
        WHEN 'Low' THEN 3
        ELSE 4
      END,
      crop_name ASC;
    """
    cursor.execute(query, (soil_type_name, crop_name, crop_name))
    return [dict(row) for row in cursor.fetchall()]


def fetch_support_fertilizer_recommendations(
    cursor,
    soil_type_name: str,
    productivity_level: Optional[str],
    crop_name: Optional[str] = None,
):
    if not productivity_level:
        return []

    query = """
    SELECT
        frr.id,
        st.soil_type_name,
        pl.productivity_level,
        c.crop_name,
        frr.priority_order,
        frr.recommendation_role,
        frr.display_label,
        frr.guidance_text,
        frr.application_rate_text,
        frr.application_timing_text,
        frr.reason_basis,
        frr.source_title,
        frr.source_organization,
        frr.source_year,
        frr.source_link,
        f.id AS fertilizer_id,
        f.fertilizer_code,
        f.common_name,
        f.display_name,
        f.aliases,
        f.n_value,
        f.p_value,
        f.k_value,
        f.category,
        f.note
    FROM fertilizer_recommendation_rules frr
    JOIN soil_types st
        ON st.id = frr.soil_type_id
    JOIN productivity_levels pl
        ON pl.id = frr.productivity_level_id
    JOIN fertilizers f
        ON f.id = frr.fertilizer_id
    LEFT JOIN crops c
        ON c.id = frr.crop_id
    WHERE LOWER(st.soil_type_name) = LOWER(%s)
      AND pl.productivity_level = %s
      AND frr.is_active = TRUE
      AND f.is_active = TRUE
      AND (
            (%s IS NULL AND frr.crop_id IS NULL)
            OR LOWER(c.crop_name) = LOWER(%s)
            OR frr.crop_id IS NULL
          )
    ORDER BY
      CASE
        WHEN LOWER(c.crop_name) = LOWER(%s) THEN 0
        ELSE 1
      END,
      frr.priority_order ASC;
    """
    cursor.execute(
        query,
        (
            soil_type_name,
            productivity_level,
            crop_name,
            crop_name,
            crop_name,
        ),
    )

    recommendations = []
    for row in cursor.fetchall():
        row_dict = dict(row)
        recommendations.append({
            "id": row_dict["id"],
            "soil_type_name": row_dict["soil_type_name"],
            "productivity_level": row_dict["productivity_level"],
            "crop_name": row_dict["crop_name"],
            "priority_order": row_dict["priority_order"],
            "recommendation_role": row_dict["recommendation_role"],
            "display_label": row_dict["display_label"],
            "guidance_text": row_dict["guidance_text"],
            "application_rate_text": row_dict["application_rate_text"],
            "application_timing_text": row_dict["application_timing_text"],
            "reason_basis": row_dict["reason_basis"],
            "source_title": row_dict["source_title"],
            "source_organization": row_dict["source_organization"],
            "source_year": row_dict["source_year"],
            "source_link": row_dict["source_link"],
            "fertilizer": serialize_fertilizer_item_row(row_dict),
        })

    return recommendations


@app.get("/soil-analysis/details")
def get_soil_analysis_details(
    soil_type: str = Query(..., description="Predicted soil type from the soil analysis module"),
    crop_name: Optional[str] = Query(None, description="Optional crop filter for fertilizer rules")
):
    conn = None
    cursor = None

    try:
        conn = get_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)

        soil_check_query = """
        SELECT
            id,
            soil_type_name,
            description
        FROM soil_types
        WHERE LOWER(soil_type_name) = LOWER(%s)
        LIMIT 1;
        """
        cursor.execute(soil_check_query, (soil_type,))
        soil_row = cursor.fetchone()

        if not soil_row:
            raise HTTPException(
                status_code=404,
                detail=f"Unsupported soil type: {soil_type}"
            )

        productivity_basis = fetch_soil_productivity_basis(cursor, soil_type)
        crop_recommendations = fetch_crop_recommendations_for_soil(cursor, soil_type)

        derived_productivity_level = None
        if productivity_basis:
            derived_productivity_level = productivity_basis["productivity_level"]

        fertilizer_recommendations = fetch_fertilizer_recommendations(
            cursor,
            soil_type=soil_type,
            productivity_level=derived_productivity_level,
            crop_name=crop_name
        )

        fertilizer_catalog = fetch_fertilizer_catalog(cursor)

        return {
            "soil_type": soil_row["soil_type_name"],
            "soil_description": soil_row["description"],
            "productivity_basis": productivity_basis,
            "recommended_crops": crop_recommendations,
            "fertilizer_recommendations": fertilizer_recommendations,
            "fertilizer_catalog": fertilizer_catalog,
            "filters": {
                "crop_name": crop_name,
                "productivity_level": derived_productivity_level
            }
        }

    except HTTPException:
        raise

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.get("/soil-analysis/productivity-basis")
def get_soil_productivity_basis_only(
    soil_type: str = Query(..., description="Predicted soil type from the soil analysis module")
):
    conn = None
    cursor = None

    try:
        conn = get_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)

        productivity_basis = fetch_soil_productivity_basis(cursor, soil_type)

        if not productivity_basis:
            raise HTTPException(
                status_code=404,
                detail=f"No productivity basis found for soil type: {soil_type}"
            )

        return productivity_basis

    except HTTPException:
        raise

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.get("/soil-analysis/fertilizers")
def get_soil_fertilizers(
    soil_type: str = Query(..., description="Predicted soil type from the soil analysis module"),
    crop_name: Optional[str] = Query(None, description="Optional crop filter")
):
    conn = None
    cursor = None

    try:
        conn = get_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)

        productivity_basis = fetch_soil_productivity_basis(cursor, soil_type)
        productivity_level = productivity_basis["productivity_level"] if productivity_basis else None

        fertilizer_recommendations = fetch_fertilizer_recommendations(
            cursor,
            soil_type=soil_type,
            productivity_level=productivity_level,
            crop_name=crop_name
        )

        return {
            "soil_type": soil_type,
            "crop_name": crop_name,
            "productivity_level": productivity_level,
            "fertilizer_recommendations": fertilizer_recommendations
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.get("/soil-analysis/support/{soil_type_name}")
def get_soil_analysis_support_by_soil_type(
    soil_type_name: str,
    crop_name: Optional[str] = Query(None, description="Optional crop filter, e.g. Rice")
):
    conn = None
    cursor = None

    try:
        conn = get_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)

        soil_row = fetch_soil_type_row(cursor, soil_type_name)
        if not soil_row:
            raise HTTPException(
                status_code=404,
                detail=f"Soil type '{soil_type_name}' not found."
            )

        resolved_soil_type_name = soil_row["soil_type_name"]
        productivity_basis_row = fetch_soil_productivity_basis(cursor, resolved_soil_type_name)
        productivity_basis = serialize_productivity_basis_row(productivity_basis_row)
        productivity_level = (
            productivity_basis["productivity_level"]
            if productivity_basis
            else None
        )

        recommended_crops = fetch_support_crop_recommendations(
            cursor,
            resolved_soil_type_name,
            crop_name=crop_name,
        )
        fertilizer_recommendations = fetch_support_fertilizer_recommendations(
            cursor,
            resolved_soil_type_name,
            productivity_level=productivity_level,
            crop_name=crop_name,
        )
        fertilizer_catalog = [
            serialize_fertilizer_item_row(row)
            for row in fetch_fertilizer_catalog(cursor)
        ]

        return {
            "soil_type": resolved_soil_type_name,
            "soil_description": soil_row["description"],
            "productivity_basis": productivity_basis,
            "recommended_crops": recommended_crops,
            "fertilizer_recommendations": fertilizer_recommendations,
            "fertilizer_catalog": fertilizer_catalog,
            "filters": {
                "crop_name": crop_name,
                "productivity_level": productivity_level,
            }
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

@app.get("/analysis/by-location")
def analyze_by_location(lat: float, lng: float):
    conn = None
    cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor()

        soil_query = """
        SELECT soil_type, soil_name, barangay
        FROM soil_polygons
        WHERE ST_Contains(
            geom,
            ST_SetSRID(ST_Point(%s, %s), 4326)
        )
        LIMIT 1;
        """

        cursor.execute(soil_query, (lng, lat))
        soil_result = cursor.fetchone()

        if not soil_result:
            return {"message": "No soil data found for this location"}

        soil_type = soil_result[0]
        soil_name = soil_result[1]
        barangay = soil_result[2]

        reco_query = """
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
        """

        cursor.execute(reco_query, (soil_type,))
        reco_rows = cursor.fetchall()

        return {
            "location": {
                "lat": lat,
                "lng": lng,
                "barangay": barangay
            },
            "soil": {
                "soil_type": soil_type,
                "soil_name": soil_name
            },
            "recommendations": [
                {
                    "crop_name": row[0],
                    "suitability": row[1],
                    "notes": row[2]
                }
                for row in reco_rows
            ]
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.get("/soil/polygons")
def get_soil_polygons():
    conn = None
    cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor()

        query = """
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', jsonb_agg(feature)
        )
        FROM (
            SELECT jsonb_build_object(
                'type', 'Feature',
                'geometry', ST_AsGeoJSON(geom)::jsonb,
                'properties', jsonb_build_object(
                    'id', id,
                    'soil_type', soil_type,
                    'soil_name', soil_name,
                    'barangay', barangay
                )
            ) AS feature
            FROM soil_polygons
        ) features;
        """

        cursor.execute(query)
        result = cursor.fetchone()
        return result[0]

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.post("/users/register")
def register_user(full_name: str, email: str, password: str):
    conn = None
    cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor()

        check_query = "SELECT id FROM users WHERE email = %s;"
        cursor.execute(check_query, (email,))
        existing_user = cursor.fetchone()

        if existing_user:
            raise HTTPException(status_code=400, detail="Email already registered")

        insert_query = """
        INSERT INTO users (full_name, email, password_hash)
        VALUES (%s, %s, %s)
        RETURNING id, full_name, email, role, created_at;
        """

        cursor.execute(insert_query, (full_name, email, password))
        user = cursor.fetchone()
        conn.commit()

        return {
            "message": "User registered successfully",
            "user": {
                "id": user[0],
                "full_name": user[1],
                "email": user[2],
                "role": user[3],
                "created_at": str(user[4])
            }
        }

    except HTTPException:
        raise

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.post("/users/login")
def login_user(email: str, password: str):
    conn = None
    cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor()

        query = """
        SELECT id, full_name, email, password_hash, role
        FROM users
        WHERE email = %s;
        """

        cursor.execute(query, (email,))
        user = cursor.fetchone()

        if not user:
            raise HTTPException(status_code=404, detail="User not found")

        if password != user[3]:
            raise HTTPException(status_code=401, detail="Invalid password")

        return {
            "message": "Login successful",
            "user": {
                "id": user[0],
                "full_name": user[1],
                "email": user[2],
                "role": user[4]
            }
        }

    except HTTPException:
        raise

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.post("/leases")
def create_lease(
    owner_name: str,
    contact_number: str,
    barangay: str,
    soil_type: str,
    area_hectares: float,
    price: float,
    description: str
):
    conn = None
    cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor()

        query = """
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
        """

        cursor.execute(query, (
            owner_name,
            contact_number,
            barangay,
            soil_type,
            area_hectares,
            price,
            description
        ))
        lease = cursor.fetchone()
        conn.commit()

        return {
            "message": "Land lease created successfully",
            "lease": {
                "id": lease[0],
                "owner_name": lease[1],
                "contact_number": lease[2],
                "barangay": lease[3],
                "soil_type": lease[4],
                "area_hectares": float(lease[5]),
                "price": float(lease[6]),
                "description": lease[7],
                "status": lease[8],
                "created_at": str(lease[9])
            }
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.get("/leases")
def get_leases():
    conn = None
    cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor()

        query = """
        SELECT id, owner_name, contact_number, barangay, soil_type,
               area_hectares, price, description, status, created_at
        FROM land_leases
        ORDER BY created_at DESC;
        """

        cursor.execute(query)
        rows = cursor.fetchall()

        return {
            "leases": [
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
                    "created_at": str(row[9])
                }
                for row in rows
            ]
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.post("/productivity")
def create_productivity_record(
    user_id: int,
    soil_type: str,
    crop_name: str,
    area_hectares: float,
    yield_amount: float,
    notes: str = ""
):
    conn = None
    cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor()

        user_check_query = "SELECT id FROM users WHERE id = %s;"
        cursor.execute(user_check_query, (user_id,))
        user_exists = cursor.fetchone()

        if not user_exists:
            raise HTTPException(status_code=404, detail="User not found")

        query = """
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
        """

        cursor.execute(query, (
            user_id,
            soil_type,
            crop_name,
            area_hectares,
            yield_amount,
            notes
        ))
        record = cursor.fetchone()
        conn.commit()

        return {
            "message": "Productivity record created successfully",
            "record": {
                "id": record[0],
                "user_id": record[1],
                "soil_type": record[2],
                "crop_name": record[3],
                "area_hectares": float(record[4]),
                "yield_amount": float(record[5]),
                "notes": record[6],
                "created_at": str(record[7])
            }
        }

    except HTTPException:
        raise

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.get("/productivity/{user_id}")
def get_productivity_records(user_id: int):
    conn = None
    cursor = None
    try:
        conn = get_connection()
        cursor = conn.cursor()

        query = """
        SELECT id, user_id, soil_type, crop_name,
               area_hectares, yield_amount, notes, created_at
        FROM productivity_records
        WHERE user_id = %s
        ORDER BY created_at DESC;
        """

        cursor.execute(query, (user_id,))
        rows = cursor.fetchall()

        return {
            "user_id": user_id,
            "records": [
                {
                    "id": row[0],
                    "user_id": row[1],
                    "soil_type": row[2],
                    "crop_name": row[3],
                    "area_hectares": float(row[4]),
                    "yield_amount": float(row[5]),
                    "notes": row[6],
                    "created_at": str(row[7])
                }
                for row in rows
            ]
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()


@app.get("/climate/current")
def get_climate_current(lat: float, lng: float):
    try:
        url = "https://api.open-meteo.com/v1/forecast"
        params = {
            "latitude": lat,
            "longitude": lng,
            "current": "temperature_2m,relative_humidity_2m,precipitation,rain,weather_code,wind_speed_10m",
            "timezone": "Asia/Manila"
        }

        response = requests.get(url, params=params, timeout=20)
        response.raise_for_status()
        data = response.json()

        current = data.get("current")
        if not current:
            return {"message": "No climate data returned"}

        return {
            "location": {
                "lat": lat,
                "lng": lng
            },
            "climate": {
                "temperature": current.get("temperature_2m"),
                "humidity": current.get("relative_humidity_2m"),
                "precipitation": current.get("precipitation"),
                "rain": current.get("rain"),
                "weather_code": current.get("weather_code"),
                "wind_speed": current.get("wind_speed_10m"),
                "time": current.get("time")
            }
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/dashboard/by-location")
def dashboard_by_location(lat: float, lng: float):
    conn = None
    cursor = None

    try:
        conn = get_connection()
        cursor = conn.cursor()

        soil_query = """
        SELECT soil_type, soil_name, barangay
        FROM soil_polygons
        WHERE ST_Contains(
            geom,
            ST_SetSRID(ST_Point(%s, %s), 4326)
        )
        LIMIT 1;
        """

        cursor.execute(soil_query, (lng, lat))
        soil_result = cursor.fetchone()

        if not soil_result:
            return {"message": "No soil data found for this location"}

        soil_type = soil_result[0]
        soil_name = soil_result[1]
        barangay = soil_result[2]

        reco_query = """
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
        """

        cursor.execute(reco_query, (soil_type,))
        reco_rows = cursor.fetchall()

        weather_url = "https://api.open-meteo.com/v1/forecast"
        weather_params = {
            "latitude": lat,
            "longitude": lng,
            "current": "temperature_2m,relative_humidity_2m,precipitation,rain,weather_code,wind_speed_10m",
            "timezone": "Asia/Manila"
        }

        weather_response = requests.get(weather_url, params=weather_params, timeout=20)
        weather_response.raise_for_status()
        weather_data = weather_response.json()
        current = weather_data.get("current", {})

        return {
            "location": {
                "lat": lat,
                "lng": lng,
                "barangay": barangay
            },
            "soil": {
                "soil_type": soil_type,
                "soil_name": soil_name
            },
            "climate": {
                "temperature": current.get("temperature_2m"),
                "humidity": current.get("relative_humidity_2m"),
                "precipitation": current.get("precipitation"),
                "rain": current.get("rain"),
                "weather_code": current.get("weather_code"),
                "wind_speed": current.get("wind_speed_10m"),
                "time": current.get("time")
            },
            "recommendations": [
                {
                    "crop_name": row[0],
                    "suitability": row[1],
                    "notes": row[2]
                }
                for row in reco_rows
            ]
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

@app.get("/soil-analysis/support")
def get_soil_analysis_support(
    soil_type: str = Query(..., description="Predicted soil type"),
    crop_name: Optional[str] = Query(None, description="Optional crop filter")
):
    conn = get_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)

    try:
        # 1. Get soil type + productivity basis
        cursor.execute("""
            SELECT
                st.id AS soil_type_id,
                st.soil_type_name,
                st.description AS soil_description,
                pl.id AS productivity_level_id,
                pl.productivity_level,
                pl.display_order,
                spb.nutrient_retention,
                spb.drainage_condition,
                spb.compaction_risk,
                spb.water_holding_capacity,
                spb.basis_explanation,
                spb.source_title,
                spb.source_organization,
                spb.source_year,
                spb.source_link
            FROM soil_types st
            LEFT JOIN soil_productivity_basis spb
                ON spb.soil_type_id = st.id
               AND spb.is_active = TRUE
            LEFT JOIN productivity_levels pl
                ON pl.id = spb.productivity_level_id
            WHERE LOWER(st.soil_type_name) = LOWER(%s)
            LIMIT 1
        """, (soil_type,))
        productivity_basis = cursor.fetchone()

        if not productivity_basis:
            raise HTTPException(
                status_code=404,
                detail=f"Soil type '{soil_type}' not found in soil_types / soil_productivity_basis."
            )

        productivity_level = productivity_basis.get("productivity_level")

        # 2. Get fertilizer recommendations based on:
        #    soil_type + productivity_level + optional crop_name
        fertilizer_recommendations = []
        if productivity_level:
            cursor.execute("""
                SELECT
                    frr.id,
                    frr.priority_order,
                    frr.recommendation_role,
                    frr.display_label,
                    frr.guidance_text,
                    frr.application_rate_text,
                    frr.application_timing_text,
                    frr.reason_basis,
                    frr.source_title,
                    frr.source_organization,
                    frr.source_year,
                    frr.source_link,

                    c.id AS crop_id,
                    c.crop_name,

                    f.id AS fertilizer_id,
                    f.fertilizer_code,
                    f.common_name,
                    f.display_name,
                    f.aliases,
                    f.n_value,
                    f.p_value,
                    f.k_value,
                    f.category,
                    f.note
                FROM fertilizer_recommendation_rules frr
                JOIN soil_types st
                    ON st.id = frr.soil_type_id
                JOIN productivity_levels pl
                    ON pl.id = frr.productivity_level_id
                JOIN fertilizers f
                    ON f.id = frr.fertilizer_id
                LEFT JOIN crops c
                    ON c.id = frr.crop_id
                WHERE frr.is_active = TRUE
                  AND LOWER(st.soil_type_name) = LOWER(%s)
                  AND LOWER(pl.productivity_level) = LOWER(%s)
                  AND (%s IS NULL OR LOWER(c.crop_name) = LOWER(%s))
                ORDER BY
                    CASE
                        WHEN %s IS NOT NULL AND LOWER(c.crop_name) = LOWER(%s) THEN 0
                        WHEN c.crop_name IS NULL THEN 1
                        ELSE 2
                    END,
                    frr.priority_order ASC,
                    f.display_name ASC
            """, (
                soil_type,
                productivity_level,
                crop_name,
                crop_name,
                crop_name,
                crop_name
            ))
            fertilizer_recommendations = cursor.fetchall()

        # 3. Get full fertilizer catalog
        cursor.execute("""
            SELECT
                id,
                fertilizer_code,
                common_name,
                display_name,
                aliases,
                n_value,
                p_value,
                k_value,
                category,
                note
            FROM fertilizers
            WHERE is_active = TRUE
            ORDER BY id ASC
        """)
        fertilizer_catalog = cursor.fetchall()

        return {
            "soil_type": productivity_basis["soil_type_name"],
            "soil_description": productivity_basis["soil_description"],
            "productivity_basis": productivity_basis,
            "fertilizer_recommendations": fertilizer_recommendations,
            "fertilizer_catalog": fertilizer_catalog,
            "filters": {
                "crop_name": crop_name,
                "productivity_level": productivity_level
            }
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conn.close()

@app.get("/soil-analysis/details")
def get_soil_analysis_details(
    soil_type: str = Query(..., description="Exact soil type name, e.g. Clay"),
    crop_name: Optional[str] = Query(None, description="Optional crop filter, e.g. Rice"),
    productivity_level: Optional[str] = Query(None, description="Optional override, e.g. Moderate")
):
    conn = None
    cursor = None

    try:
        conn = get_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)

        # 1) Get soil type + productivity basis
        if productivity_level:
            productivity_basis_query = """
                SELECT
                    st.id AS soil_type_id,
                    st.soil_type_name,
                    st.description AS soil_description,
                    pl.id AS productivity_level_id,
                    pl.productivity_level,
                    pl.display_order,
                    spb.nutrient_retention,
                    spb.drainage_condition,
                    spb.compaction_risk,
                    spb.water_holding_capacity,
                    spb.basis_explanation,
                    spb.source_title,
                    spb.source_organization,
                    spb.source_year,
                    spb.source_link
                FROM soil_productivity_basis spb
                JOIN soil_types st
                    ON st.id = spb.soil_type_id
                JOIN productivity_levels pl
                    ON pl.id = spb.productivity_level_id
                WHERE st.soil_type_name = %s
                  AND pl.productivity_level = %s
                  AND spb.is_active = TRUE
                LIMIT 1;
            """
            cursor.execute(productivity_basis_query, (soil_type, productivity_level))
        else:
            productivity_basis_query = """
                SELECT
                    st.id AS soil_type_id,
                    st.soil_type_name,
                    st.description AS soil_description,
                    pl.id AS productivity_level_id,
                    pl.productivity_level,
                    pl.display_order,
                    spb.nutrient_retention,
                    spb.drainage_condition,
                    spb.compaction_risk,
                    spb.water_holding_capacity,
                    spb.basis_explanation,
                    spb.source_title,
                    spb.source_organization,
                    spb.source_year,
                    spb.source_link
                FROM soil_productivity_basis spb
                JOIN soil_types st
                    ON st.id = spb.soil_type_id
                JOIN productivity_levels pl
                    ON pl.id = spb.productivity_level_id
                WHERE st.soil_type_name = %s
                  AND spb.is_active = TRUE
                ORDER BY pl.display_order
                LIMIT 1;
            """
            cursor.execute(productivity_basis_query, (soil_type,))

        productivity_basis = cursor.fetchone()

        if not productivity_basis:
            raise HTTPException(
                status_code=404,
                detail=f"No productivity basis found for soil type '{soil_type}'."
            )

        resolved_productivity_level = productivity_basis["productivity_level"]

        # 2) Get recommended crops for this soil type
        recommended_crops_query = """
            SELECT
                crop_name,
                suitability,
                notes
            FROM crop_recommendations
            WHERE soil_type = %s
            ORDER BY
                CASE
                    WHEN suitability = 'High' THEN 1
                    WHEN suitability = 'Medium' THEN 2
                    WHEN suitability = 'Moderate' THEN 2
                    WHEN suitability = 'Low' THEN 3
                    ELSE 4
                END,
                crop_name ASC;
        """
        cursor.execute(recommended_crops_query, (soil_type,))
        recommended_crops = [dict(row) for row in cursor.fetchall()]

        # 3) Get fertilizer recommendations
        # If crop_name is not provided -> only generic rules (crop_id IS NULL)
        # If crop_name is provided -> return crop-specific rules first, then generic fallback rules
        if crop_name:
            fertilizer_rules_query = """
                SELECT
                    frr.id,
                    st.soil_type_name,
                    pl.productivity_level,
                    c.crop_name,
                    frr.priority_order,
                    frr.recommendation_role,
                    frr.display_label,
                    frr.guidance_text,
                    frr.application_rate_text,
                    frr.application_timing_text,
                    frr.reason_basis,
                    frr.source_title,
                    frr.source_organization,
                    frr.source_year,
                    frr.source_link,
                    f.id AS fertilizer_id,
                    f.fertilizer_code,
                    f.common_name,
                    f.display_name,
                    f.aliases,
                    f.n_value,
                    f.p_value,
                    f.k_value,
                    f.category,
                    f.note
                FROM fertilizer_recommendation_rules frr
                JOIN soil_types st
                    ON st.id = frr.soil_type_id
                JOIN productivity_levels pl
                    ON pl.id = frr.productivity_level_id
                JOIN fertilizers f
                    ON f.id = frr.fertilizer_id
                LEFT JOIN crops c
                    ON c.id = frr.crop_id
                WHERE st.soil_type_name = %s
                  AND pl.productivity_level = %s
                  AND frr.is_active = TRUE
                  AND (
                        c.crop_name = %s
                        OR c.id IS NULL
                  )
                ORDER BY
                    CASE
                        WHEN c.crop_name = %s THEN 0
                        WHEN c.id IS NULL THEN 1
                        ELSE 2
                    END,
                    frr.priority_order ASC;
            """
            cursor.execute(
                fertilizer_rules_query,
                (soil_type, resolved_productivity_level, crop_name, crop_name)
            )
        else:
            fertilizer_rules_query = """
                SELECT
                    frr.id,
                    st.soil_type_name,
                    pl.productivity_level,
                    c.crop_name,
                    frr.priority_order,
                    frr.recommendation_role,
                    frr.display_label,
                    frr.guidance_text,
                    frr.application_rate_text,
                    frr.application_timing_text,
                    frr.reason_basis,
                    frr.source_title,
                    frr.source_organization,
                    frr.source_year,
                    frr.source_link,
                    f.id AS fertilizer_id,
                    f.fertilizer_code,
                    f.common_name,
                    f.display_name,
                    f.aliases,
                    f.n_value,
                    f.p_value,
                    f.k_value,
                    f.category,
                    f.note
                FROM fertilizer_recommendation_rules frr
                JOIN soil_types st
                    ON st.id = frr.soil_type_id
                JOIN productivity_levels pl
                    ON pl.id = frr.productivity_level_id
                JOIN fertilizers f
                    ON f.id = frr.fertilizer_id
                LEFT JOIN crops c
                    ON c.id = frr.crop_id
                WHERE st.soil_type_name = %s
                  AND pl.productivity_level = %s
                  AND frr.is_active = TRUE
                  AND c.id IS NULL
                ORDER BY frr.priority_order ASC;
            """
            cursor.execute(
                fertilizer_rules_query,
                (soil_type, resolved_productivity_level)
            )

        fertilizer_rules_rows = [dict(row) for row in cursor.fetchall()]

        fertilizer_recommendations = []
        for row in fertilizer_rules_rows:
            fertilizer_recommendations.append({
                "id": row["id"],
                "soil_type_name": row["soil_type_name"],
                "productivity_level": row["productivity_level"],
                "crop_name": row["crop_name"],
                "priority_order": row["priority_order"],
                "recommendation_role": row["recommendation_role"],
                "display_label": row["display_label"],
                "guidance_text": row["guidance_text"],
                "application_rate_text": row["application_rate_text"],
                "application_timing_text": row["application_timing_text"],
                "reason_basis": row["reason_basis"],
                "source_title": row["source_title"],
                "source_organization": row["source_organization"],
                "source_year": row["source_year"],
                "source_link": row["source_link"],
                "fertilizer": {
                    "id": row["fertilizer_id"],
                    "fertilizer_code": row["fertilizer_code"],
                    "common_name": row["common_name"],
                    "display_name": row["display_name"],
                    "aliases": row["aliases"],
                    "n_value": float(row["n_value"]) if row["n_value"] is not None else 0.0,
                    "p_value": float(row["p_value"]) if row["p_value"] is not None else 0.0,
                    "k_value": float(row["k_value"]) if row["k_value"] is not None else 0.0,
                    "category": row["category"],
                    "note": row["note"],
                }
            })

        # 4) Optional: full fertilizer catalog for dropdown/reference
        fertilizer_catalog_query = """
            SELECT
                id,
                fertilizer_code,
                common_name,
                display_name,
                aliases,
                n_value,
                p_value,
                k_value,
                category,
                note
            FROM fertilizers
            WHERE is_active = TRUE
            ORDER BY id ASC;
        """
        cursor.execute(fertilizer_catalog_query)
        fertilizer_catalog_rows = [dict(row) for row in cursor.fetchall()]

        fertilizer_catalog = []
        for row in fertilizer_catalog_rows:
            fertilizer_catalog.append({
                "id": row["id"],
                "fertilizer_code": row["fertilizer_code"],
                "common_name": row["common_name"],
                "display_name": row["display_name"],
                "aliases": row["aliases"],
                "n_value": float(row["n_value"]) if row["n_value"] is not None else 0.0,
                "p_value": float(row["p_value"]) if row["p_value"] is not None else 0.0,
                "k_value": float(row["k_value"]) if row["k_value"] is not None else 0.0,
                "category": row["category"],
                "note": row["note"],
            })

        return {
            "soil_type": productivity_basis["soil_type_name"],
            "soil_description": productivity_basis["soil_description"],
            "productivity_basis": {
                "soil_type_id": productivity_basis["soil_type_id"],
                "soil_type_name": productivity_basis["soil_type_name"],
                "soil_description": productivity_basis["soil_description"],
                "productivity_level_id": productivity_basis["productivity_level_id"],
                "productivity_level": productivity_basis["productivity_level"],
                "display_order": productivity_basis["display_order"],
                "nutrient_retention": productivity_basis["nutrient_retention"],
                "drainage_condition": productivity_basis["drainage_condition"],
                "compaction_risk": productivity_basis["compaction_risk"],
                "water_holding_capacity": productivity_basis["water_holding_capacity"],
                "basis_explanation": productivity_basis["basis_explanation"],
                "source_title": productivity_basis["source_title"],
                "source_organization": productivity_basis["source_organization"],
                "source_year": productivity_basis["source_year"],
                "source_link": productivity_basis["source_link"],
            },
            "recommended_crops": recommended_crops,
            "fertilizer_recommendations": fertilizer_recommendations,
            "fertilizer_catalog": fertilizer_catalog,
            "filters": {
                "crop_name": crop_name,
                "productivity_level": resolved_productivity_level
            }
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

def fetch_crop_recommendations_for_soil(cursor, soil_type: str):
    query = """
    SELECT
        id,
        soil_type,
        crop_name,
        suitability,
        notes
    FROM crop_recommendations
    WHERE LOWER(TRIM(soil_type)) = LOWER(TRIM(%s))
    ORDER BY
        CASE
            WHEN LOWER(TRIM(suitability)) = 'high' THEN 1
            WHEN LOWER(TRIM(suitability)) IN ('medium', 'moderate') THEN 2
            WHEN LOWER(TRIM(suitability)) = 'low' THEN 3
            ELSE 4
        END,
        crop_name ASC;
    """
    cursor.execute(query, (soil_type,))
    rows = cursor.fetchall()
    return [dict(row) for row in rows]


@app.get("/soil-analysis/crop-recommendations/{soil_type_name}")
def get_soil_analysis_crop_recommendations(soil_type_name: str):
    conn = None
    cursor = None

    try:
        conn = get_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)

        rows = fetch_crop_recommendations_for_soil(cursor, soil_type_name)

        return {
            "soil_type": soil_type_name,
            "total_recommendations": len(rows),
            "top_recommendation": rows[0] if rows else None,
            "recommendations": rows
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

