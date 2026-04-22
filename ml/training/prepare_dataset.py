import argparse
import json
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from config import ML_TRAIN_DIR, ML_VAL_DIR, RAW_SOIL_DATASET_DIR
from ml.utils.preprocess import split_dataset


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare train/validation folders from the raw soil image dataset.")
    parser.add_argument("--source-dir", type=Path, default=RAW_SOIL_DATASET_DIR)
    parser.add_argument("--train-dir", type=Path, default=ML_TRAIN_DIR)
    parser.add_argument("--val-dir", type=Path, default=ML_VAL_DIR)
    parser.add_argument("--val-split", type=float, default=0.2)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--force-resplit",
        action="store_true",
        help="Delete the existing generated train/val split and rebuild it from the source dataset.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    metadata = split_dataset(
        source_dir=args.source_dir,
        train_dir=args.train_dir,
        val_dir=args.val_dir,
        val_split=args.val_split,
        seed=args.seed,
        force_resplit=args.force_resplit,
    )
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (FileNotFoundError, ValueError) as exc:
        raise SystemExit(f"Dataset preparation failed: {exc}") from exc
