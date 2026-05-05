from datetime import date, datetime

from pydantic import BaseModel, Field


class LeaseCreateRequest(BaseModel):
    owner_name: str
    contact_number: str
    barangay: str
    soil_type: str
    area_hectares: float | None = Field(None, gt=0)
    area_sqm: float | None = Field(None, gt=0)
    price: float | None = Field(None, ge=0)
    description: str
    rental_start_date: date | None = None
    duration_value: float | None = Field(None, gt=0)
    duration_unit: str | None = None
    location_description: str | None = None
    lease_title: str | None = None
    user_id: int | None = None


class LeaseRentalRequestCreate(BaseModel):
    renter_user_id: int = Field(..., gt=0)
    renter_name: str | None = None
    renter_contact: str | None = None
    payment_due_date: date | None = None


class LeaseRentalPaymentUpdate(BaseModel):
    amount_paid: float | None = Field(None, ge=0)
    payment_status: str | None = None


class LeaseRentalStatusUpdate(BaseModel):
    rental_status: str
    approved_by: int | None = None


class LeaseMediaItem(BaseModel):
    id: int
    land_lease_id: int
    file_type: str
    original_file_name: str
    saved_file_name: str
    file_path: str
    file_extension: str
    content_type: str | None = None
    size_bytes: int
    uploaded_at: datetime | None = None


class LeaseContractSummary(BaseModel):
    id: int
    land_lease_id: int
    contract_number: str
    price_per_sqm: float | None = None
    total_lease_price: float | None = None
    generated_at: datetime | None = None


class LeaseContractResponse(BaseModel):
    contract_number: str
    contract_body: str
    price_per_sqm: float | None = None
    total_lease_price: float | None = None
    generated_at: datetime | None = None


class LeaseResponseItem(BaseModel):
    id: int
    owner_name: str
    contact_number: str
    barangay: str
    soil_type: str
    area_hectares: float | None = None
    area_sqm: float | None = None
    price: float | None = None
    description: str
    status: str | None = None
    created_at: datetime | None = None
    rental_start_date: date | None = None
    rental_end_date: date | None = None
    duration_value: float | None = None
    duration_unit: str | None = None
    duration_months: float | None = None
    price_per_sqm: float | None = None
    total_lease_price: float | None = None
    location_description: str | None = None
    contract_status: str | None = None
    lease_title: str | None = None
    availability_start_date: date | None = None
    availability_end_date: date | None = None
    contract_number: str | None = None
    media: list[LeaseMediaItem] = Field(default_factory=list)
    contract: LeaseContractSummary | None = None


class LeaseCreateResponse(BaseModel):
    message: str
    lease: LeaseResponseItem


class LeaseListResponse(BaseModel):
    leases: list[LeaseResponseItem]


class LeaseDetailResponse(BaseModel):
    lease: LeaseResponseItem


class LeaseMediaUploadResponse(BaseModel):
    message: str
    uploaded_media: list[LeaseMediaItem]
