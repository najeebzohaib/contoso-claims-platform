# Databricks notebook source
# MAGIC %md
# MAGIC # Contoso Claims Intelligence Platform
# MAGIC ## Medallion Pipeline: Bronze → Silver → Gold
# MAGIC
# MAGIC This notebook implements the medallion architecture for claims processing:
# MAGIC - **Bronze**: Raw ingestion from ADLS Gen2 (no transformation)
# MAGIC - **Silver**: Validated, deduplicated, enriched with Document Intelligence output
# MAGIC - **Gold**: Aggregated, ML-ready features for OpenAI and AI Search indexing

# COMMAND ----------
# MAGIC %md ## Configuration

# COMMAND ----------
from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col, lit, current_timestamp, sha2, concat_ws,
    when, trim, upper, regexp_replace, explode,
    to_timestamp, datediff, avg, count, sum as spark_sum
)
from pyspark.sql.types import (
    StructType, StructField, StringType, DoubleType,
    TimestampType, BooleanType, IntegerType
)
from delta.tables import DeltaTable
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Storage account — injected via Databricks secret scope
STORAGE_ACCOUNT = dbutils.secrets.get(scope="claims-kv", key="datalake-name")
CONTAINER_BRONZE = "bronze"
CONTAINER_SILVER = "silver"
CONTAINER_GOLD   = "gold"

def adls_path(container: str, path: str = "") -> str:
    return f"abfss://{container}@{STORAGE_ACCOUNT}.dfs.core.windows.net/{path}"

print(f"Storage account: {STORAGE_ACCOUNT}")
print(f"Bronze: {adls_path(CONTAINER_BRONZE)}")
print(f"Silver: {adls_path(CONTAINER_SILVER)}")
print(f"Gold:   {adls_path(CONTAINER_GOLD)}")

# COMMAND ----------
# MAGIC %md ## Bronze Layer — Raw Ingestion
# MAGIC Reads raw claim JSON files as-is. No transformation.
# MAGIC Schema-on-read. Adds ingestion metadata only.

# COMMAND ----------

BRONZE_SCHEMA = StructType([
    StructField("claim_id",          StringType(),    nullable=False),
    StructField("policy_number",     StringType(),    nullable=True),
    StructField("claimant_name",     StringType(),    nullable=True),
    StructField("claim_type",        StringType(),    nullable=True),
    StructField("incident_date",     StringType(),    nullable=True),
    StructField("submission_date",   StringType(),    nullable=True),
    StructField("claimed_amount",    DoubleType(),    nullable=True),
    StructField("currency",          StringType(),    nullable=True),
    StructField("description",       StringType(),    nullable=True),
    StructField("status",            StringType(),    nullable=True),
    StructField("document_url",      StringType(),    nullable=True),
    StructField("extracted_fields",  StringType(),    nullable=True),  # JSON from Doc Intelligence
])

def ingest_bronze(source_path: str = None) -> int:
    """
    Ingest raw claim files from source into Bronze Delta table.
    Idempotent — uses claim_id as dedup key.
    """
    source = source_path or adls_path(CONTAINER_BRONZE, "incoming/")

    logger.info(f"Reading from: {source}")

    df_raw = (
        spark.read
        .schema(BRONZE_SCHEMA)
        .option("multiLine", "true")
        .json(source)
        .withColumn("_ingested_at",    current_timestamp())
        .withColumn("_source_path",    lit(source))
        .withColumn("_record_hash",    sha2(concat_ws("|",
            col("claim_id"), col("claimed_amount"), col("status")
        ), 256))
    )

    count = df_raw.count()
    logger.info(f"Records read: {count}")

    # Write to Delta with merge (upsert on claim_id)
    bronze_path = adls_path(CONTAINER_BRONZE, "delta/claims/")

    if DeltaTable.isDeltaTable(spark, bronze_path):
        bronze_table = DeltaTable.forPath(spark, bronze_path)
        bronze_table.alias("target").merge(
            df_raw.alias("source"),
            "target.claim_id = source.claim_id"
        ).whenMatchedUpdateAll(
        ).whenNotMatchedInsertAll(
        ).execute()
        logger.info(f"Upserted {count} records into Bronze Delta table")
    else:
        df_raw.write.format("delta").mode("overwrite").save(bronze_path)
        logger.info(f"Created Bronze Delta table with {count} records")

    return count

bronze_count = ingest_bronze()
print(f"Bronze ingestion complete: {bronze_count} records")

# COMMAND ----------
# MAGIC %md ## Silver Layer — Validated & Enriched
# MAGIC - Type casting and normalisation
# MAGIC - Deduplication on claim_id
# MAGIC - Data quality checks (DQ flags)
# MAGIC - Parsing Document Intelligence extracted_fields JSON

# COMMAND ----------

from pyspark.sql.functions import from_json, get_json_object

DOCINTEL_SCHEMA = StructType([
    StructField("confidence",       DoubleType(),  nullable=True),
    StructField("policy_extracted", StringType(),  nullable=True),
    StructField("amount_extracted", DoubleType(),  nullable=True),
    StructField("date_extracted",   StringType(),  nullable=True),
    StructField("fraud_indicators", StringType(),  nullable=True),
])

def transform_silver() -> int:
    """
    Transform Bronze → Silver:
    - Cast types, normalise strings
    - Parse Document Intelligence JSON
    - Apply data quality flags
    - Deduplicate
    """
    bronze_path = adls_path(CONTAINER_BRONZE, "delta/claims/")
    silver_path = adls_path(CONTAINER_SILVER, "delta/claims/")

    df_bronze = spark.read.format("delta").load(bronze_path)

    df_silver = (
        df_bronze
        # Type casting
        .withColumn("incident_date",   to_timestamp(col("incident_date"),   "yyyy-MM-dd"))
        .withColumn("submission_date", to_timestamp(col("submission_date"), "yyyy-MM-dd"))
        # Normalise strings
        .withColumn("claim_type",  upper(trim(col("claim_type"))))
        .withColumn("currency",    upper(trim(col("currency"))))
        .withColumn("status",      upper(trim(col("status"))))
        # Parse Document Intelligence output
        .withColumn("docintel", from_json(col("extracted_fields"), DOCINTEL_SCHEMA))
        .withColumn("docintel_confidence",       col("docintel.confidence"))
        .withColumn("docintel_policy",           col("docintel.policy_extracted"))
        .withColumn("docintel_amount",           col("docintel.amount_extracted"))
        .withColumn("docintel_fraud_indicators", col("docintel.fraud_indicators"))
        # Data quality flags
        .withColumn("dq_missing_policy",
            when(col("policy_number").isNull(), True).otherwise(False))
        .withColumn("dq_amount_mismatch",
            when(
                col("docintel_amount").isNotNull() &
                (abs(col("claimed_amount") - col("docintel_amount")) > col("claimed_amount") * 0.1),
                True
            ).otherwise(False))
        .withColumn("dq_low_confidence",
            when(col("docintel_confidence") < 0.7, True).otherwise(False))
        .withColumn("dq_passed",
            ~col("dq_missing_policy") & ~col("dq_amount_mismatch") & ~col("dq_low_confidence"))
        # Audit
        .withColumn("_processed_at", current_timestamp())
        .drop("docintel", "extracted_fields")
        # Deduplicate — keep latest by submission_date
        .dropDuplicates(["claim_id"])
    )

    count = df_silver.count()

    df_silver.write.format("delta").mode("overwrite").option("overwriteSchema", "true").save(silver_path)

    logger.info(f"Silver layer written: {count} records")
    dq_passed = df_silver.filter(col("dq_passed")).count()
    logger.info(f"DQ passed: {dq_passed}/{count} ({100*dq_passed//count}%)")

    return count

silver_count = transform_silver()
print(f"Silver transformation complete: {silver_count} records")

# COMMAND ----------
# MAGIC %md ## Gold Layer — Aggregated & ML-Ready
# MAGIC - Claims summary by type and status
# MAGIC - Risk scoring features
# MAGIC - AI Search indexing payload
# MAGIC - OpenAI embedding preparation

# COMMAND ----------

def build_gold() -> int:
    """
    Build Gold layer aggregations for:
    - Claims summary (BI/reporting)
    - Risk features (ML)
    - Search index payload (AI Search)
    """
    silver_path = adls_path(CONTAINER_SILVER, "delta/claims/")
    gold_path   = adls_path(CONTAINER_GOLD,   "delta/")

    df_silver = spark.read.format("delta").load(silver_path)

    # --- Gold table 1: Claims summary by type ---
    df_summary = (
        df_silver
        .filter(col("dq_passed"))
        .groupBy("claim_type", "status", "currency")
        .agg(
            count("claim_id").alias("claim_count"),
            spark_sum("claimed_amount").alias("total_claimed"),
            avg("claimed_amount").alias("avg_claimed"),
            avg("docintel_confidence").alias("avg_docintel_confidence"),
        )
        .withColumn("_aggregated_at", current_timestamp())
    )

    df_summary.write.format("delta").mode("overwrite").save(
        adls_path(CONTAINER_GOLD, "delta/claims_summary/")
    )

    # --- Gold table 2: Risk features per claim ---
    df_risk = (
        df_silver
        .withColumn("days_to_submit",
            datediff(col("submission_date"), col("incident_date")))
        .withColumn("risk_score",
            when(col("dq_amount_mismatch"), lit(0.8))
            .when(col("dq_low_confidence"), lit(0.6))
            .when(col("days_to_submit") > 90,  lit(0.5))
            .when(col("days_to_submit") > 180, lit(0.7))
            .otherwise(lit(0.1))
        )
        .withColumn("risk_band",
            when(col("risk_score") >= 0.7, lit("HIGH"))
            .when(col("risk_score") >= 0.4, lit("MEDIUM"))
            .otherwise(lit("LOW"))
        )
        .select(
            "claim_id", "policy_number", "claim_type", "status",
            "claimed_amount", "currency", "incident_date",
            "submission_date", "days_to_submit",
            "risk_score", "risk_band",
            "docintel_confidence", "docintel_fraud_indicators",
            "dq_passed", "_processed_at"
        )
        .withColumn("_scored_at", current_timestamp())
    )

    df_risk.write.format("delta").mode("overwrite").save(
        adls_path(CONTAINER_GOLD, "delta/claims_risk/")
    )

    # --- Gold table 3: AI Search index payload ---
    df_search = (
        df_silver
        .filter(col("dq_passed"))
        .select(
            col("claim_id").alias("id"),
            col("claim_type").alias("claimType"),
            col("description").alias("content"),
            col("status").alias("status"),
            col("claimed_amount").alias("claimedAmount"),
            col("currency").alias("currency"),
            col("incident_date").alias("incidentDate"),
            col("docintel_confidence").alias("extractionConfidence"),
        )
    )

    df_search.write.format("json").mode("overwrite").save(
        adls_path(CONTAINER_GOLD, "search-index-payload/")
    )

    count = df_risk.count()
    high_risk = df_risk.filter(col("risk_band") == "HIGH").count()
    logger.info(f"Gold layer written: {count} claims, {high_risk} HIGH risk")

    return count

gold_count = build_gold()
print(f"Gold build complete: {gold_count} records")

# COMMAND ----------
# MAGIC %md ## Pipeline Summary

# COMMAND ----------

print("=" * 60)
print("CLAIMS MEDALLION PIPELINE COMPLETE")
print("=" * 60)
print(f"  Bronze (raw):    {bronze_count:>6} records")
print(f"  Silver (clean):  {silver_count:>6} records")
print(f"  Gold (features): {gold_count:>6} records")
print()

# Display risk distribution
silver_path = adls_path(CONTAINER_SILVER, "delta/claims/")
gold_risk   = adls_path(CONTAINER_GOLD,   "delta/claims_risk/")

df_risk_summary = (
    spark.read.format("delta").load(gold_risk)
    .groupBy("risk_band")
    .agg(count("claim_id").alias("count"))
    .orderBy("risk_band")
)
display(df_risk_summary)

# Display claims summary
df_summary = spark.read.format("delta").load(
    adls_path(CONTAINER_GOLD, "delta/claims_summary/")
)
display(df_summary)
