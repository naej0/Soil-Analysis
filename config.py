import os
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
UPLOAD_DIR = BASE_DIR / "uploads"
RAW_SOIL_DATASET_DIR = BASE_DIR / "soil_images"
ML_DIR = BASE_DIR / "ml"
ML_DATASET_DIR = ML_DIR / "dataset"
ML_TRAIN_DIR = ML_DATASET_DIR / "train"
ML_VAL_DIR = ML_DATASET_DIR / "val"
ML_MODELS_DIR = ML_DIR / "models"
ML_TRAINING_DIR = ML_DIR / "training"
TRAINED_MODEL_PATH = Path(os.getenv("TRAINED_MODEL_PATH", str(ML_MODELS_DIR / "best_model.keras")))
LABELS_PATH = Path(os.getenv("LABELS_PATH", str(ML_TRAINING_DIR / "labels.json")))

DB_NAME = os.getenv("DB_NAME", "postgres")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "SoilCrop123")
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = int(os.getenv("DB_PORT", "5432"))

SURIGAO_CITY_CENTER = {
    "lat": 9.7845,
    "lng": 125.4888,
}

OPEN_METEO_BASE_URL = "https://api.open-meteo.com/v1/forecast"

SUPPORTED_SOIL_TYPES = (
    "Silty Clay",
    "Loam",
    "Clay Loam",
    "Clay",
    "Rock Land",
)

ALLOWED_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
