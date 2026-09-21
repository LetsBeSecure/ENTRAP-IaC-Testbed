import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import classification_report, confusion_matrix
import joblib

# Load training dataset
data = pd.read_csv("dataset/dataset.csv")

# Drop non-numeric columns
obj_cols = data.select_dtypes(include=["object"]).columns.tolist()
data_numeric = data.drop(columns=obj_cols)

# Create binary label
data_numeric["label_binary"] = (data["label"] == "gonnacry").astype(int)

# Drop identifier columns — these are labels, not features
drop_ids = ["uid", "pid", "auid"]
data_numeric = data_numeric.drop(columns=drop_ids, errors="ignore")

# Features and labels
X = data_numeric.drop(["label_binary"], axis=1)
y = data_numeric["label_binary"]

print(f"Features after dropping identifiers: {list(X.columns)}")
print(f"Shape: {X.shape}")
print(f"\nLabel distribution:\n{y.value_counts()}")

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

# Evaluate on internal split
pred = model.predict(X_test_scaled)
print("\n=== Internal Validation (80/20 split) ===")
print(classification_report(y_test, pred, target_names=["benign", "gonnacry"]))
print("Confusion Matrix:")
print(confusion_matrix(y_test, pred))

# Feature importance
importances = pd.Series(model.feature_importances_, index=X.columns)
print("\n=== Top 10 Features ===")
print(importances.sort_values(ascending=False).head(10))

# Save v2 model
joblib.dump(model, "dataset/rf_gonnacry_detector_v2.joblib")
joblib.dump(scaler, "dataset/rf_scaler_v2.joblib")
joblib.dump(list(X.columns), "dataset/rf_feature_names_v2.joblib")

# ── Now evaluate on unseen run ──
print("\n\n=== Cross-run Evaluation (unseen run) ===")
eval_data = pd.read_csv("dataset/dataset_eval.csv")
eval_data["label_binary"] = (eval_data["label"] == "gonnacry").astype(int)
eval_numeric = eval_data.drop(columns=eval_data.select_dtypes(include=["object"]).columns)
eval_numeric = eval_numeric.drop(columns=drop_ids, errors="ignore")

X_eval = eval_numeric[list(X.columns)]
y_eval = eval_numeric["label_binary"]

X_eval_scaled = scaler.transform(X_eval)
pred_eval = model.predict(X_eval_scaled)

print(f"Eval samples: {len(y_eval)} (benign: {sum(y_eval==0)}, gonnacry: {sum(y_eval==1)})")
print(classification_report(y_eval, pred_eval, target_names=["benign", "gonnacry"]))
print("Confusion Matrix:")
print(confusion_matrix(y_eval, pred_eval))

# Summary comparison
print("\n=== Summary ===")
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score
for name, yt, yp in [("Trained (80/20)", y_test, pred), ("Inferred (unseen)", y_eval, pred_eval)]:
    print(f"{name}: Acc={accuracy_score(yt,yp):.2f}  Prec={precision_score(yt,yp):.2f}  Rec={recall_score(yt,yp):.2f}  F1={f1_score(yt,yp):.2f}")
