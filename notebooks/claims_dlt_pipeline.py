# Databricks notebook source
# MAGIC %md
# MAGIC # Claims Intelligence — Delta Live Tables Pipeline
# MAGIC ## Declarative Bronze to Silver to Gold with Data Quality Expectations

# COMMAND ----------

import dlt
from pyspark.sql.functions import (
    col, upper, trim, to_timestamp, datediff,
    when, abs as spark_abs, sha2, concat_ws,
    current_timestamp, from_json, input_file_name
)
from pyspark.sql.types import (
    StructType, StructField, StringType, DoubleType
)

# COMMAND ----------
# MAGIC %md ## Bronze Layer

# COMMAND ----------

STORAGE_ACCOUNT = "adlsclaimsdev0bd2"
STORAGE_KEY = "<STORAGE_KEY_REDACTED>"

def adls(container, path=""):
    return f"abfss://{container}@{STORAGE_ACCOUNT}.dfs.core.windows.net/{path}"

BRONZE_SCHEMA = StructType([
    StructField("claim_id",         StringType(), True),
    StructField("policy_number",    StringType(), True),
    StructField("claimant_name",    StringType(), True),
    StructField("claim_type",       StringType(), True),
    StructField("incident_date",    StringType(), True),
    StructField("submission_date",  StringType(), True),
    StructField("claimed_amount",   DoubleType(), True),
    StructField("currency",         StringType(), True),
    StructField("description",      StringType(), True),
    StructField("status",           StringType(), True),
    StructField("extracted_fields", StringType(), True),
])

@dlt.table(
    name="bronze_claims",
    comment="Raw claim records from ADLS Gen2 landing zone"
)
@dlt.expect_or_fail("claim_id_not_null", "claim_id IS NOT NULL")
@dlt.expect("positive_amount", "claimed_amount > 0")
def bronze_claims():
    spark.conf.set(
        f"fs.azure.account.key.{STORAGE_ACCOUNT}.dfs.core.windows.net",
        STORAGE_KEY
    )
    return (
        spark.read
        .schema(BRONZE_SCHEMA)
        .json(adls("bronze", "incoming/"))
        .withColumn("_ingested_at", current_timestamp())
        .withColumn("_record_hash",
            sha2(concat_ws("|", col("claim_id"), col("claimed_amount")), 256))
    )

# COMMAND ----------
# MAGIC %md ## Silver Layer

# COMMAND ----------

DOCINTEL_SCHEMA = StructType([
    StructField("confidence",       DoubleType(), True),
    StructField("amount_extracted", DoubleType(), True),
    StructField("fraud_indicators", StringType(), True),
])

@dlt.table(
    name="silver_claims",
    comment="Validated and enriched claims with DQ flags"
)
@dlt.expect_or_drop(
    "valid_claim_type",
    "claim_type IN ('MOTOR', 'PROPERTY', 'LIABILITY', 'HEALTH')"
)
@dlt.expect("reasonable_amount", "claimed_amount < 1000000")
@dlt.expect("policy_present", "policy_number IS NOT NULL")
def silver_claims():
    bronze = dlt.read("bronze_claims")
    return (
        bronze
        .withColumn("incident_date",
            to_timestamp("incident_date", "yyyy-MM-dd"))
        .withColumn("submission_date",
            to_timestamp("submission_date", "yyyy-MM-dd"))
        .withColumn("claim_type", upper(trim(col("claim_type"))))
        .withColumn("claimed_amount", col("claimed_amount").cast("double"))
        .withColumn("docintel",
            from_json(col("extracted_fields"), DOCINTEL_SCHEMA))
        .withColumn("docintel_confidence",    col("docintel.confidence"))
        .withColumn("docintel_fraud_indicators", col("docintel.fraud_indicators"))
        .withColumn("docintel_amount_extracted", col("docintel.amount_extracted"))
        .withColumn("dq_missing_policy",
            col("policy_number").isNull() | (col("policy_number") == ""))
        .withColumn("dq_amount_mismatch",
            when(col("docintel.amount_extracted").isNotNull(),
                spark_abs(col("claimed_amount") - col("docintel.amount_extracted"))
                / col("claimed_amount") > 0.1
            ).otherwise(False))
        .withColumn("dq_low_confidence", col("docintel_confidence") < 0.7)
        .dropDuplicates(["claim_id"])
        .drop("docintel", "extracted_fields", "_record_hash")
    )

# COMMAND ----------
# MAGIC %md ## Gold Layer — Risk Scored

# COMMAND ----------

@dlt.table(
    name="gold_claims_risk",
    comment="Risk-scored claims for fraud investigation triage"
)
@dlt.expect("valid_risk_score", "risk_score BETWEEN 0 AND 1")
@dlt.expect("valid_risk_band", "risk_band IN ('LOW', 'MEDIUM', 'HIGH')")
def gold_claims_risk():
    silver = dlt.read("silver_claims")
    return (
        silver
        .withColumn("days_to_submit",
            datediff(col("submission_date"), col("incident_date")))
        .withColumn("risk_score",
            when(col("docintel_fraud_indicators").isNotNull(), 0.8)
            .when(col("dq_amount_mismatch"), 0.7)
            .when(col("dq_low_confidence"), 0.6)
            .when(datediff(col("submission_date"), col("incident_date")) > 180, 0.7)
            .when(datediff(col("submission_date"), col("incident_date")) > 90, 0.5)
            .otherwise(0.1))
        .withColumn("risk_band",
            when(col("risk_score") >= 0.7, "HIGH")
            .when(col("risk_score") >= 0.5, "MEDIUM")
            .otherwise("LOW"))
        .withColumn("scored_at", current_timestamp())
    )

# COMMAND ----------
# MAGIC %md ## Gold Layer — Summary

# COMMAND ----------

from pyspark.sql.functions import count, sum as spark_sum, avg, round as spark_round

@dlt.table(
    name="gold_claims_summary",
    comment="Aggregated claims by type and risk band"
)
def gold_claims_summary():
    risk = dlt.read("gold_claims_risk")
    return (
        risk
        .groupBy("claim_type", "risk_band")
        .agg(
            count("claim_id").alias("claim_count"),
            spark_round(spark_sum("claimed_amount"), 2).alias("total_exposure"),
            spark_round(avg("claimed_amount"), 2).alias("avg_claim_value"),
            spark_round(avg("risk_score"), 3).alias("avg_risk_score")
        )
        .orderBy("claim_type", "risk_band")
    )
