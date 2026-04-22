from fastapi import APIRouter, Body, HTTPException, Query

from models.common_models import ErrorResponse
from models.user_models import UserAuthResponse, UserLoginRequest, UserRegisterRequest
from services.user_service import login_user, register_user


router = APIRouter(prefix="/users", tags=["Users"])


@router.post(
    "/register",
    response_model=UserAuthResponse,
    summary="Register a user",
    description="Creates a new user account for the decision-support system. Accepts JSON body and also supports legacy query-parameter submission.",
    responses={400: {"model": ErrorResponse, "description": "Email already registered."}},
)
def register(
    payload: UserRegisterRequest | None = Body(None),
    full_name: str | None = Query(None),
    email: str | None = Query(None),
    password: str | None = Query(None),
):
    if payload is None:
        if not all([full_name, email, password]):
            raise HTTPException(status_code=422, detail="Provide JSON body or query parameters")
        payload = UserRegisterRequest(full_name=full_name, email=email, password=password)
    user = register_user(payload)
    return {"message": "User registered successfully", "user": user}


@router.post(
    "/login",
    response_model=UserAuthResponse,
    summary="Login a user",
    description="Authenticates a user by email and password. Supports both JSON body and legacy query-parameter submission.",
    responses={
        401: {"model": ErrorResponse, "description": "Invalid password."},
        404: {"model": ErrorResponse, "description": "User not found."},
    },
)
def login(
    payload: UserLoginRequest | None = Body(None),
    email: str | None = Query(None),
    password: str | None = Query(None),
):
    if payload is None:
        if not all([email, password]):
            raise HTTPException(status_code=422, detail="Provide JSON body or query parameters")
        payload = UserLoginRequest(email=email, password=password)
    user = login_user(payload)
    return {"message": "Login successful", "user": user}
