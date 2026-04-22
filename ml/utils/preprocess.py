import json
import random
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, UnidentifiedImageError

from config import (
    ALLOWED_IMAGE_EXTENSIONS,
    LABELS_PATH,
    ML_TRAIN_DIR,
    ML_VAL_DIR,
    RAW_SOIL_DATASET_DIR,
    SUPPORTED_SOIL_TYPES,
)


def canonical_soil_class_name(class_name: str) -> str:
    normalized = class_name.strip().lower().replace("-", " ").replace("_", " ")
    normalized = " ".join(normalized.split())
    mapping = {
        "silty clay": "Silty Clay",
        "loam": "Loam",
        "clay loam": "Clay Loam",
        "clay": "Clay",
        "rock land": "Rock Land",
    }
    if normalized not in mapping:
        raise ValueError(
            f"Unsupported class folder '{class_name}'. Supported classes: {', '.join(SUPPORTED_SOIL_TYPES)}"
        )
    return mapping[normalized]


def ensure_dataset_directories(
    train_dir: Path = ML_TRAIN_DIR,
    val_dir: Path = ML_VAL_DIR,
    classes: tuple[str, ...] = SUPPORTED_SOIL_TYPES,
) -> None:
    for base_dir in (train_dir, val_dir):
        for class_name in classes:
            (base_dir / class_name).mkdir(parents=True, exist_ok=True)


def list_valid_image_files(class_dir: Path) -> list[Path]:
    image_files = []
    for file_path in sorted(class_dir.rglob("*")):
        if not file_path.is_file():
            continue
        if file_path.suffix.lower() not in ALLOWED_IMAGE_EXTENSIONS:
            continue
        if is_valid_image(file_path):
            image_files.append(file_path)
    return image_files


def is_valid_image(file_path: Path) -> bool:
    try:
        with Image.open(file_path) as image:
            image.verify()
        return True
    except (UnidentifiedImageError, OSError):
        return False


def summarize_class_directories(source_dir: Path) -> dict:
    summary = {}
    for child in sorted(source_dir.iterdir(), key=lambda item: item.name.lower()):
        if not child.is_dir():
            continue
        canonical_name = canonical_soil_class_name(child.name)
        summary[canonical_name] = list_valid_image_files(child)
    return summary


def validate_source_dataset(source_dir: Path = RAW_SOIL_DATASET_DIR) -> dict:
    source_dir = Path(source_dir)
    if not source_dir.exists():
        raise FileNotFoundError(
            f"Source dataset directory was not found: {source_dir}. "
            "Place your real soil images under soil_images/<class>/."
        )

    discovered_dirs = [child for child in source_dir.iterdir() if child.is_dir()]
    if not discovered_dirs:
        raise FileNotFoundError(
            f"No class folders were found in {source_dir}. "
            f"Create folders for: {', '.join(SUPPORTED_SOIL_TYPES)}."
        )

    summary = summarize_class_directories(source_dir)
    missing_classes = [class_name for class_name in SUPPORTED_SOIL_TYPES if class_name not in summary]
    if missing_classes:
        raise ValueError(
            "The dataset is missing required class folders: "
            + ", ".join(missing_classes)
        )

    total_images = sum(len(files) for files in summary.values())
    if total_images == 0:
        raise ValueError(
            f"No valid image files were found in {source_dir}. "
            "The class folders exist, but they are currently empty."
        )

    return summary


def reset_split_directories(train_dir: Path, val_dir: Path) -> None:
    for base_dir in (train_dir, val_dir):
        if base_dir.exists():
            shutil.rmtree(base_dir)
    ensure_dataset_directories(train_dir=train_dir, val_dir=val_dir)


def split_dataset(
    source_dir: Path = RAW_SOIL_DATASET_DIR,
    train_dir: Path = ML_TRAIN_DIR,
    val_dir: Path = ML_VAL_DIR,
    val_split: float = 0.2,
    seed: int = 42,
    force_resplit: bool = False,
) -> dict:
    source_dir = Path(source_dir)
    train_dir = Path(train_dir)
    val_dir = Path(val_dir)

    if not 0 < val_split < 1:
        raise ValueError("val_split must be between 0 and 1.")

    class_to_files = validate_source_dataset(source_dir)

    existing_train_images = sum(len(list_valid_image_files(train_dir / class_name)) for class_name in SUPPORTED_SOIL_TYPES)
    existing_val_images = sum(len(list_valid_image_files(val_dir / class_name)) for class_name in SUPPORTED_SOIL_TYPES)
    if existing_train_images or existing_val_images:
        if not force_resplit:
            return describe_split_dataset(train_dir=train_dir, val_dir=val_dir)
        reset_split_directories(train_dir, val_dir)
    else:
        ensure_dataset_directories(train_dir=train_dir, val_dir=val_dir)

    random_generator = random.Random(seed)
    split_summary = {"train": {}, "val": {}, "source": {}}

    for class_name in SUPPORTED_SOIL_TYPES:
        files = list(class_to_files[class_name])
        random_generator.shuffle(files)

        val_count = max(1, int(len(files) * val_split)) if len(files) > 1 else 0
        train_files = files[val_count:]
        val_files = files[:val_count]

        if not train_files and val_files:
            train_files, val_files = val_files, []

        destination_groups = (
            (train_dir / class_name, train_files, "train"),
            (val_dir / class_name, val_files, "val"),
        )
        for destination_dir, grouped_files, split_name in destination_groups:
            for file_path in grouped_files:
                destination_path = destination_dir / file_path.name
                copy_with_unique_name(file_path, destination_path)
            split_summary[split_name][class_name] = len(grouped_files)

        split_summary["source"][class_name] = len(files)

    metadata = {
        "source_dir": str(source_dir),
        "train_dir": str(train_dir),
        "val_dir": str(val_dir),
        "val_split": val_split,
        "seed": seed,
        "counts": split_summary,
    }
    return metadata


def copy_with_unique_name(source_path: Path, destination_path: Path) -> None:
    destination_path.parent.mkdir(parents=True, exist_ok=True)
    candidate = destination_path
    counter = 1
    while candidate.exists():
        candidate = destination_path.with_name(f"{destination_path.stem}_{counter}{destination_path.suffix}")
        counter += 1
    shutil.copy2(source_path, candidate)


def describe_split_dataset(
    train_dir: Path = ML_TRAIN_DIR,
    val_dir: Path = ML_VAL_DIR,
) -> dict:
    train_dir = Path(train_dir)
    val_dir = Path(val_dir)
    ensure_dataset_directories(train_dir=train_dir, val_dir=val_dir)

    summary = {"train": {}, "val": {}}
    for class_name in SUPPORTED_SOIL_TYPES:
        summary["train"][class_name] = len(list_valid_image_files(train_dir / class_name))
        summary["val"][class_name] = len(list_valid_image_files(val_dir / class_name))
    return summary


def save_labels_json(
    class_names: list[str],
    image_size: tuple[int, int],
    destination: Path = LABELS_PATH,
) -> dict:
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)

    payload = {
        "class_names": class_names,
        "class_to_index": {class_name: index for index, class_name in enumerate(class_names)},
        "index_to_class": {str(index): class_name for index, class_name in enumerate(class_names)},
        "image_size": list(image_size),
    }
    destination.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return payload


def load_labels_json(labels_path: Path = LABELS_PATH) -> dict:
    labels_path = Path(labels_path)
    if not labels_path.exists():
        raise FileNotFoundError(f"labels.json was not found at {labels_path}")
    return json.loads(labels_path.read_text(encoding="utf-8"))


def load_image_array(image_path: Path, image_size: tuple[int, int]) -> np.ndarray:
    with Image.open(image_path) as image:
        image = image.convert("RGB").resize(image_size)
        array = np.asarray(image, dtype=np.float32)
    return np.expand_dims(array, axis=0)


def collect_split_records(base_dir: Path, class_names: list[str] | None = None) -> tuple[list[str], list[int]]:
    base_dir = Path(base_dir)
    class_names = class_names or list(SUPPORTED_SOIL_TYPES)

    file_paths: list[str] = []
    labels: list[int] = []
    for index, class_name in enumerate(class_names):
        class_dir = base_dir / class_name
        image_files = list_valid_image_files(class_dir)
        for image_path in image_files:
            file_paths.append(str(image_path))
            labels.append(index)
    return file_paths, labels
