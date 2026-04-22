from datetime import datetime

from pydantic import BaseModel, EmailStr


class UserRegisterRequest(BaseModel):
    full_name: str
    email: EmailStr
    password: str


class UserLoginRequest(BaseModel):
    email: EmailStr
    password: str


class UserSummary(BaseModel):
    id: int
    full_name: str
    email: EmailStr
    role: str | None = None
    created_at: datetime | None = None


class UserAuthResponse(BaseModel):
    message: str
    user: UserSummary
