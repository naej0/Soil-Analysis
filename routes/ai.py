from fastapi import APIRouter, Body, File, UploadFile

from models.ai_models import AIPredictRequest, AIPredictResponse, AIUploadResponse
from models.common_models import ErrorResponse
from services.ai_service import (
    predict_soil_from_file,
    save_upload_file,
    build_soil_decision_support,
    fetch_crop_recommendations,
    save_soil_analysis_log,
)

router = APIRouter(prefix="/ai", tags=["AI Soil Analysis"])


@router.post(
    "/upload-soil-image",
    response_model=AIUploadResponse,
    summary="Upload a soil image",
    description="Uploads and validates a soil image file, then saves it to the backend uploads directory for later AI inference.",
    responses={400: {"model": ErrorResponse, "description": "Invalid image upload."}},
)
def upload_soil_image(file: UploadFile = File(...)):
    saved = save_upload_file(file)
    return {"message": "Soil image uploaded successfully", **saved}


@router.post(
    "/predict",
    response_model=AIPredictResponse,
    summary="Predict soil type from uploaded image",
    description="Runs real soil-image inference for a previously uploaded image using the trained MobileNetV2 model and labels.json artifacts, then saves the analysis log.",
    responses={
        400: {"model": ErrorResponse, "description": "Invalid prediction request."},
        404: {"model": ErrorResponse, "description": "Uploaded image not found."},
        500: {"model": ErrorResponse, "description": "Prediction failed unexpectedly."},
        503: {"model": ErrorResponse, "description": "Trained model or labels are not available yet."},
    },
)
def predict_soil(payload: AIPredictRequest = Body(...)):
    # Existing prediction result from your trained model
    result = predict_soil_from_file(payload.file_name)

    predicted_soil_type = result.get("prediction")
    confidence = result.get("confidence")

    # Build decision-support fields for logging
    decision_support = build_soil_decision_support(predicted_soil_type)
    crop_recommendations = fetch_crop_recommendations(predicted_soil_type)

    # Save to soil_analysis_logs
    save_soil_analysis_log(
        user_id=payload.user_id,
        lat=payload.lat,
        lng=payload.lng,
        predicted_soil_type=predicted_soil_type,
        soil_name=payload.soil_name,
        barangay=payload.barangay,
        confidence=confidence,
        estimated_productivity_level=decision_support["estimated_productivity_level"],
        fertilizer_recommendation=decision_support["fertilizer_recommendation"],
        soil_management_advice=decision_support["soil_management_advice"],
        crop_recommendations=crop_recommendations,
        original_file_name=payload.original_file_name,
        image_path=payload.file_name,
    )

    # Keep the current response shape unchanged for Flutter
    return result