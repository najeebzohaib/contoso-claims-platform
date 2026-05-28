# Databricks notebook source
# Claims Fraud Detection — MLflow + Scikit-learn
#
# Pipeline:
#   Gold Delta table → Feature engineering → 3 model comparison
#   → MLflow experiment tracking → Model Registry → Batch scoring
#
# MLflow Results (synthetic data — AUC=1.0 reflects clear signal in generated features):
#   GradientBoosting:   AUC=1.0  F1=1.0   (registered, promoted to Production)
#   RandomForest:       AUC=1.0  F1=1.0   (registered)
#   LogisticRegression: AUC=1.0  F1=0.889 (registered)
#
# Features engineered:
#   days_to_submit      — lateness of claim submission
#   amount_band         — claimed amount bucketed (0-3)
#   has_fraud_indicators — Document Intelligence fraud flags
#   docintel_confidence — extraction confidence score
#   amount_mismatch     — claimed vs extracted amount variance >10%
#   claim_type_enc      — MOTOR/PROPERTY/LIABILITY/HEALTH encoded
#
# Output: gold/delta/claims_ml_scored/ — 200 claims with ml_fraud_probability
#
# Full executable notebook: /Shared/claims_fraud_detection_mlflow in Databricks
# MLflow experiment: /Shared/claims-fraud-detection
# Model Registry: claims-fraud-gradientboosting (Production)
