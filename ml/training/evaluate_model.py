import argparse
import json
import os
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
MPL_CONFIG_DIR = PROJECT_ROOT / ".matplotlib"
MPL_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
os.environ["MPLCONFIGDIR"] = str(MPL_CONFIG_DIR)

import numpy as np
import tensorflow as tf

if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from config import LABELS_PATH, ML_MODELS_DIR, ML_VAL_DIR
from ml.utils.metrics import save_evaluation_artifacts
from ml.utils.preprocess import collect_split_records, load_labels_json


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate a trained soil classification model.")
    parser.add_argument("--model-path", type=Path, default=ML_MODELS_DIR / "best_model.keras")
    parser.add_argument("--labels-path", type=Path, default=LABELS_PATH)
    parser.add_argument("--dataset-dir", type=Path, default=ML_VAL_DIR)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--output-dir", type=Path, default=ML_MODELS_DIR / "evaluation")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    labels_payload = load_labels_json(args.labels_path)
    image_size = tuple(labels_payload.get("image_size", [224, 224]))
    class_names = labels_payload["class_names"]

    model = tf.keras.models.load_model(args.model_path)
    file_paths, labels = collect_split_records(args.dataset_dir, class_names)
    if not file_paths:
        raise ValueError(f"No evaluation images were found in {args.dataset_dir}")

    dataset = tf.data.Dataset.from_tensor_slices((file_paths, labels))
    dataset = dataset.map(
        lambda path, label: (
            tf.cast(
                tf.image.resize(tf.image.decode_jpeg(tf.io.read_file(path), channels=3), image_size),
                tf.float32,
            ),
            label,
        ),
        num_parallel_calls=tf.data.AUTOTUNE,
    ).batch(args.batch_size).prefetch(tf.data.AUTOTUNE)

    y_true = np.array(labels)
    y_probs = model.predict(dataset)
    y_pred = np.argmax(y_probs, axis=1)

    artifacts = save_evaluation_artifacts(
        y_true=y_true,
        y_pred=y_pred,
        class_names=class_names,
        output_dir=args.output_dir,
    )
    print(json.dumps(artifacts, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (FileNotFoundError, ValueError) as exc:
        raise SystemExit(f"Evaluation failed: {exc}") from exc
