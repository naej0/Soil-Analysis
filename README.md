# Soil Backend

FastAPI backend for the Surigao City soil classification, GIS, recommendation, climate, and land lease capstone project.

## Run

1. Install dependencies:

```bash
pip install -r requirements.txt
```

2. Optional environment variables:

```bash
DB_NAME=postgres
DB_USER=postgres
DB_PASSWORD=SoilCrop123
DB_HOST=localhost
DB_PORT=5432
```

3. Start the API:

```bash
uvicorn main:app --reload
```

4. Open Swagger:

```text
http://127.0.0.1:8000/docs
```

## Notes

- Scope is limited to Surigao City.
- Supported soil types are: Silty Clay, Loam, Clay Loam, Clay, and Rock Land.
- Climate endpoints use the live Open-Meteo API.
- AI upload and prediction endpoints now expect a real trained MobileNetV2 model at `ml/models/best_model.keras` and `ml/training/labels.json`.
- `ai_predictions` is optional. If you want prediction logs saved, create that table manually in PostgreSQL.

## ML Workflow

1. Put your real soil images into:

```text
soil_images/
  Clay/
  Clay Loam/
  Loam/
  Rock Land/
  Silty Clay/
```

2. Prepare the train/validation split:

```bash
python ml/training/prepare_dataset.py --force-resplit
```

3. Train the MobileNetV2 classifier:

```bash
python ml/training/train_model.py --epochs 15 --fine-tune-epochs 5
```

4. Evaluate the saved model:

```bash
python ml/training/evaluate_model.py
```

5. Predict a single image:

```bash
python ml/training/predict_image.py --image path/to/soil_image.jpg
```

The training pipeline writes:

- `ml/models/best_model.keras`
- `ml/models/final_model.keras`
- `ml/models/training_history.json`
- `ml/models/evaluation/classification_report.json`
- `ml/models/evaluation/confusion_matrix.csv`
- `ml/models/evaluation/confusion_matrix.png`
- `ml/training/labels.json`
