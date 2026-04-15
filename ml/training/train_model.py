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
from tensorflow.keras import callbacks, layers, models, optimizers
from tensorflow.keras.applications import MobileNetV2
from tensorflow.keras.applications.mobilenet_v2 import preprocess_input

if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from config import LABELS_PATH, ML_MODELS_DIR, ML_TRAIN_DIR, ML_VAL_DIR, RAW_SOIL_DATASET_DIR, SUPPORTED_SOIL_TYPES
from ml.utils.metrics import save_evaluation_artifacts, save_training_history
from ml.utils.preprocess import collect_split_records, save_labels_json, split_dataset


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train a real MobileNetV2 soil classifier.")
    parser.add_argument("--source-dir", type=Path, default=RAW_SOIL_DATASET_DIR)
    parser.add_argument("--train-dir", type=Path, default=ML_TRAIN_DIR)
    parser.add_argument("--val-dir", type=Path, default=ML_VAL_DIR)
    parser.add_argument("--model-dir", type=Path, default=ML_MODELS_DIR)
    parser.add_argument("--labels-path", type=Path, default=LABELS_PATH)
    parser.add_argument("--image-size", type=int, default=224)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--epochs", type=int, default=15)
    parser.add_argument("--fine-tune-epochs", type=int, default=5)
    parser.add_argument("--dropout-rate", type=float, default=0.2)
    parser.add_argument("--learning-rate", type=float, default=1e-4)
    parser.add_argument("--fine-tune-learning-rate", type=float, default=1e-5)
    parser.add_argument("--val-split", type=float, default=0.2)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--force-resplit", action="store_true")
    return parser.parse_args()


def decode_image(file_path, label, image_size: int):
    image = tf.io.read_file(file_path)
    image = tf.image.decode_jpeg(image, channels=3)
    image = tf.image.resize(image, [image_size, image_size])
    image = tf.cast(image, tf.float32)
    return image, label


def make_datasets(
    train_dir: Path,
    val_dir: Path,
    image_size: int,
    batch_size: int,
    seed: int,
    class_names: list[str],
):
    train_paths, train_labels = collect_split_records(train_dir, class_names)
    val_paths, val_labels = collect_split_records(val_dir, class_names)

    if not train_paths:
        raise ValueError(f"No training images were found in {train_dir}")
    if not val_paths:
        raise ValueError(f"No validation images were found in {val_dir}")

    train_dataset = tf.data.Dataset.from_tensor_slices((train_paths, train_labels))
    train_dataset = train_dataset.shuffle(len(train_paths), seed=seed, reshuffle_each_iteration=True)
    train_dataset = train_dataset.map(
        lambda path, label: decode_image(path, label, image_size),
        num_parallel_calls=tf.data.AUTOTUNE,
    )
    train_dataset = train_dataset.batch(batch_size).prefetch(tf.data.AUTOTUNE)

    val_dataset = tf.data.Dataset.from_tensor_slices((val_paths, val_labels))
    val_dataset = val_dataset.map(
        lambda path, label: decode_image(path, label, image_size),
        num_parallel_calls=tf.data.AUTOTUNE,
    )
    val_dataset = val_dataset.batch(batch_size).prefetch(tf.data.AUTOTUNE)

    return train_dataset, val_dataset, np.array(train_labels), np.array(val_labels)


def build_model(image_size: int, num_classes: int, dropout_rate: float):
    data_augmentation = tf.keras.Sequential(
        [
            layers.RandomFlip("horizontal"),
            layers.RandomRotation(0.1),
            layers.RandomZoom(0.1),
            layers.RandomContrast(0.1),
        ],
        name="augmentation",
    )

    base_model = MobileNetV2(
        input_shape=(image_size, image_size, 3),
        include_top=False,
        weights="imagenet",
    )
    base_model.trainable = False

    inputs = layers.Input(shape=(image_size, image_size, 3))
    x = data_augmentation(inputs)
    x = preprocess_input(x)
    x = base_model(x, training=False)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dropout(dropout_rate)(x)
    outputs = layers.Dense(num_classes, activation="softmax")(x)

    model = models.Model(inputs, outputs)
    return model, base_model


def compile_model(model: tf.keras.Model, learning_rate: float) -> None:
    model.compile(
        optimizer=optimizers.Adam(learning_rate=learning_rate),
        loss="sparse_categorical_crossentropy",
        metrics=[
            "accuracy",
            tf.keras.metrics.SparseTopKCategoricalAccuracy(k=3, name="top_3_accuracy"),
        ],
    )


def merge_histories(*histories: tf.keras.callbacks.History) -> dict:
    combined = {}
    for history in histories:
        if not history:
            continue
        for key, values in history.history.items():
            combined.setdefault(key, []).extend(values)
    return combined


def main() -> None:
    args = parse_args()
    args.model_dir.mkdir(parents=True, exist_ok=True)

    split_metadata = split_dataset(
        source_dir=args.source_dir,
        train_dir=args.train_dir,
        val_dir=args.val_dir,
        val_split=args.val_split,
        seed=args.seed,
        force_resplit=args.force_resplit,
    )

    class_names = list(SUPPORTED_SOIL_TYPES)
    train_dataset, val_dataset, _, val_labels = make_datasets(
        train_dir=args.train_dir,
        val_dir=args.val_dir,
        image_size=args.image_size,
        batch_size=args.batch_size,
        seed=args.seed,
        class_names=class_names,
    )

    labels_payload = save_labels_json(class_names, (args.image_size, args.image_size), destination=args.labels_path)
    (args.model_dir / "dataset_summary.json").write_text(json.dumps(split_metadata, indent=2), encoding="utf-8")

    model, base_model = build_model(
        image_size=args.image_size,
        num_classes=len(class_names),
        dropout_rate=args.dropout_rate,
    )
    compile_model(model, args.learning_rate)

    best_model_path = args.model_dir / "best_model.keras"
    final_model_path = args.model_dir / "final_model.keras"
    callbacks_list = [
        callbacks.EarlyStopping(monitor="val_loss", patience=5, restore_best_weights=True),
        callbacks.ModelCheckpoint(filepath=best_model_path, monitor="val_loss", save_best_only=True),
        callbacks.ReduceLROnPlateau(monitor="val_loss", factor=0.2, patience=2, min_lr=1e-6),
        callbacks.CSVLogger(args.model_dir / "training_log.csv"),
    ]

    initial_history = model.fit(
        train_dataset,
        validation_data=val_dataset,
        epochs=args.epochs,
        callbacks=callbacks_list,
    )

    fine_tune_history = None
    if args.fine_tune_epochs > 0:
        base_model.trainable = True
        freeze_until = max(0, len(base_model.layers) - 30)
        for layer in base_model.layers[:freeze_until]:
            layer.trainable = False

        compile_model(model, args.fine_tune_learning_rate)
        fine_tune_history = model.fit(
            train_dataset,
            validation_data=val_dataset,
            epochs=args.epochs + args.fine_tune_epochs,
            initial_epoch=args.epochs,
            callbacks=callbacks_list,
        )

    history_payload = merge_histories(initial_history, fine_tune_history)
    save_training_history(history_payload, args.model_dir / "training_history.json")

    best_model = tf.keras.models.load_model(best_model_path)
    best_model.save(final_model_path)

    with open(args.model_dir / "model_summary.txt", "w", encoding="utf-8") as summary_file:
        best_model.summary(print_fn=lambda line: summary_file.write(f"{line}\n"))

    y_probs = best_model.predict(val_dataset)
    y_pred = np.argmax(y_probs, axis=1)
    evaluation_artifacts = save_evaluation_artifacts(
        y_true=val_labels,
        y_pred=y_pred,
        class_names=class_names,
        output_dir=args.model_dir / "evaluation",
    )

    result = {
        "best_model_path": str(best_model_path),
        "final_model_path": str(final_model_path),
        "labels_path": str(args.labels_path),
        "class_names": class_names,
        "history_path": str(args.model_dir / "training_history.json"),
        "evaluation": evaluation_artifacts,
        "dataset_summary": split_metadata,
        "labels": labels_payload,
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (FileNotFoundError, ValueError) as exc:
        raise SystemExit(f"Training failed: {exc}") from exc
