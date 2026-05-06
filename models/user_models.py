from datetime import datetime

from pydantic import BaseModel, EmailStr, field_validator


VALID_USER_CATEGORIES = {"farmer", "renter"}


class UserRegisterRequest(BaseModel):
    full_name: str
    email: EmailStr
    password: str
    user_category: str

    @field_validator("user_category")
    @classmethod
    def validate_user_category(cls, value: str) -> str:
        normalized = (value or "").strip().lower()
        if normalized not in VALID_USER_CATEGORIES:
            raise ValueError("user_category must be either 'farmer' or 'renter'")
        return normalized


class UserLoginRequest(BaseModel):
    email: EmailStr
    password: str


class UserSummary(BaseModel):
    id: int
    full_name: str
    email: EmailStr
    role: str | None = None
    user_category: str | None = None
    created_at: datetime | None = None


class UserAuthResponse(BaseModel):
    message: str
    user: UserSummary
