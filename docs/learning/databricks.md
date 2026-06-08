# Module 5 — Databricks and Data Engineering
## Based on the Contoso Claims Platform

**Time to complete:** 3-4 hours
**Builds on:** Module 1 (networking), Module 2b (private endpoints)

---

## What You Will Understand After This Module

- What Databricks is and why it exists
- What Apache Spark is and why distributed computing matters
- What Delta Lake is and why it is better than plain files
- The medallion architecture — Bronze, Silver, Gold — and the reasoning behind each layer
- What MLflow is and why experiment tracking matters
- How your fraud detection pipeline works end to end
- What the Model Registry is and what "promoting to Production" means
- How Databricks connects to ADLS Gen2 in your platform
- How to read your Databricks notebooks
- What structured streaming is and how it differs from batch processing

---

## Part 1 — What Databricks Is

Databricks is a cloud data platform built on top of Apache Spark. It provides:

- **Managed Spark clusters** — you choose the VM size and number of workers, Databricks provisions and manages the cluster
- **Collaborative notebooks** — browser-based notebooks where you write Python, SQL, or Scala that runs on the cluster
- **Delta Lake** — an open-source storage format that adds ACID transactions to files on blob storage
- **MLflow** — an open-source ML lifecycle platform built into Databricks
- **Jobs and Pipelines** — scheduled or triggered notebook execution
- **Unity Catalog** — data governance and access control (not used in your platform)

**Why Databricks over plain Azure services?**

You could process data using Azure Data Factory + Azure Functions + plain Parquet files. But:

- Data Factory has no support for complex Python transformations
- Azure Functions have execution time limits unsuitable for large data processing
- Plain Parquet files have no ACID guarantees — a failed write leaves partial data
- There is no built-in experiment tracking for ML models

Databricks solves all of these in one platform.

**Why Premium tier?**

Your platform uses Databricks Premium. The key Premium feature is **Role-Based Access Control** — controlling who can access which notebooks, clusters, and data. Without Premium, any user in the workspace can see any data. For a financial services platform handling claims data, access control is mandatory.

📖 [Azure Databricks overview](https://learn.microsoft.com/en-us/azure/databricks/introduction/)
📖 [Azure Databricks pricing tiers](https://learn.microsoft.com/en-us/azure/databricks/administration-guide/account-settings/pricing)

---

## Part 2 — Apache Spark: Why Distributed Computing

Before understanding Databricks you need to understand why Spark exists.

### The single-machine problem

Imagine processing 10 million insurance claims. Each claim is one row in a CSV file. The file is 50GB.

On a single machine:
- Reading 50GB takes ~5 minutes
- Running transformations takes ~10 minutes
- Writing results takes ~5 minutes
- Total: ~20 minutes, single-threaded

This does not scale. 1 billion claims = 5TB file = hours of processing. Add machine failure halfway through and you lose all progress.

### Spark's solution: distribute the work

Spark splits the data into partitions and processes them in parallel across many machines:

```
50GB file → split into 200 partitions of 250MB each
           → 20 workers each process 10 partitions simultaneously
           → each worker finishes in ~1 minute
           → total: ~1 minute regardless of file size
```

**Your cluster:**
- 1 driver node (Standard_D4s_v5 — 4 vCPU, 16GB) — coordinates the job
- 2 worker nodes (Standard_D4s_v5 each) — process data partitions
- Total: 12 cores, 48GB RAM

For 200 claims this is enormous overkill — your pipeline runs in seconds. The architecture is designed to scale to millions of claims by adding worker nodes without changing the code.

### Spark DataFrames

Spark provides a DataFrame API similar to pandas but distributed:

```python
# pandas (single machine, all data in memory)
import pandas as pd
df = pd.read_csv("claims.csv")
df_filtered = df[df["claimed_amount"] > 10000]

# Spark (distributed, data never all in one machine's memory)
from pyspark.sql import SparkSession
spark = SparkSession.builder.getOrCreate()
df = spark.read.csv("abfss://bronze@adlsclaimsdev0bd2.dfs.core.windows.net/claims/")
df_filtered = df.filter(df["claimed_amount"] > 10000)
```

The Spark DataFrame is **lazy** — `df.filter(...)` does not immediately process data. It builds an execution plan. Processing only happens when you call an action like `.count()`, `.show()`, or `.write()`. Spark optimises the entire execution plan before running it.

📖 [Apache Spark overview](https://spark.apache.org/docs/latest/index.html)
📖 [Databricks Spark concepts](https://learn.microsoft.com/en-us/azure/databricks/getting-started/spark/)
📖 [Spark DataFrames](https://learn.microsoft.com/en-us/azure/databricks/spark/latest/dataframes-datasets/)

---

## Part 3 — ADLS Gen2: Where Your Data Lives

Azure Data Lake Storage Gen2 (ADLS Gen2) is the storage layer for your data pipeline. It is Azure Blob Storage with a hierarchical namespace — files are organised in a tree structure like a file system rather than a flat object store.

**Your storage account: `adlsclaimsdev0bd2`**

```
adlsclaimsdev0bd2 (storage account)
  ├── bronze (container)
  │     └── incoming/
  │           └── claims_2025_sample.json   (raw input data)
  │     └── delta/claims/                   (Bronze Delta table)
  │
  ├── silver (container)
  │     └── delta/claims/                   (Silver Delta table)
  │
  └── gold (container)
        └── delta/claims_risk/              (risk-scored claims)
        └── delta/claims_summary/           (aggregations)
        └── delta/claims_ml_scored/         (ML fraud probability)
```

**The abfss:// URL scheme**

ADLS Gen2 uses the `abfss://` (Azure Blob File System Secure) scheme:
```
abfss://{container}@{storage-account}.dfs.core.windows.net/{path}
```

Examples from your notebook:
```python
adls("bronze", "incoming/") 
= "abfss://bronze@adlsclaimsdev0bd2.dfs.core.windows.net/incoming/"

adls("gold", "delta/claims_risk/")
= "abfss://gold@adlsclaimsdev0bd2.dfs.core.windows.net/delta/claims_risk/"
```

**How Databricks authenticates to ADLS Gen2**

Your notebooks use a storage account key:
```python
spark.conf.set(
    "fs.azure.account.key.adlsclaimsdev0bd2.dfs.core.windows.net",
    "{storage-account-key}"
)
```

This is the simplest approach but requires a secret. In production you would use service principal authentication or managed identity — the same zero-credential pattern as Workload Identity in AKS.

📖 [ADLS Gen2 overview](https://learn.microsoft.com/en-us/azure/storage/blobs/data-lake-storage-introduction)
📖 [Connect Databricks to ADLS Gen2](https://learn.microsoft.com/en-us/azure/databricks/connect/storage/azure-storage)

---

## Part 4 — Delta Lake: Why Not Just Use CSV or Parquet?

This is the most important concept in the data engineering module.

### The problem with plain files

Imagine writing 200,000 claim records to a Parquet file. Halfway through the write, the Spark job fails (node crash, network issue, out of memory). What happens?

With plain Parquet:
```
Before write: old_claims.parquet (100,000 records — previous run)
During write: new_claims.parquet (written 87,000 of 200,000 records)
Job fails:    new_claims.parquet is now corrupt/incomplete
              old_claims.parquet may have been overwritten
Result:       You have neither the old data nor the complete new data
```

This is a data corruption problem. In a financial platform, corrupted data means incorrect risk scores, missed fraud detection, and potentially wrong payment decisions.

### What Delta Lake adds

Delta Lake is a storage layer that sits on top of Parquet files and adds:

**ACID Transactions** — Atomicity, Consistency, Isolation, Durability:
- *Atomicity:* a write either fully succeeds or fully fails. No partial writes.
- *Consistency:* the data always matches the schema. No corrupt rows.
- *Isolation:* concurrent reads and writes do not interfere with each other.
- *Durability:* once a write is committed, it is permanent even if a machine crashes.

**How Delta achieves atomicity:**

Delta Lake maintains a `_delta_log/` directory alongside the data files:
```
gold/delta/claims_risk/
  ├── _delta_log/
  │     ├── 00000000000000000000.json   (transaction 0 — table creation)
  │     ├── 00000000000000000001.json   (transaction 1 — first write)
  │     ├── 00000000000000000002.json   (transaction 2 — second write)
  │     └── 00000000000000000010.checkpoint.parquet (checkpoint every 10 commits)
  ├── part-00000-abc123.parquet
  ├── part-00001-def456.parquet
  └── part-00002-ghi789.parquet
```

When Spark writes data:
1. Writes new Parquet files (they are not yet part of the table)
2. Atomically writes a new transaction log entry listing the new files
3. The transaction log entry is a single file write — atomic at the filesystem level

If step 2 fails, the new Parquet files exist but are not in the transaction log — they are orphaned and ignored by subsequent reads. The table remains in its previous consistent state.

**Time Travel**

Every transaction log entry is preserved. This means you can query the table as it appeared at any point in time:

```python
# Query the table as it was 5 writes ago
df = spark.read.format("delta") \
    .option("versionAsOf", 5) \
    .load("abfss://gold@adlsclaimsdev0bd2.dfs.core.windows.net/delta/claims_risk/")

# Query the table as it was yesterday at 9am
df = spark.read.format("delta") \
    .option("timestampAsOf", "2026-05-27 09:00:00") \
    .load("abfss://gold@adlsclaimsdev0bd2.dfs.core.windows.net/delta/claims_risk/")
```

For insurance claims this is essential. A regulator asks: "What did your risk model show for claim CLM-123 on May 15th?" You can answer exactly because Delta preserves the full history.

**Schema Enforcement**

Delta rejects writes that do not match the table schema:
```python
# Table schema has "claimed_amount" as Double
# Writing a row with "claimed_amount" as String fails immediately
# Rather than silently corrupting the table
```

**Upserts (MERGE)**

Delta supports updating existing records efficiently:
```python
# Update all claims where status has changed
delta_table.alias("target").merge(
    new_data.alias("source"),
    "target.claim_id = source.claim_id"
).whenMatchedUpdateAll() \
 .whenNotMatchedInsertAll() \
 .execute()
```

Plain Parquet has no efficient update mechanism — you must rewrite the entire file.

📖 [Delta Lake documentation](https://docs.delta.io/latest/index.html)
📖 [Delta Lake on Azure Databricks](https://learn.microsoft.com/en-us/azure/databricks/delta/)
📖 [Delta Lake time travel](https://learn.microsoft.com/en-us/azure/databricks/delta/history)
📖 [Delta Lake ACID transactions](https://learn.microsoft.com/en-us/azure/databricks/delta/concurrency-control)

---

## Part 5 — The Medallion Architecture in Detail

The medallion architecture organises data into three layers with increasing quality and decreasing volume at each layer.

### Why three layers?

A single "processed data" layer creates a dilemma: do you keep the original messy data or the cleaned data? If you keep only cleaned data and discover a cleaning bug months later, you cannot reprocess — the original data is gone.

The medallion architecture keeps everything:
- Bronze: original data, never touched after initial write
- Silver: cleaned version — can always be regenerated from Bronze
- Gold: business-ready version — can always be regenerated from Silver

If a Gold table has wrong risk scores due to a bug in the risk scoring logic, you fix the logic and rerun from Silver. You do not need to re-ingest data from the source.

### Bronze — Raw Truth

```python
# Bronze: read raw JSON, add metadata, write to Delta
df_raw = (spark.read
    .schema(BRONZE_SCHEMA)         # apply schema on read
    .json(adls("bronze", "incoming/"))
    .withColumn("_ingested_at", current_timestamp())
    .withColumn("_source_file", input_file_name())
    .withColumn("_record_hash", sha2(concat_ws("|", 
        col("claim_id"), col("claimed_amount")), 256))
)

df_raw.write \
    .format("delta") \
    .mode("overwrite") \
    .save(adls("bronze", "delta/claims/"))
```

**Rules for Bronze:**
- Never modify records after writing
- Never delete records
- Store exactly what arrived, including duplicates
- Add provenance metadata (`_ingested_at`, `_source_file`)
- Write in append or overwrite mode — never update

Bronze is your legal audit trail. If a fraud investigation asks "what data did you receive and when?", Bronze answers that question definitively.

### Silver — Trusted Data

```python
# Silver: read Bronze, apply transformations and DQ checks
df_bronze = spark.read.format("delta").load(adls("bronze", "delta/claims/"))

df_silver = (df_bronze
    # Type normalisation
    .withColumn("incident_date", to_timestamp("incident_date", "yyyy-MM-dd"))
    .withColumn("submission_date", to_timestamp("submission_date", "yyyy-MM-dd"))
    .withColumn("claim_type", upper(trim(col("claim_type"))))
    .withColumn("claimed_amount", col("claimed_amount").cast("double"))
    
    # Parse Document Intelligence JSON
    .withColumn("docintel", from_json(col("extracted_fields"), DOCINTEL_SCHEMA))
    .withColumn("docintel_confidence", col("docintel.confidence"))
    .withColumn("docintel_fraud_indicators", col("docintel.fraud_indicators"))
    .withColumn("docintel_amount_extracted", col("docintel.amount_extracted"))
    
    # Data Quality flags (never filter, always flag)
    .withColumn("dq_missing_policy",
        col("policy_number").isNull() | (col("policy_number") == ""))
    .withColumn("dq_amount_mismatch",
        when(col("docintel_amount_extracted").isNotNull(),
            abs(col("claimed_amount") - col("docintel_amount_extracted")) 
            / col("claimed_amount") > 0.1
        ).otherwise(False))
    .withColumn("dq_low_confidence",
        col("docintel_confidence") < 0.7)
    
    # Deduplication
    .dropDuplicates(["claim_id"])
    
    .drop("docintel", "extracted_fields")
)

df_silver.write \
    .format("delta") \
    .mode("overwrite") \
    .save(adls("silver", "delta/claims/"))
```

**Key Silver principle — flag, never filter:**

```python
# WRONG: removes bad data, destroys audit trail
df_silver = df_bronze.filter(col("docintel_confidence") >= 0.7)

# RIGHT: marks bad data, preserves everything
df_silver = df_bronze.withColumn("dq_low_confidence",
    col("docintel_confidence") < 0.7)
```

The downstream Gold layer and ML models decide what to do with flagged data. Silver never makes that decision.

### Gold — Business Ready

```python
# Gold: apply business logic and risk scoring
df_silver = spark.read.format("delta").load(adls("silver", "delta/claims/"))

df_risk = (df_silver
    .withColumn("days_to_submit",
        datediff(col("submission_date"), col("incident_date")))
    
    .withColumn("risk_score",
        when(col("docintel_fraud_indicators").isNotNull(), 0.8)
        .when(col("dq_amount_mismatch"), 0.7)
        .when(col("dq_low_confidence"), 0.6)
        .when(col("days_to_submit") > 180, 0.7)
        .when(col("days_to_submit") > 90, 0.5)
        .otherwise(0.1))
    
    .withColumn("risk_band",
        when(col("risk_score") >= 0.7, "HIGH")
        .when(col("risk_score") >= 0.5, "MEDIUM")
        .otherwise("LOW"))
)

df_risk.write \
    .format("delta") \
    .mode("overwrite") \
    .save(adls("gold", "delta/claims_risk/"))
```

Gold tables are optimised for consumption. You might create multiple Gold tables from the same Silver data, each serving a different consumer:
- `claims_risk` — for the fraud investigation team (per-claim detail)
- `claims_summary` — for executive dashboards (aggregations)
- `claims_ml_scored` — for the ML model output

📖 [Medallion architecture](https://www.databricks.com/glossary/medallion-architecture)
📖 [Delta Lake best practices](https://learn.microsoft.com/en-us/azure/databricks/delta/best-practices)

---

## Part 6 — MLflow: The ML Lifecycle Platform

### The problem MLflow solves

Without MLflow, ML development looks like this:

```
Week 1: Train model with learning_rate=0.1, AUC=0.82 — save to model_v1.pkl
Week 2: Try learning_rate=0.05, AUC=0.79 — hmm, worse. What was the old result?
Week 3: Try n_estimators=200, AUC=0.84 — better! But what exact parameters?
Week 4: Need to deploy the best model. Which pkl file was it? What AUC did it get?
Week 5: The model in production gives wrong predictions. What version is it?
```

This is unmanageable. MLflow provides structure:

**Experiment Tracking** — every training run logs parameters and metrics automatically. You can compare all runs in a table or chart.

**Model Registry** — a central store for trained models with version control and stage promotion (Staging → Production → Archived).

**Reproducibility** — every run logs the exact code version, parameters, and environment. You can reproduce any run exactly.

### Your MLflow experiment

```python
import mlflow
import mlflow.sklearn

# Set the experiment — creates it if it doesn't exist
mlflow.set_experiment("/Shared/claims-fraud-detection")

# Each model training is one run
with mlflow.start_run(run_name="GradientBoosting"):
    
    # Log all hyperparameters
    mlflow.log_params(model.get_params())
    # Logs: n_estimators=100, max_depth=4, learning_rate=0.1, etc.
    
    # Train the model
    model.fit(X_train, y_train)
    
    # Calculate metrics
    y_pred = model.predict(X_test)
    y_prob = model.predict_proba(X_test)[:, 1]
    auc = roc_auc_score(y_test, y_prob)
    f1 = f1_score(y_test, y_pred)
    
    # Log all metrics
    mlflow.log_metrics({
        "roc_auc": auc,
        "f1": f1,
        "precision": precision_score(y_test, y_pred),
        "recall": recall_score(y_test, y_pred),
        "cv_auc_mean": cross_val_score(model, X, y, cv=5, scoring="roc_auc").mean()
    })
    
    # Log the model with its input/output signature
    signature = infer_signature(X_train, y_pred)
    mlflow.sklearn.log_model(
        model,
        "model",
        signature=signature,
        registered_model_name="claims-fraud-gradientboosting"
    )
```

**`infer_signature`** — records the expected input columns and types, and the output type. When the model is deployed, this signature validates that incoming data matches what the model was trained on. Prevents silent failures from column name typos or type mismatches.

### MLflow Run Structure

Each run stores:

```
Run: GradientBoosting (run_id: 373a5e7e...)
  Parameters:
    n_estimators: 100
    max_depth: 4
    learning_rate: 0.1
    random_state: 42
    ... (20 parameters total)
  
  Metrics:
    roc_auc: 1.0
    f1: 1.0
    precision: 1.0
    recall: 1.0
    cv_auc_mean: 1.0
  
  Artifacts:
    model/
      MLmodel          (metadata file)
      model.pkl        (serialised sklearn model)
      conda.yaml       (Python environment)
      requirements.txt (pip requirements)
      input_example.json
```

Everything needed to reproduce and deploy the model is stored in the run.

📖 [MLflow overview](https://mlflow.org/docs/latest/index.html)
📖 [MLflow on Databricks](https://learn.microsoft.com/en-us/azure/databricks/mlflow/)
📖 [MLflow tracking](https://mlflow.org/docs/latest/tracking.html)
📖 [MLflow model registry](https://mlflow.org/docs/latest/model-registry.html)

---

## Part 7 — The Model Registry and Production Promotion

The MLflow Model Registry is a centralised store for production-ready models. It tracks model versions and their lifecycle stages.

### Stages

```
None → Staging → Production → Archived
```

**None** — freshly registered, not yet validated for production

**Staging** — under evaluation. Run integration tests, validate on holdout data, get business sign-off.

**Production** — the model actively used for scoring. At most one version per model should be in Production at a time.

**Archived** — retired but preserved. Not used for scoring but available for audit.

### Your platform's model lifecycle

```
Run 1 (fraud-detection-mlflow-v2):
  GradientBoosting trained → registered as claims-fraud-gradientboosting v1 (None)
  RandomForest trained → registered as claims-fraud-randomforest v1 (None)
  LogisticRegression trained → registered as claims-fraud-logisticregression v1 (None)

Run 2 (fraud-detection-mlflow-v3):
  All 3 models retrained → v2 of each registered

Manual action:
  claims-fraud-gradientboosting v2 → transitioned to Production
  Activity log: "applied a stage transition None → Production"
```

In production, the scoring service loads the Production model:

```python
import mlflow.sklearn

# Always load whatever is currently in Production
# No hardcoded version numbers
model = mlflow.sklearn.load_model(
    "models:/claims-fraud-gradientboosting/Production"
)

# Score new claims
fraud_probability = model.predict_proba(features)[:, 1]
```

When you promote a new model version to Production, this code automatically uses the new model without any code changes — the model name stays the same but `Production` now resolves to the new version.

### Why AUC = 1.0 on your data

Your models achieved perfect AUC because the features directly encode the label. Specifically:

- `has_fraud_indicators` — derived from `docintel_fraud_indicators`, which is set when `risk_band = HIGH` in the synthetic data generation
- The model learns: `has_fraud_indicators = True → is_fraud = True`

This is circular — the feature and the label come from the same source. It means the model has learned the rules rather than generalised patterns.

In real insurance fraud detection:
- Labels come from confirmed fraud investigations (months after the claim)
- Features come from claim submission data at the time of filing
- There is genuine uncertainty — fraudulent claims often look legitimate initially
- AUC of 0.75-0.85 is typical for well-designed models
- AUC of 1.0 would indicate data leakage (future information in features)

Your pipeline's architecture is production-quality. The data characteristics are synthetic.

📖 [MLflow Model Registry](https://mlflow.org/docs/latest/model-registry.html)
📖 [MLflow model deployment](https://learn.microsoft.com/en-us/azure/databricks/mlflow/models)

---

## Part 8 — Feature Engineering: Turning Raw Data into ML Inputs

Machine learning models cannot work directly on raw text. You must convert raw claim data into numerical features.

### Your features and why each was chosen

```python
FEATURES = [
    "days_to_submit",        # How many days between incident and filing
    "amount_band",           # Claimed amount bucketed into 4 bands
    "has_fraud_indicators",  # Document Intelligence fraud flags (0 or 1)
    "low_confidence",        # Document Intelligence confidence < 0.7 (0 or 1)
    "amount_mismatch",       # Claimed vs extracted amount >10% (0 or 1)
    "claim_type_enc",        # MOTOR=0, PROPERTY=1, LIABILITY=2, HEALTH=3
    "claimed_amount",        # Raw amount in GBP
    "docintel_confidence"    # 0.0 to 1.0 confidence score
]
```

**days_to_submit:** Fraudulent claims are often filed late — the fraudster needs time to fabricate a plausible story and gather fake documentation. Real claims are typically filed within 30 days. A claim filed 200 days after the incident is suspicious.

```python
.withColumn("days_to_submit",
    datediff(col("submission_date"), col("incident_date")))
```

**amount_band:** Rather than using the raw amount (which varies from £1,000 to £200,000+), bucketing into bands makes the feature more robust to outliers:

```python
.withColumn("amount_band",
    when(col("claimed_amount") < 5000, 0)     # small claim
    .when(col("claimed_amount") < 20000, 1)    # medium claim  
    .when(col("claimed_amount") < 50000, 2)    # large claim
    .otherwise(3))                             # very large claim
```

**claim_type_enc:** The model needs numbers, not strings. Encoding converts categorical values to integers:

```python
.withColumn("claim_type_enc",
    when(col("claim_type") == "MOTOR", 0)
    .when(col("claim_type") == "PROPERTY", 1)
    .when(col("claim_type") == "LIABILITY", 2)
    .otherwise(3))  # HEALTH or unknown
```

### Why GradientBoosting outperforms LogisticRegression here

| Model | AUC | F1 | Why |
|-------|-----|----|----|
| GradientBoosting | 1.0 | 1.0 | Handles non-linear relationships, feature interactions |
| RandomForest | 1.0 | 1.0 | Ensemble method, robust to noise |
| LogisticRegression | 1.0 | 0.889 | Linear model — assumes linear relationship between features and label |

LogisticRegression's lower F1 (0.889 vs 1.0) shows it struggles with the non-linear decision boundary. In real data the gap would be more pronounced. GradientBoosting typically performs best on tabular data with mixed feature types.

📖 [Feature engineering in Databricks](https://learn.microsoft.com/en-us/azure/databricks/machine-learning/feature-store/)
📖 [Scikit-learn GradientBoostingClassifier](https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.GradientBoostingClassifier.html)

---

## Part 9 — Structured Streaming

Your platform includes a structured streaming notebook (`claims_structured_streaming`) that demonstrates real-time claim processing.

### Batch vs streaming

**Batch processing** — processes a fixed dataset on a schedule:
```
Every hour: read all new claims from Bronze, transform, write to Silver
Latency: up to 60 minutes between ingestion and availability in Silver
```

**Streaming processing** — processes events as they arrive:
```
New claim file lands in Bronze → triggers processing immediately
Latency: seconds between ingestion and availability in Silver
```

### Auto Loader (cloudFiles)

Auto Loader is Databricks' mechanism for incrementally ingesting files as they land in cloud storage:

```python
stream_df = (spark.readStream
    .format("cloudFiles")
    .option("cloudFiles.format", "json")
    .option("cloudFiles.schemaLocation", adls("bronze", "streaming/_schema"))
    .schema(CLAIM_SCHEMA)
    .load(adls("bronze", "streaming/claims/"))
)
```

`cloudFiles` monitors the specified directory for new files. When a new JSON file lands, Spark reads it and adds it to the stream. The `schemaLocation` stores the inferred schema so Auto Loader does not re-infer it on every restart.

### Writing a stream to Delta Lake

```python
query = (transformed_stream.writeStream
    .format("delta")
    .outputMode("append")
    .option("checkpointLocation", adls("silver", "streaming/_checkpoint"))
    .trigger(availableNow=True)    # process all available data then stop
    .start(adls("silver", "delta/claims_streaming/"))
)

query.awaitTermination()
```

**Checkpoint:** The checkpoint directory stores the stream's progress — which files have been processed. If the job fails and restarts, it resumes from where it left off. Without a checkpoint, it would reprocess everything, creating duplicates.

**outputMode("append"):** New records are appended to the Delta table. Never updates or deletes. Suitable for event streams where each event is distinct.

**trigger(availableNow=True):** Process all currently available data and stop. This is micro-batch mode — run the stream as a batch job. True continuous streaming (always running) would use `trigger(processingTime="30 seconds")` instead.

📖 [Databricks Structured Streaming](https://learn.microsoft.com/en-us/azure/databricks/structured-streaming/)
📖 [Auto Loader](https://learn.microsoft.com/en-us/azure/databricks/ingestion/auto-loader/)
📖 [Stream-static joins](https://learn.microsoft.com/en-us/azure/databricks/structured-streaming/delta-lake)

---

## Part 10 — Databricks Clusters

A Databricks cluster is a set of VMs that run Spark. Your platform uses an all-purpose cluster (`claims-pipeline-v2` / `claims-demo-cluster`).

### Cluster configuration

```
Cluster name:    claims-demo-cluster
Runtime:         15.4 LTS (Apache Spark 3.5.0, Scala 2.12)
Worker type:     Standard_D4s_v5 (16GB, 4 cores)
Workers:         2
Driver type:     Standard_D4s_v5
Total:           3 nodes, 48GB RAM, 12 cores
Auto-terminate:  30 minutes of inactivity
Price:           3 DBU/hour
```

**DBU (Databricks Unit)** — Databricks' billing unit. 1 DBU is roughly 1 Standard_D4s_v5 core-hour. At 3 DBU/hour for your cluster, a 30-minute job costs 1.5 DBU.

**Runtime 15.4 LTS** — LTS means Long Term Support. Databricks guarantees patches and support for LTS versions for 2 years. Use LTS for production — avoid latest non-LTS runtimes which may have breaking changes.

**Auto-terminate 30 minutes** — the most important cost control setting. A cluster left running costs ~£3-5/hour even with no jobs running. Auto-terminate ensures the cluster shuts down automatically after 30 minutes of no activity. This is why you had to restart the cluster at the beginning of each session.

### Cluster startup time

A Databricks cluster takes 4-7 minutes to start from terminated state. This is because Azure must provision the VMs (VMSS instances), install Databricks Runtime, and initialise Spark. This is the main operational friction with Databricks — planning around cold start time.

For production pipelines, you would either:
- Keep the cluster running (expensive but no cold start)
- Use a job cluster — a cluster created specifically for one job, terminated when done
- Use serverless compute (Databricks Serverless) which starts in seconds

📖 [Databricks cluster configuration](https://learn.microsoft.com/en-us/azure/databricks/compute/configure)
📖 [Databricks runtime versions](https://learn.microsoft.com/en-us/azure/databricks/release-notes/runtime/)
📖 [Cluster auto-termination](https://learn.microsoft.com/en-us/azure/databricks/compute/clusters-manage#automatic-termination)

---

## Part 11 — Jobs and Pipelines

A Databricks Job is a scheduled or triggered run of one or more notebooks or scripts.

### Your job runs

From your screenshots, the job runs table showed:

| Job name | Status | Duration | Launched by |
|----------|--------|----------|-------------|
| fraud-detection-mlflow-v3 | Succeeded | 19s | runs submit API |
| claims-dashboard-v2 | Succeeded | 19s | runs submit API |
| medallion-stats | Succeeded | 31s | runs submit API |
| medallion-run-4 | Succeeded | 1m 32s | runs submit API |

"By runs submit API" means the job was triggered via the REST API — which is what your terminal commands did (`curl .../jobs/runs/submit`).

### How you triggered jobs from the terminal

```bash
# Submit a notebook as a job
RUN_ID=$(curl -s -X POST "https://$DBW_URL/api/2.0/jobs/runs/submit" \
  -H "Authorization: Bearer $DBW_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"run_name\": \"fraud-detection-mlflow-v3\",
    \"existing_cluster_id\": \"$NEW_CLUSTER\",
    \"notebook_task\": {
      \"notebook_path\": \"/Shared/claims_fraud_detection_mlflow\"
    }
  }" | python3 -c "import sys,json; print(json.load(sys.stdin)['run_id'])")
```

This is the Databricks REST API. Everything you can do in the UI you can also do via API — create clusters, run notebooks, check run status, download results.

📖 [Databricks Jobs](https://learn.microsoft.com/en-us/azure/databricks/workflows/jobs/jobs)
📖 [Databricks REST API](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/api/)

---

## Part 12 — Reading Your Notebook Code

Your notebooks follow a consistent structure. Here is how to read them.

### Notebook cell types

```python
# MAGIC %md
# MAGIC # This is a markdown cell — documentation, not code
```

```python
# COMMAND ----------
# This is a Python cell — runs on the Spark cluster
df = spark.read.format("delta").load(adls("gold", "delta/claims_risk/"))
```

```python
# MAGIC %sql
# MAGIC SELECT risk_band, COUNT(*) FROM claims_risk GROUP BY risk_band
```

### The `display()` function

```python
display(df)  # Shows a formatted interactive table in the notebook
display(fig) # Shows a matplotlib figure inline
```

`display()` is a Databricks-specific function. It renders DataFrames as interactive tables with sorting and filtering. Outside Databricks (e.g. in plain Python), you would use `df.show()` or `print()`.

### The `dbutils` library

```python
# dbutils is a Databricks utility library
dbutils.fs.ls("abfss://gold@adlsclaimsdev0bd2.dfs.core.windows.net/")
# Lists files in ADLS Gen2

dbutils.secrets.get(scope="claims-kv", key="datalake-name")
# Reads a secret from a Databricks secret scope

dbutils.notebook.run("/Shared/claims_medallion_v2", timeout_seconds=600)
# Runs another notebook as a sub-notebook
```

`dbutils` only works inside Databricks notebooks — it is not available in regular Python.

📖 [Databricks notebooks](https://learn.microsoft.com/en-us/azure/databricks/notebooks/)
📖 [dbutils reference](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/databricks-utils)

---

## Summary

| Concept | Your Platform | Key Point |
|---------|--------------|-----------|
| Databricks | `dbw-claims-dev-uks`, Premium | Managed Spark — distributed processing + Delta Lake + MLflow |
| Apache Spark | Runtime 15.4 LTS | Distributes data processing across multiple nodes |
| ADLS Gen2 | `adlsclaimsdev0bd2` | Hierarchical blob storage — bronze/silver/gold containers |
| Delta Lake | All three layers | ACID transactions, time travel, schema enforcement on blob storage |
| Bronze | Raw JSON claims | Immutable audit log — never modified |
| Silver | Validated + DQ flags | Type-cast, deduplicated, quality-flagged — never filtered |
| Gold | Risk-scored claims | Business-ready — per-claim risk, aggregations, ML scores |
| MLflow | `/Shared/claims-fraud-detection` | Experiment tracking — every run logged permanently |
| Model Registry | 3 models, v2 each | GradientBoosting promoted to Production |
| Feature engineering | 8 features from Gold table | days_to_submit, amount_band, fraud indicators etc. |
| Structured Streaming | Auto Loader + Delta sink | Real-time ingestion with exactly-once guarantees |
| Cluster | `claims-demo-cluster`, 2 workers | Auto-terminates after 30 min — critical cost control |

---

## Documentation Reference

📖 [Azure Databricks documentation hub](https://learn.microsoft.com/en-us/azure/databricks/)
📖 [Apache Spark documentation](https://spark.apache.org/docs/latest/)
📖 [Delta Lake documentation](https://docs.delta.io/latest/index.html)
📖 [Delta Lake on Databricks](https://learn.microsoft.com/en-us/azure/databricks/delta/)
📖 [Delta Lake time travel](https://learn.microsoft.com/en-us/azure/databricks/delta/history)
📖 [Medallion architecture](https://www.databricks.com/glossary/medallion-architecture)
📖 [MLflow documentation](https://mlflow.org/docs/latest/index.html)
📖 [MLflow on Databricks](https://learn.microsoft.com/en-us/azure/databricks/mlflow/)
📖 [MLflow Model Registry](https://mlflow.org/docs/latest/model-registry.html)
📖 [Databricks Structured Streaming](https://learn.microsoft.com/en-us/azure/databricks/structured-streaming/)
📖 [Auto Loader](https://learn.microsoft.com/en-us/azure/databricks/ingestion/auto-loader/)
📖 [ADLS Gen2 overview](https://learn.microsoft.com/en-us/azure/storage/blobs/data-lake-storage-introduction)
📖 [Databricks cluster configuration](https://learn.microsoft.com/en-us/azure/databricks/compute/configure)
📖 [Databricks Jobs](https://learn.microsoft.com/en-us/azure/databricks/workflows/jobs/jobs)
📖 [dbutils reference](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/databricks-utils)
📖 [Databricks notebooks](https://learn.microsoft.com/en-us/azure/databricks/notebooks/)

---

## AZ-305 Exam Alignment

**Domain 2: Design Data Storage Solutions (25-30%)**
- Design data storage solutions for relational and non-relational data
- Design data integration solutions

📖 [AZ-305 exam skills outline](https://learn.microsoft.com/en-us/credentials/certifications/exams/az-305/)
📖 [Azure data architecture guide](https://learn.microsoft.com/en-us/azure/architecture/data-guide/)
📖 [Lambda and Kappa architecture patterns](https://learn.microsoft.com/en-us/azure/architecture/data-guide/big-data/)
📖 [Choose a data pipeline orchestration technology](https://learn.microsoft.com/en-us/azure/architecture/data-guide/technology-choices/pipeline-orchestration-data-movement)

---

*Next: Module 6 — Terraform and Infrastructure as Code*
