import argparse
import json
import sys
from pathlib import Path

import numpy as np
import tensorflow as tf
from tensorflow.keras.applications.mobilenet_v2 import preprocess_input


PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from config import LABELS_PATH, ML_MODELS_DIR
from ml.utils.preprocess import load_image_array, load_labels_json


def predict_single_image(
    image_path: Path,
    model_path: Path,
    labels_path: Path,
    top_k: int = 3,
) -> dict:
    labels_payload = load_labels_json(labels_path)
    class_names = labels_payload["class_names"]
    image_size = tuple(labels_payload.get("image_size", [224, 224]))

    model = tf.keras.models.load_model(model_path)
    image_array = load_image_array(image_path, image_size)
    predictions = model.predict(preprocess_input(image_array), verbose=0)[0]

    top_indices = np.argsort(predictions)[::-1][:top_k]
    top_predictions = [
        {
            "soil_type": class_names[index],
            "confidence": float(predictions[index]),
        }
        for index in top_indices
    ]
    return {
        "predicted_class": top_predictions[0]["soil_type"],
        "confidence": top_predictions[0]["confidence"],
        "top_predictions": top_predictions,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Predict the soil class for a single image.")
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--model-path", type=Path, default=ML_MODELS_DIR / "best_model.keras")
    parser.add_argument("--labels-path", type=Path, default=LABELS_PATH)
    parser.add_argument("--top-k", type=int, default=3)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    result = predict_single_image(
        image_path=args.image,
        model_path=args.model_path,
        labels_path=args.labels_path,
        top_k=args.top_k,
    )
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (FileNotFoundError, ValueError) as exc:
        raise SystemExit(f"Prediction failed: {exc}") from exc
