from fastapi import HTTPException

from db import get_cursor
from services.recommendation_service import get_recommendations_by_soil_type


def get_soil_by_location(lat: float, lng: float) -> dict | None:
    with get_cursor() as (_, cursor):
        cursor.execute(
            """
            SELECT soil_type, soil_name, barangay
            FROM soil_polygons
            WHERE ST_Contains(
                geom,
                ST_SetSRID(ST_Point(%s, %s), 4326)
            )
            LIMIT 1;
            """,
            (lng, lat),
        )
        result = cursor.fetchone()

    if not result:
        return None

    soil_type = result[0]
    return {
        "soil_type": soil_type,
        "soil_name": result[1],
        "barangay": result[2],
        "recommendations": get_recommendations_by_soil_type(soil_type),
    }


def get_soil_polygons_geojson() -> dict:
    with get_cursor() as (_, cursor):
        cursor.execute(
            """
            SELECT jsonb_build_object(
                'type', 'FeatureCollection',
                'features', COALESCE(jsonb_agg(feature), '[]'::jsonb)
            )
            FROM (
                SELECT jsonb_build_object(
                    'type', 'Feature',
                    'geometry', ST_AsGeoJSON(geom)::jsonb,
                    'properties', jsonb_build_object(
                        'id', id,
                        'fid', fid,
                        'soil_type', soil_type,
                        'soil_name', soil_name,
                        'barangay', barangay
                    )
                ) AS feature
                FROM soil_polygons
            ) features;
            """
        )
        result = cursor.fetchone()

    if not result or not result[0]:
        return {"type": "FeatureCollection", "features": []}
    return result[0]


def get_analysis_by_location(lat: float, lng: float) -> dict:
    soil_data = get_soil_by_location(lat, lng)
    if not soil_data:
        raise HTTPException(status_code=404, detail="No soil data found for this location")

    return {
        "location": {
            "lat": lat,
            "lng": lng,
            "barangay": soil_data["barangay"],
        },
        "soil": {
            "soil_type": soil_data["soil_type"],
            "soil_name": soil_data["soil_name"],
        },
        "recommendations": soil_data["recommendations"],
    }
