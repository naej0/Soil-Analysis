from datetime import datetime

from pydantic import BaseModel, Field


class ProductivityCreateRequest(BaseModel):
    user_id: int
    soil_type: str
    crop_name: str
    area_hectares: float = Field(..., gt=0)
    yield_amount: float = Field(..., ge=0)
    notes: str = ""


class ProductivityRecordItem(BaseModel):
    id: int
    user_id: int
    soil_type: str
    crop_name: str
    area_hectares: float
    yield_amount: float
    notes: str | None = None
    created_at: datetime | None = None


class ProductivityCreateResponse(BaseModel):
    message: str
    record: ProductivityRecordItem


class ProductivityListResponse(BaseModel):
    records: list[ProductivityRecordItem]
