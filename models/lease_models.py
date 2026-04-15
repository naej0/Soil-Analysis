from datetime import datetime

from pydantic import BaseModel, Field


class LeaseCreateRequest(BaseModel):
    owner_name: str
    contact_number: str
    barangay: str
    soil_type: str
    area_hectares: float = Field(..., gt=0)
    price: float = Field(..., ge=0)
    description: str


class LeaseResponseItem(BaseModel):
    id: int
    owner_name: str
    contact_number: str
    barangay: str
    soil_type: str
    area_hectares: float
    price: float
    description: str
    status: str | None = None
    created_at: datetime | None = None


class LeaseCreateResponse(BaseModel):
    message: str
    lease: LeaseResponseItem


class LeaseListResponse(BaseModel):
    leases: list[LeaseResponseItem]
