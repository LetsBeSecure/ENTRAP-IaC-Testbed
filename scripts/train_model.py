import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import classification_report, confusion_matrix
import joblib

# Load dataset
data = pd.read_csv("dataset/dataset.csv")

# Drop non-numeric columns
obj_cols = data.select_dtypes(include=["object"]).columns.tolist()
print(f"Dropping non-numeric columns: {obj_cols}")
data_numeric = data.drop(columns=obj_cols)

# Create binary label: 1 = gonnacry, 0 = benign
data_numeric["label_binary"] = (data["label"] == "gonnacry").astype(int)

print(f"\nLabel distribution:")
print(data_numeric["label_binary"].value_counts())

# Features and labels
X = data_numeric.drop(["label_binary"], axis=1)
y = data_numeric["label_binary"]

print(f"\nFeatures: {list(X.columns)}")
print(f"Shape: {X.shape}")

# Split
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

# Scale
scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled = scaler.transform(X_test)

# Train
model = RandomForestClassifier(n_estimators=100, random_state=42)
model.fit(X_train_scaled, y_train)

# Evaluate
pred = model.predict(X_test_scaled)
print("\n=== Classification Report ===")
print(classification_report(y_test, pred, target_names=["benign", "gonnacry"]))
print("=== Confusion Matrix ===")
print(confusion_matrix(y_test, pred))

# Feature importance
importances = pd.Series(model.feature_importances_, index=X.columns)
print("\n=== Top 10 Features ===")
print(importances.sort_values(ascending=False).head(10))

# Save
joblib.dump(model, "dataset/rf_gonnacry_detector.joblib")
joblib.dump(scaler, "dataset/rf_scaler.joblib")
joblib.dump(list(X.columns), "dataset/rf_feature_names.joblib")
print("\nModel saved to dataset/rf_gonnacry_detector.joblib")
