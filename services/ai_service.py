from __future__ import annotations
import os
import io
import cv2
from matplotlib import image
import numpy as np
from PIL import Image, UnidentifiedImageError
import json
import uuid
import shutil
import importlib
from fastapi import HTTPException, UploadFile
from tensorflow.keras.models import load_model # type: ignore
from datetime import datetime, timezone
from functools import lru_cache
from io import BytesIO
from pathlib import Path
from typing import Optional
from uuid import uuid4
from psycopg2.extras import Json, RealDictCursor
from db import get_connection

try:
    import cv2  # type: ignore
except Exception:
    cv2 = None

from config import (
    ALLOWED_IMAGE_EXTENSIONS,
    LABELS_PATH,
    SUPPORTED_SOIL_TYPES,
    TRAINED_MODEL_PATH,
    UPLOAD_DIR,
)
from db import get_cursor
from ml.utils.preprocess import load_image_array


class ModelNotConfiguredError(Exception):
    pass

BASE_DIR = Path(__file__).resolve().parent.parent
UPLOAD_DIR = BASE_DIR / "uploads"
MODEL_DIR = BASE_DIR / "ml" / "models"
TRAINED_MODEL_PATH = MODEL_DIR / "best_model.keras"
LABELS_PATH = MODEL_DIR / "labels.json"

_MODEL_CACHE = {
    "model": None,
    "labels": None,
    "model_path": None,
    "labels_path": None,
    "model_mtime": None,
    "labels_mtime": None,
}

_FACE_CASCADE = None
_HOG = None

SOIL_DECISION_SUPPORT = {
    "Loam": {
        "estimated_productivity_level": "High",
        "fertilizer_recommendation": "Apply balanced organic and inorganic nutrient support to maintain loam soil fertility.",
        "soil_management_advice": "Maintain fertility through compost application, proper drainage, and crop rotation.",
    },
    "Clay Loam": {
        "estimated_productivity_level": "Medium to High",
        "fertilizer_recommendation": "Apply balanced fertilizer and organic matter to improve nutrient availability and structure.",
        "soil_management_advice": "Maintain moderate drainage, reduce compaction, and support soil structure with organic matter.",
    },
    "Clay": {
        "estimated_productivity_level": "Medium",
        "fertilizer_recommendation": "Use organic matter and balanced fertilizer inputs; avoid over-application in poorly drained areas.",
        "soil_management_advice": "Improve drainage, reduce waterlogging, and loosen compacted soil before planting.",
    },
    "Silty Clay": {
        "estimated_productivity_level": "Medium",
        "fertilizer_recommendation": "Apply organic matter and balanced fertilizer support suited for moisture-retentive soil.",
        "soil_management_advice": "Improve drainage, avoid prolonged waterlogging, and monitor soil moisture before planting.",
    },
    "Rock Land": {
        "estimated_productivity_level": "Low",
        "fertilizer_recommendation": "Fertilizer effect may be limited; prioritize soil improvement and organic matter buildup first.",
        "soil_management_advice": "Use soil rehabilitation measures, add organic matter, and consider only hardy or suitable crops.",
    },
}


def ensure_upload_dir() -> None:
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


def validate_image_upload(upload_file: UploadFile) -> None:
    original_name = (upload_file.filename or "").strip()
    if not original_name:
        raise HTTPException(status_code=400, detail="Uploaded file must include a file name.")

    content_type = (upload_file.content_type or "").strip().lower()
    if content_type and content_type != "application/octet-stream" and not content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Uploaded file must be an image.")

    extension = Path(original_name).suffix.lower()
    if extension not in ALLOWED_IMAGE_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type. Allowed: {sorted(ALLOWED_IMAGE_EXTENSIONS)}",
        )


def _read_upload_bytes(upload_file: UploadFile) -> bytes:
    file_bytes = upload_file.file.read()

    if not file_bytes:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")

    if len(file_bytes) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Uploaded file exceeds 10MB limit.")

    return file_bytes


def _load_rgb_from_bytes(image_bytes: bytes) -> np.ndarray:
    try:
        pil_image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    except UnidentifiedImageError as exc:
        raise HTTPException(status_code=400, detail="Invalid image file.") from exc
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Unable to read the uploaded image.") from exc

    return np.array(pil_image)


def _get_face_cascade():
    global _FACE_CASCADE

    if cv2 is None:
        return None

    if _FACE_CASCADE is None:
        try:
            cascade_path = str(Path(cv2.data.haarcascades) / "haarcascade_frontalface_default.xml")
            classifier = cv2.CascadeClassifier(cascade_path)
            if classifier.empty():
                return None
            _FACE_CASCADE = classifier
        except Exception:
            return None

    return _FACE_CASCADE


def _get_people_hog():
    global _HOG

    if cv2 is None:
        return None

    if _HOG is None:
        try:
            hog = cv2.HOGDescriptor()
            hog.setSVMDetector(cv2.HOGDescriptor_getDefaultPeopleDetector())
            _HOG = hog
        except Exception:
            return None

    return _HOG


def _compute_texture_score(gray: np.ndarray) -> float:
    if cv2 is not None:
        return float(cv2.Laplacian(gray, cv2.CV_64F).var())

    gray_float = gray.astype("float32")
    gy, gx = np.gradient(gray_float)
    return float(np.mean((gx ** 2) + (gy ** 2)))


def validate_soil_photo(image_bytes: bytes):
    rgb = _load_rgb_from_bytes(image_bytes)

    if rgb is None or rgb.size == 0:
        return False, "Invalid image."

    h, w, _ = rgb.shape
    if h < 80 or w < 80:
        return False, "Image is too small. Please upload a clearer soil photo."

    if cv2 is not None:
        bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
        gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
        hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)

        face_cascade = _get_face_cascade()
        if face_cascade is not None:
            faces = face_cascade.detectMultiScale(
                gray,
                scaleFactor=1.1,
                minNeighbors=5,
                minSize=(40, 40),
            )
            #if len(faces) > 0:
                #return False, "Person/face detected. Please upload a soil photo only."

        #hog = _get_people_hog()
        #if hog is not None:
            #     try:
    #         people_rects, weights = hog.detectMultiScale(
    #             bgr,
    #             winStride=(8, 8),
    #             padding=(8, 8),
    #             scale=1.05,
    #         )
    #         if len(people_rects) > 0:
    #             if len(weights) == 0 or float(np.max(weights)) >= 0.30:
    #                 return False, "Person detected. Please upload a soil photo only."
    #     except Exception:
    #         pass


        # Loosened soil color ranges for brown / reddish / grayish soils
        
        soil_mask_1 = cv2.inRange(hsv, np.array([0, 10, 20]), np.array([35, 255, 255]))
        soil_mask_2 = cv2.inRange(hsv, np.array([0, 0, 20]), np.array([180, 120, 220]))
        soil_mask_3 = cv2.inRange(hsv, np.array([160, 10, 20]), np.array([179, 255, 255]))
        soil_mask = cv2.bitwise_or(cv2.bitwise_or(soil_mask_1, soil_mask_2), soil_mask_3)

        green_mask = cv2.inRange(hsv, np.array([35, 40, 20]), np.array([95, 255, 255]))
        blue_mask = cv2.inRange(hsv, np.array([96, 40, 20]), np.array([140, 255, 255]))

        soil_ratio = float(np.count_nonzero(soil_mask)) / float(soil_mask.size)
        green_ratio = float(np.count_nonzero(green_mask)) / float(green_mask.size)
        blue_ratio = float(np.count_nonzero(blue_mask)) / float(blue_mask.size)
        texture_score = _compute_texture_score(gray)

        # Keep blocking obvious non-soil scenes
        if blue_ratio > 0.45:
            return False, "The image looks like sky, water, or another non-soil subject. Please upload soil only."

        if green_ratio > 0.60:
            return False, "The image contains too much vegetation. Please focus on bare soil."

        # Only reject if soil is clearly too little AND the image is dominated by non-soil colors
        if soil_ratio < 0.10:
          return False, "Not enough soil area detected. Please capture a closer soil photo."

        # Much softer blur rule for real phone captures
        if texture_score < 4:
            return False, "Image is too blurry. Please retake a clearer soil photo."

        return True, {
            "soil_ratio": round(soil_ratio, 3),
            "green_ratio": round(green_ratio, 3),
            "blue_ratio": round(blue_ratio, 3),
            "texture_score": round(texture_score, 2),
        }

    # Fallback if OpenCV is not available
    r = rgb[:, :, 0].astype("float32")
    g = rgb[:, :, 1].astype("float32")
    b = rgb[:, :, 2].astype("float32")

    soil_like_mask = (
        (r > 25)
        & (g > 15)
        & (b > 5)
        & (r >= (b * 0.90))
        & (g >= (b * 0.70))
    )
    green_mask = (g > (r * 1.15)) & (g > (b * 1.15)) & (g > 40)
    blue_mask = (b > (r * 1.15)) & (b > (g * 1.15)) & (b > 40)

    soil_ratio = float(np.count_nonzero(soil_like_mask)) / float(soil_like_mask.size)
    green_ratio = float(np.count_nonzero(green_mask)) / float(green_mask.size)
    blue_ratio = float(np.count_nonzero(blue_mask)) / float(blue_mask.size)

    gray = np.dot(rgb[..., :3], [0.299, 0.587, 0.114]).astype(np.uint8)
    texture_score = _compute_texture_score(gray)

    if blue_ratio > 0.45:
        return False, "The image looks like sky, water, or another non-soil subject. Please upload soil only."

    if green_ratio > 0.60:
        return False, "The image contains too much vegetation. Please focus on bare soil."

    if soil_ratio < 0.10:
        return False, "Not enough soil area detected. Please capture a closer soil photo."

    if texture_score < 4:
        return False, "Image is too blurry. Please retake a clearer soil photo."

    return True, {
        "soil_ratio": round(soil_ratio, 3),
        "green_ratio": round(green_ratio, 3),
        "blue_ratio": round(blue_ratio, 3),
        "texture_score": round(texture_score, 2),
        "validation_mode": "fallback_without_opencv",
    }


def validate_soil_photo_or_raise(image_bytes: bytes) -> dict:
    is_valid, result = validate_soil_photo(image_bytes)
    if not is_valid:
        raise HTTPException(status_code=400, detail=result)
    return result


def save_upload_file(upload_file: UploadFile) -> dict:
    ensure_upload_dir()
    validate_image_upload(upload_file)

    file_bytes = _read_upload_bytes(upload_file)
    validate_soil_photo_or_raise(file_bytes)

    original_name = Path((upload_file.filename or "").strip()).name or "soil-image"
    extension = Path(original_name).suffix.lower()
    safe_name = f"{uuid4().hex}{extension}"
    destination = UPLOAD_DIR / safe_name

    destination.write_bytes(file_bytes)

    try:
        with Image.open(destination) as image:
            image.verify()
    except Exception as exc:
        destination.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail="Uploaded file is not a valid image.") from exc

    return {
        "file_name": safe_name,
        "original_file_name": original_name,
        "content_type": upload_file.content_type or "application/octet-stream",
        "size_bytes": len(file_bytes),
    }


def predict_soil_from_file(file_name: str) -> dict:
    ensure_upload_dir()

    normalized_name = Path((file_name or "").strip()).name
    if not normalized_name:
        raise HTTPException(status_code=400, detail="file_name is required.")

    image_path = UPLOAD_DIR / normalized_name
    if not image_path.exists():
        raise HTTPException(status_code=404, detail="Uploaded image not found.")

    try:
        image_bytes = image_path.read_bytes()

        is_valid, validation_message = validate_soil_photo(image_bytes)
        if not is_valid:
            raise HTTPException(status_code=400, detail=validation_message)

        inference_result = run_model_inference(image_path)

        top_predictions = inference_result.get("top_predictions", [])
        top1_conf = float(inference_result.get("confidence", 0.0))
        top2_conf = float(top_predictions[1]["confidence"]) if len(top_predictions) > 1 else 0.0
        confidence_gap = top1_conf - top2_conf

        if top1_conf < 0.65:
            raise HTTPException(
                status_code=400,
                detail="Image is not a confident soil match. Please upload a clearer close-up soil photo."
            )

        if confidence_gap < 0.08:
            raise HTTPException(
                status_code=400,
                detail="Prediction is too ambiguous. Please upload a clearer close-up soil photo of soil only."
            )

    except ModelNotConfiguredError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
        status_code=500,
        detail="Prediction failed due to an internal inference error.",
    ) from exc

    created_at = datetime.utcnow()

    log_ai_prediction_if_table_exists(
        file_name=normalized_name,
        prediction=inference_result["prediction"],
        confidence=inference_result["confidence"],
        status="success",
    )

    return {
        "status": "success",
        "file_name": normalized_name,
        "prediction": inference_result["prediction"],
        "confidence": inference_result["confidence"],
        "top_predictions": inference_result["top_predictions"],
        "supported_soil_types": list(SUPPORTED_SOIL_TYPES),
        "message": "Prediction completed successfully.",
        "created_at": created_at,
    }


def run_model_inference(image_path: Path) -> dict:
    bundle = load_model_bundle()
    model = bundle["model"]
    labels = bundle["labels"]

    image_size = tuple(labels["image_size"])
    class_names = labels["class_names"]

    image_array = load_image_array(image_path, image_size)
    predictions = model.predict(image_array, verbose=0)[0]

    top_indices = np.argsort(predictions)[::-1][:3]
    top_predictions = [
        {
            "soil_type": class_names[index],
            "confidence": float(predictions[index]),
        }
        for index in top_indices
    ]

    return {
        "prediction": top_predictions[0]["soil_type"],
        "confidence": top_predictions[0]["confidence"],
        "top_predictions": top_predictions,
    }


def validate_labels_payload(labels: dict) -> dict:
    class_names = labels.get("class_names")
    if not isinstance(class_names, list) or not class_names:
        raise ModelNotConfiguredError(
            f"labels.json at {LABELS_PATH} is invalid: class_names must be a non-empty list."
        )

    if len(class_names) != len(SUPPORTED_SOIL_TYPES):
        raise ModelNotConfiguredError(
            f"labels.json at {LABELS_PATH} must contain exactly {len(SUPPORTED_SOIL_TYPES)} classes."
        )

    if len(set(class_names)) != len(class_names):
        raise ModelNotConfiguredError(
            f"labels.json at {LABELS_PATH} contains duplicate class names."
        )

    unsupported_classes = [name for name in class_names if name not in SUPPORTED_SOIL_TYPES]
    if unsupported_classes:
        raise ModelNotConfiguredError(
            "labels.json contains unsupported soil classes: "
            f"{', '.join(sorted(unsupported_classes))}."
        )

    class_to_index = labels.get("class_to_index")
    expected_class_to_index = {name: index for index, name in enumerate(class_names)}
    if class_to_index is not None and class_to_index != expected_class_to_index:
        raise ModelNotConfiguredError(
            f"labels.json at {LABELS_PATH} has an inconsistent class_to_index mapping."
        )

    index_to_class = labels.get("index_to_class")
    expected_index_to_class = {str(index): name for index, name in enumerate(class_names)}
    if index_to_class is not None and index_to_class != expected_index_to_class:
        raise ModelNotConfiguredError(
            f"labels.json at {LABELS_PATH} has an inconsistent index_to_class mapping."
        )

    image_size = labels.get("image_size", [224, 224])
    if (
        not isinstance(image_size, list)
        or len(image_size) != 2
        or any(not isinstance(value, int) or value <= 0 for value in image_size)
    ):
        raise ModelNotConfiguredError(
            f"labels.json at {LABELS_PATH} has an invalid image_size value."
        )

    return {
        "class_names": class_names,
        "class_to_index": expected_class_to_index,
        "index_to_class": expected_index_to_class,
        "image_size": image_size,
    }


def validate_model_and_labels(model, labels: dict) -> None:
    output_shape = getattr(model, "output_shape", None)
    if not isinstance(output_shape, tuple) or len(output_shape) < 2:
        raise ModelNotConfiguredError(
            f"The trained model at {TRAINED_MODEL_PATH} has an unsupported output shape."
        )

    num_classes = output_shape[-1]
    if not isinstance(num_classes, int) or num_classes != len(labels["class_names"]):
        raise ModelNotConfiguredError(
            "The trained model output size does not match the number of classes in labels.json."
        )


def load_model_bundle() -> dict:
    model_path = TRAINED_MODEL_PATH
    labels_path = LABELS_PATH

    if not model_path.exists():
        raise ModelNotConfiguredError(
            f"No trained model file was found at {model_path}. "
            "Train the MobileNetV2 model first with: python ml/training/train_model.py"
        )

    if not labels_path.exists():
        raise ModelNotConfiguredError(
            f"No labels.json file was found at {labels_path}. "
            "Run the training pipeline to generate labels.json."
        )

    try:
        tensorflow = importlib.import_module("tensorflow")
    except ModuleNotFoundError as exc:
        raise ModelNotConfiguredError(
            "TensorFlow is not installed. Install the ML dependencies from requirements.txt first."
        ) from exc

    model_mtime = model_path.stat().st_mtime
    labels_mtime = labels_path.stat().st_mtime

    if (
        _MODEL_CACHE["model"] is None
        or _MODEL_CACHE["model_path"] != str(model_path)
        or _MODEL_CACHE["labels_path"] != str(labels_path)
        or _MODEL_CACHE["model_mtime"] != model_mtime
        or _MODEL_CACHE["labels_mtime"] != labels_mtime
    ):
        try:
            model = tensorflow.keras.models.load_model(model_path)
        except Exception as exc:
            raise ModelNotConfiguredError(
                f"Failed to load the trained model from {model_path}."
            ) from exc

        try:
            raw_labels = json.loads(labels_path.read_text(encoding="utf-8"))
        except Exception as exc:
            raise ModelNotConfiguredError(
                f"Failed to read labels.json from {labels_path}."
            ) from exc

        validated_labels = validate_labels_payload(raw_labels)
        validate_model_and_labels(model, validated_labels)

        _MODEL_CACHE["model"] = model
        _MODEL_CACHE["labels"] = validated_labels
        _MODEL_CACHE["model_path"] = str(model_path)
        _MODEL_CACHE["labels_path"] = str(labels_path)
        _MODEL_CACHE["model_mtime"] = model_mtime
        _MODEL_CACHE["labels_mtime"] = labels_mtime

    return {
        "model": _MODEL_CACHE["model"],
        "labels": _MODEL_CACHE["labels"],
    }


def build_soil_decision_support(predicted_soil_type: str | None) -> dict:
    if not predicted_soil_type:
        return {
            "estimated_productivity_level": "Unknown",
            "fertilizer_recommendation": "No fertilizer recommendation available.",
            "soil_management_advice": "No soil management advice available.",
        }

    return SOIL_DECISION_SUPPORT.get(
        predicted_soil_type,
        {
            "estimated_productivity_level": "Unknown",
            "fertilizer_recommendation": "No fertilizer recommendation available.",
            "soil_management_advice": "No soil management advice available.",
        },
    )


def fetch_crop_recommendations(soil_type: str | None) -> list[dict]:
    if not soil_type:
        return []

    try:
        with get_cursor() as (_, cursor):
            cursor.execute(
                """
                SELECT crop_name, suitability, notes
                FROM crop_recommendations
                WHERE soil_type = %s
                ORDER BY
                    CASE suitability
                        WHEN 'High' THEN 1
                        WHEN 'Medium' THEN 2
                        WHEN 'Low' THEN 3
                        ELSE 4
                    END,
                    crop_name;
                """,
                (soil_type,),
            )
            rows = cursor.fetchall()

            return [
                {
                    "crop_name": row[0],
                    "suitability": row[1],
                    "notes": row[2],
                }
                for row in rows
            ]
    except Exception:
        return []


def save_soil_analysis_log(
    *,
    user_id: int | None,
    lat: float | None,
    lng: float | None,
    predicted_soil_type: str | None,
    soil_name: str | None,
    barangay: str | None,
    confidence: float | None,
    estimated_productivity_level: str | None,
    fertilizer_recommendation: str | None,
    soil_management_advice: str | None,
    crop_recommendations: list[dict],
    original_file_name: str | None,
    image_path: str | None,
) -> int | None:
    try:
        with get_cursor() as (_, cursor):
            cursor.execute("SELECT to_regclass('public.soil_analysis_logs');")
            table_exists = cursor.fetchone()
            if not table_exists or not table_exists[0]:
                return None

            cursor.execute(
                """
                SELECT column_name
                FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'soil_analysis_logs'
                ORDER BY ordinal_position;
                """
            )
            columns = {row[0] for row in cursor.fetchall()}

            insert_columns = []
            values = []

            if "user_id" in columns:
                insert_columns.append("user_id")
                values.append(user_id)

            if "lat" in columns:
                insert_columns.append("lat")
                values.append(lat)

            if "lng" in columns:
                insert_columns.append("lng")
                values.append(lng)

            if "soil_type" in columns:
                insert_columns.append("soil_type")
                values.append(predicted_soil_type)

            if "soil_name" in columns:
                insert_columns.append("soil_name")
                values.append(soil_name or predicted_soil_type)

            if "barangay" in columns:
                insert_columns.append("barangay")
                values.append(barangay)

            if "predicted_soil_type" in columns:
                insert_columns.append("predicted_soil_type")
                values.append(predicted_soil_type)

            if "confidence" in columns:
                insert_columns.append("confidence")
                values.append(confidence)

            if "estimated_productivity_level" in columns:
                insert_columns.append("estimated_productivity_level")
                values.append(estimated_productivity_level)

            if "fertilizer_recommendation" in columns:
                insert_columns.append("fertilizer_recommendation")
                values.append(fertilizer_recommendation)

            if "soil_management_advice" in columns:
                insert_columns.append("soil_management_advice")
                values.append(soil_management_advice)

            if "crop_recommendations" in columns:
                insert_columns.append("crop_recommendations")
                values.append(Json(crop_recommendations))

            if "original_file_name" in columns:
                insert_columns.append("original_file_name")
                values.append(original_file_name)

            if "image_path" in columns:
                insert_columns.append("image_path")
                values.append(image_path)

            if "updated_at" in columns:
                insert_columns.append("updated_at")
                values.append(datetime.utcnow())

            if not insert_columns:
                return None

            placeholders = ", ".join(["%s"] * len(insert_columns))
            query = f"""
                INSERT INTO soil_analysis_logs ({', '.join(insert_columns)})
                VALUES ({placeholders})
                RETURNING id;
            """
            cursor.execute(query, tuple(values))
            inserted = cursor.fetchone()
            return inserted[0] if inserted else None
    except Exception:
        return None


def log_ai_prediction_if_table_exists(
    file_name: str,
    prediction: str | None,
    confidence: float | None,
    status: str,
) -> None:
    try:
        with get_cursor() as (_, cursor):
            cursor.execute("SELECT to_regclass('public.ai_predictions');")
            table_exists = cursor.fetchone()
            if not table_exists or not table_exists[0]:
                return

            cursor.execute(
                """
                SELECT column_name
                FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'ai_predictions'
                ORDER BY ordinal_position;
                """
            )
            columns = {row[0] for row in cursor.fetchall()}

            insert_columns = []
            values = []

            if "file_name" in columns:
                insert_columns.append("file_name")
                values.append(file_name)
            elif "image_path" in columns:
                insert_columns.append("image_path")
                values.append(str(UPLOAD_DIR / file_name))

            if "predicted_soil_type" in columns:
                insert_columns.append("predicted_soil_type")
                values.append(prediction)

            if "confidence" in columns:
                insert_columns.append("confidence")
                values.append(confidence)

            if "status" in columns:
                insert_columns.append("status")
                values.append(status)

            if not insert_columns:
                return

            placeholders = ", ".join(["%s"] * len(insert_columns))
            cursor.execute(
                f"INSERT INTO ai_predictions ({', '.join(insert_columns)}) VALUES ({placeholders});",
                tuple(values),
            )
    except Exception:
        return