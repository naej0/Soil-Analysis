import requests
from fastapi import HTTPException

from config import OPEN_METEO_BASE_URL


def _weather_session() -> requests.Session:
    session = requests.Session()
    session.trust_env = False
    return session


def fetch_weather_data(lat: float, lng: float) -> dict:
    params = {
        "latitude": lat,
        "longitude": lng,
        "current": "temperature_2m,relative_humidity_2m,precipitation,rain,weather_code,wind_speed_10m",
        "daily": "temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,wind_speed_10m_max",
        "timezone": "Asia/Manila",
        "forecast_days": 3,
    }
    try:
        with _weather_session() as session:
            response = session.get(OPEN_METEO_BASE_URL, params=params, timeout=20)
            response.raise_for_status()
            return response.json()
    except requests.RequestException as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Climate service request failed: {exc}",
        ) from exc


def build_current_climate(lat: float, lng: float) -> dict:
    data = fetch_weather_data(lat, lng)
    return build_current_climate_from_data(lat, lng, data)


def build_advisory(lat: float, lng: float) -> dict:
    data = fetch_weather_data(lat, lng)
    return build_advisory_from_data(lat, lng, data)


def build_current_climate_from_data(lat: float, lng: float, data: dict) -> dict:
    current = data.get("current")
    if not current:
        raise HTTPException(status_code=404, detail="No climate data returned")

    return {
        "location": {"lat": lat, "lng": lng},
        "climate": {
            "temperature": current.get("temperature_2m"),
            "humidity": current.get("relative_humidity_2m"),
            "precipitation": current.get("precipitation"),
            "rain": current.get("rain"),
            "weather_code": current.get("weather_code"),
            "wind_speed": current.get("wind_speed_10m"),
            "time": current.get("time"),
        },
    }


def build_advisory_from_data(lat: float, lng: float, data: dict) -> dict:
    current = data.get("current", {})
    daily = data.get("daily", {})

    precipitation_probability = _safe_daily_value(daily, "precipitation_probability_max")
    precipitation_sum = _safe_daily_value(daily, "precipitation_sum")
    wind_speed_max = _safe_daily_value(daily, "wind_speed_10m_max")
    temperature_max = _safe_daily_value(daily, "temperature_2m_max")

    advisory = []
    if precipitation_probability is not None and precipitation_probability >= 70:
        advisory.append("High chance of rain. Delay fertilizer spraying and plan fieldwork early.")
    if precipitation_sum is not None and precipitation_sum >= 10:
        advisory.append("Expected rainfall is significant. Check drainage in low-lying plots.")
    if wind_speed_max is not None and wind_speed_max >= 25:
        advisory.append("Strong winds are possible. Secure seedlings, covers, and light farm structures.")
    if temperature_max is not None and temperature_max >= 33:
        advisory.append("Hot daytime conditions are forecast. Prioritize irrigation and monitor plant stress.")
    if not advisory:
        advisory.append("Weather conditions are currently moderate for routine field activities.")

    return {
        "location": {"lat": lat, "lng": lng},
        "current": {
            "temperature": current.get("temperature_2m"),
            "humidity": current.get("relative_humidity_2m"),
            "precipitation": current.get("precipitation"),
            "rain": current.get("rain"),
            "wind_speed": current.get("wind_speed_10m"),
            "time": current.get("time"),
        },
        "advisory": advisory,
        "forecast": {
            "precipitation_probability_max": precipitation_probability,
            "precipitation_sum": precipitation_sum,
            "wind_speed_10m_max": wind_speed_max,
            "temperature_2m_max": temperature_max,
        },
    }


def _safe_daily_value(daily: dict, field_name: str):
    values = daily.get(field_name) or []
    return values[0] if values else None
