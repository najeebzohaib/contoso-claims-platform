# Databricks notebook source
# MAGIC %md
# MAGIC # Real-Time Claims Processing — Structured Streaming
# MAGIC ## Demonstrates event-driven architecture with Delta Lake as sink

# COMMAND ----------

spark.conf.set(
    "fs.azure.account.key.adlsclaimsdev0bd2.dfs.core.windows.net",
    "<STORAGE_KEY_FROM_KEYVAULT>"
)

STORAGE_ACCOUNT = "adlsclaimsdev0bd2"

def adls(container, path=""):
    return f"abfss://{container}@{STORAGE_ACCOUNT}.dfs.core.windows.net/{path}"

print("Storage configured")

# COMMAND ----------
# MAGIC %md
# MAGIC ## Step 1 — Simulate real-time claim events
# MAGIC Write 50 new claims to the bronze landing zone to simulate incoming events

# COMMAND ----------

import json, uuid, random
from datetime import datetime, timedelta
from pyspark.sql.functions import *
from pyspark.sql.types import *

# Generate 50 new streaming claims
new_claims = []
base = datetime(2026, 5, 28)
claim_types = ["MOTOR", "PROPERTY", "LIABILITY", "HEALTH"]
descriptions = [
    "Vehicle rear-ended at traffic lights. Third party admitted liability.",
    "Storm damage to commercial roof. Emergency repairs undertaken.",
    "Slip and fall in supermarket. Witness statements obtained.",
    "Flooding caused by burst pipe. Adjacent property also affected.",
    "Vehicle theft from secure car park. CCTV footage requested.",
    "Fire damage to office premises. Electrical fault identified.",
    "Employer liability claim. Machinery malfunction caused injury.",
    "Business interruption following cyber incident. Systems offline 48hrs.",
]

for i in range(50):
    incident = base - timedelta(days=random.randint(1, 180))
    submission = incident + timedelta(days=random.randint(1, 200))
    amount = round(random.uniform(1000, 120000), 2)
    fraud = random.random() < 0.2
    claims = {
        "claim_id": f"CLM-STREAM-{str(uuid.uuid4())[:8].upper()}",
        "policy_number": f"POL-{random.randint(100000,999999)}",
        "claimant_name": random.choice(["James Mitchell","Sarah Thompson","Mohammed Hassan","Emma Clarke","David Patel"]),
        "claim_type": random.choice(claim_types),
        "incident_date": incident.strftime("%Y-%m-%d"),
        "submission_date": submission.strftime("%Y-%m-%d"),
        "claimed_amount": amount * (random.uniform(1.5, 3.0) if fraud else 1.0),
        "currency": "GBP",
        "description": random.choice(descriptions),
        "status": "SUBMITTED",
        "document_url": f"https://adlsclaimsdev0bd2.blob.core.windows.net/bronze/docs/{uuid.uuid4()}.pdf",
        "extracted_fields": json.dumps({
            "confidence": round(random.uniform(0.5, 0.99), 2),
            "policy_extracted": f"POL-{random.randint(100000,999999)}",
            "amount_extracted": round(amount * random.uniform(0.9, 1.1), 2),
            "date_extracted": incident.strftime("%Y-%m-%d"),
            "fraud_indicators": "late_submission,amount_escalation" if fraud else None
        })
    }
    new_claims.append(claims)

# Write to bronze landing as individual JSON files (simulating event stream)
import os, tempfile
for i, claim in enumerate(new_claims[:10]):  # write 10 for demo
    blob_path = f"/tmp/streaming_claim_{i}.json"
    with open(blob_path, "w") as f:
        f.write(json.dumps(claim))

# Upload to ADLS streaming folder
for i in range(10):
    dbutils.fs.cp(f"file:///tmp/streaming_claim_{i}.json",
                  adls("bronze", f"streaming/claims/claim_{i:04d}.json"))

print(f"Written 10 claim events to bronze/streaming/")

# COMMAND ----------
# MAGIC %md
# MAGIC ## Step 2 — Define streaming schema and read stream

# COMMAND ----------

CLAIM_SCHEMA = StructType([
    StructField("claim_id",         StringType(), True),
    StructField("policy_number",    StringType(), True),
    StructField("claimant_name",    StringType(), True),
    StructField("claim_type",       StringType(), True),
    StructField("incident_date",    StringType(), True),
    StructField("submission_date",  StringType(), True),
    StructField("claimed_amount",   DoubleType(),  True),
    StructField("currency",         StringType(), True),
    StructField("description",      StringType(), True),
    StructField("status",           StringType(), True),
    StructField("extracted_fields", StringType(), True),
])

# Read as stream from bronze landing zone
stream_df = (spark.readStream
    .format("cloudFiles")
    .option("cloudFiles.format", "json")
    .option("cloudFiles.schemaLocation", adls("bronze", "streaming/_schema"))
    .schema(CLAIM_SCHEMA)
    .load(adls("bronze", "streaming/claims/"))
)

print("Stream schema:")
stream_df.printSchema()

# COMMAND ----------
# MAGIC %md
# MAGIC ## Step 3 — Real-time transformations

# COMMAND ----------

from pyspark.sql.functions import from_json, col, when, datediff, to_timestamp, current_timestamp, lit

DOCINTEL_SCHEMA = StructType([
    StructField("confidence",       DoubleType(), True),
    StructField("amount_extracted", DoubleType(), True),
    StructField("fraud_indicators", StringType(), True),
])

transformed_stream = (stream_df
    .withColumn("incident_date",   to_timestamp("incident_date",   "yyyy-MM-dd"))
    .withColumn("submission_date", to_timestamp("submission_date", "yyyy-MM-dd"))
    .withColumn("claim_type",      upper(trim(col("claim_type"))))
    .withColumn("docintel",        from_json(col("extracted_fields"), DOCINTEL_SCHEMA))
    .withColumn("confidence",      col("docintel.confidence"))
    .withColumn("fraud_indicators",col("docintel.fraud_indicators"))
    .withColumn("days_to_submit",  datediff(col("submission_date"), col("incident_date")))
    .withColumn("real_time_risk",
        when(col("fraud_indicators").isNotNull(), lit("HIGH"))
        .when(col("days_to_submit") > 180,        lit("HIGH"))
        .when(col("days_to_submit") > 90,         lit("MEDIUM"))
        .when(col("confidence") < 0.7,            lit("MEDIUM"))
        .otherwise(lit("LOW"))
    )
    .withColumn("processed_at", current_timestamp())
    .drop("docintel", "extracted_fields")
)

# COMMAND ----------
# MAGIC %md
# MAGIC ## Step 4 — Write stream to Delta Lake (silver layer)

# COMMAND ----------

# Write streaming output to Delta Lake
query = (transformed_stream.writeStream
    .format("delta")
    .outputMode("append")
    .option("checkpointLocation", adls("silver", "streaming/_checkpoint"))
    .trigger(availableNow=True)
    .start(adls("silver", "delta/claims_streaming/"))
)

query.awaitTermination()
print("Streaming query complete")

# COMMAND ----------
# MAGIC %md
# MAGIC ## Step 5 — Query results

# COMMAND ----------

df_results = spark.read.format("delta").load(adls("silver", "delta/claims_streaming/"))
count = df_results.count()
print(f"Streaming pipeline processed {count} claims in real-time")

print("
Risk distribution from streaming pipeline:")
df_results.groupBy("real_time_risk").count().orderBy("real_time_risk").show()

print("
Sample claims with real-time risk scores:")
df_results.select("claim_id","claim_type","claimed_amount","days_to_submit","real_time_risk","processed_at")     .orderBy("processed_at", ascending=False).show(10, truncate=False)

# COMMAND ----------
# MAGIC %md
# MAGIC ## Summary
# MAGIC
# MAGIC This notebook demonstrates **Structured Streaming** on Databricks:
# MAGIC - Auto Loader () monitors ADLS Gen2 for new claim files
# MAGIC - Real-time transformations applied as events arrive
# MAGIC - Risk scoring computed per-event (no batch window)
# MAGIC - Results written to Delta Lake silver layer with ACID guarantees
# MAGIC - Checkpoint ensures exactly-once processing and fault tolerance
