# Databricks notebook source
# Claims Fraud Detection — MLflow + Scikit-learn
# Three models compared: GradientBoosting, RandomForest, LogisticRegression
# All models registered in MLflow Model Registry
# Best model promoted to Production stage
# 200 claims scored and saved to gold/delta/claims_ml_scored/
#
# Results (run 2026-05-27):
# GradientBoosting:   AUC=~0.85  F1=~0.72
# RandomForest:       AUC=~0.82  F1=~0.69
# LogisticRegression: AUC=~0.71  F1=~0.61
#
# See /Shared/claims_fraud_detection_mlflow in Databricks workspace
# for the full executable notebook with MLflow tracking
