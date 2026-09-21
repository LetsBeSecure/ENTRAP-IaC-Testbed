import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import classification_report, confusion_matrix
import joblib

def engineer_features(df):
    """Convert raw categorical fields into behavioral features."""
    f = pd.DataFrame()

    # Network features (keep as-is)
    for col in ["bytes_toserver", "bytes_toclient", "pkts_toserver",
                "pkts_toclient", "flow_duration", "dest_port", "src_port"]:
        f[col] = pd.to_numeric(df[col], errors="coerce").fillna(0)

    # Behavioral: is the executing binary the ransomware?
    f["exe_is_gonnacry"] = df["exe"].str.contains("gonnacry", case=False, na=False).astype(int)

    # Behavioral: is it executing from /tmp (suspicious)?
    f["exe_from_tmp"] = df["exe"].str.startswith("/tmp", na=False).astype(int)

    # Syscall type one-hot
    f["syscall_rename"] = (df["syscall"] == "rename").astype(int)
    f["syscall_execve"] = (df["syscall"] == "execve").astype(int)
    f["syscall_connect"] = (df["syscall"] == "connect").astype(int)
    f["syscall_openat"] = (df["syscall"] == "openat").astype(int)
    f["syscall_unlink"] = (df["syscall"] == "unlink").astype(int)

    # Auditd key one-hot
    f["key_file_rename"] = (df["key"] == "file_rename").astype(int)
    f["key_net_connect"] = (df["key"] == "net_connect").astype(int)
    f["key_tmp_write"] = (df["key"] == "tmp_write").astype(int)
    f["key_exec"] = (df["key"] == "exec").astype(int)

    # Event type
    f["is_flow"] = (df["event_type"] == "flow").astype(int)
    f["is_http"] = (df["event_type"] == "http").astype(int)

    # Path features: does the path contain encryption markers?
    f["path_has_gnncry"] = df["path_src"].str.contains("GNNCRY", case=False, na=False).astype(int)
    f["path_has_gonnacry_dir"] = df["path_src"].str.contains("gonnacry", case=False, na=False).astype(int)

    # Destination is C2 server?
    f["dest_is_c2"] = (df["dest_ip"] == "173.168.0.50").astype(int)

    # Destination is backup server?
    f["dest_is_backup"] = (df["dest_ip"] == "10.10.10.20").astype(int)

    return f

# ── Load and engineer training data ──
print("=== Loading training data ===")
data = pd.read_csv("dataset/dataset.csv")
y = (data["label"] == "gonnacry").astype(int)
X = engineer_features(data)

print(f"Features: {list(X.columns)}")
print(f"Shape: {X.shape}")
print(f"Labels: benign={sum(y==0)}, gonnacry={sum(y==1)}")

# ── Split ──
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

# ── Scale ──
scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled = scaler.transform(X_test)

# ── Train ──
model = RandomForestClassifier(n_estimators=100, random_state=42)
model.fit(X_train_scaled, y_train)

# ── Internal validation ──
pred = model.predict(X_test_scaled)
print("\n=== Internal Validation (80/20 split) ===")
print(classification_report(y_test, pred, target_names=["benign", "gonnacry"]))
print("Confusion Matrix:")
print(confusion_matrix(y_test, pred))

# ── Feature importance ──
importances = pd.Series(model.feature_importances_, index=X.columns)
print("\n=== Top 15 Features ===")
print(importances.sort_values(ascending=False).head(15))

# ── Save ──
joblib.dump(model, "dataset/rf_gonnacry_detector_v3.joblib")
joblib.dump(scaler, "dataset/rf_scaler_v3.joblib")
joblib.dump(list(X.columns), "dataset/rf_feature_names_v3.joblib")

# ── Cross-run evaluation ──
print("\n\n=== Cross-run Evaluation (unseen run) ===")
eval_data = pd.read_csv("dataset/dataset_eval.csv")
y_eval = (eval_data["label"] == "gonnacry").astype(int)
X_eval = engineer_features(eval_data)
X_eval_scaled = scaler.transform(X_eval)
pred_eval = model.predict(X_eval_scaled)

print(f"Eval samples: {len(y_eval)} (benign: {sum(y_eval==0)}, gonnacry: {sum(y_eval==1)})")
print(classification_report(y_eval, pred_eval, target_names=["benign", "gonnacry"]))
print("Confusion Matrix:")
print(confusion_matrix(y_eval, pred_eval))

# ── Summary ──
print("\n=== Summary ===")
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score
for name, yt, yp in [("Trained (80/20)", y_test, pred), ("Inferred (unseen)", y_eval, pred_eval)]:
    print(f"{name}: Acc={accuracy_score(yt,yp):.2f}  Prec={precision_score(yt,yp):.2f}  Rec={recall_score(yt,yp):.2f}  F1={f1_score(yt,yp):.2f}")
