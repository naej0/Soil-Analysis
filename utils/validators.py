from fastapi import HTTPException

from config import SUPPORTED_SOIL_TYPES


def ensure_supported_soil_type(soil_type: str) -> None:
    if soil_type not in SUPPORTED_SOIL_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported soil type. Valid values: {', '.join(SUPPORTED_SOIL_TYPES)}",
        )
