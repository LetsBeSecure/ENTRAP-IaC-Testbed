import pandas as pd
import numpy as np
from sklearn.metrics import classification_report, confusion_matrix
import joblib

# Load saved model, scaler, features
model = joblib.load("dataset/rf_gonnacry_detector.joblib")
scaler = joblib.load("dataset/rf_scaler.joblib")
feature_names = joblib.load("dataset/rf_feature_names.joblib")

# Load evaluation dataset (from new unseen runs)
data = pd.read_csv("dataset/dataset_eval.csv")

print(f"Evaluation samples: {len(data)}")
print(f"Label distribution in eval set:")
print(data["label"].value_counts())

# Create binary label
data["label_binary"] = (data["label"] == "gonnacry").astype(int)

# Drop non-numeric columns
obj_cols = data.select_dtypes(include=["object"]).columns.tolist()
data_numeric = data.drop(columns=obj_cols)

# Keep only the features the model was trained on
X_eval = data_numeric[feature_names]
y_eval = data_numeric["label_binary"]

# Scale with the SAME scaler from training
X_eval_scaled = scaler.transform(X_eval)

# Predict
pred = model.predict(X_eval_scaled)
proba = model.predict_proba(X_eval_scaled)[:, 1]

# Results
print("\n=== Evaluation on Unseen Runs ===")
print(classification_report(y_eval, pred, target_names=["benign", "gonnacry"]))
print("Confusion Matrix:")
print(confusion_matrix(y_eval, pred))

# Summary
total = len(pred)
detected = sum(pred)
print(f"\nTotal events: {total}")
print(f"Detected as gonnacry: {detected}")
print(f"Detected as benign: {total - detected}")
print(f"Accuracy: {(pred == y_eval).mean():.4f}")
