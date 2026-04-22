import os
import json
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
MPL_CONFIG_DIR = PROJECT_ROOT / ".matplotlib"
MPL_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
os.environ["MPLCONFIGDIR"] = str(MPL_CONFIG_DIR)

import matplotlib.pyplot as plt
import numpy as np
import seaborn as sns
from sklearn.metrics import classification_report, confusion_matrix


def save_training_history(history: dict, output_path: Path) -> None:
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(history, indent=2), encoding="utf-8")


def save_evaluation_artifacts(
    y_true: np.ndarray,
    y_pred: np.ndarray,
    class_names: list[str],
    output_dir: Path,
) -> dict:
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    report = classification_report(
        y_true,
        y_pred,
        target_names=class_names,
        output_dict=True,
        zero_division=0,
    )
    report_path = output_dir / "classification_report.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    matrix = confusion_matrix(y_true, y_pred)
    matrix_path = output_dir / "confusion_matrix.csv"
    np.savetxt(matrix_path, matrix, fmt="%d", delimiter=",")

    figure_path = output_dir / "confusion_matrix.png"
    save_confusion_matrix_plot(matrix, class_names, figure_path)

    return {
        "classification_report_path": str(report_path),
        "confusion_matrix_csv_path": str(matrix_path),
        "confusion_matrix_png_path": str(figure_path),
    }


def save_confusion_matrix_plot(matrix: np.ndarray, class_names: list[str], output_path: Path) -> None:
    plt.figure(figsize=(8, 6))
    sns.heatmap(matrix, annot=True, fmt="d", cmap="Blues", xticklabels=class_names, yticklabels=class_names)
    plt.xlabel("Predicted Label")
    plt.ylabel("True Label")
    plt.title("Soil Classification Confusion Matrix")
    plt.tight_layout()
    plt.savefig(output_path)
    plt.close()
