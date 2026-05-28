# Databricks notebook source
# MAGIC %md
# MAGIC # Claims Intelligence Dashboard
# MAGIC ## Interactive visualisations on Gold Delta tables

# COMMAND ----------

spark.conf.set(
    "fs.azure.account.key.adlsclaimsdev0bd2.dfs.core.windows.net",
    "<STORAGE_KEY_FROM_KEYVAULT>"
)

STORAGE_ACCOUNT = "adlsclaimsdev0bd2"
def adls(container, path=""):
    return "abfss://{}@{}.dfs.core.windows.net/{}".format(container, STORAGE_ACCOUNT, path)

print("Storage configured")

# COMMAND ----------
# MAGIC %md ## 1 - Risk distribution

# COMMAND ----------

import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

df_risk = spark.read.format("delta").load(adls("gold", "delta/claims_risk/"))
df_ml   = spark.read.format("delta").load(adls("gold", "delta/claims_ml_scored/"))

risk_counts = df_risk.groupBy("risk_band").count().toPandas().sort_values("risk_band")
colors = {"HIGH": "#d13438", "MEDIUM": "#ff8c00", "LOW": "#107c10"}

fig, axes = plt.subplots(1, 3, figsize=(18, 5))
fig.patch.set_facecolor("#fafafa")

# Pie chart
c = [colors.get(r, "#888") for r in risk_counts["risk_band"]]
axes[0].pie(risk_counts["count"], labels=risk_counts["risk_band"],
    colors=c, autopct="%1.1f%%", startangle=90,
    textprops={"fontsize": 13, "fontweight": "bold"})
axes[0].set_title("Risk Band Distribution", fontsize=15, fontweight="bold", pad=20)

# Bar by claim type
type_risk = df_risk.groupBy("claim_type", "risk_band").count().toPandas()
pivot = type_risk.pivot(index="claim_type", columns="risk_band", values="count").fillna(0)
pivot.plot(kind="bar", ax=axes[1], color=[colors.get(c,"#888") for c in pivot.columns],
    edgecolor="white", linewidth=0.5)
axes[1].set_title("Risk by Claim Type", fontsize=15, fontweight="bold")
axes[1].set_xlabel("")
axes[1].set_xticklabels(axes[1].get_xticklabels(), rotation=30, ha="right", fontsize=11)
axes[1].legend(title="Risk Band", fontsize=10)
axes[1].set_facecolor("#fafafa")

# ML probability histogram
ml_pdf = df_ml.select("ml_fraud_probability").toPandas()
axes[2].hist(ml_pdf["ml_fraud_probability"], bins=20,
    color="#0078d4", edgecolor="white", linewidth=0.5, alpha=0.85)
axes[2].axvline(x=0.4, color="#ff8c00", linestyle="--", linewidth=2, label="MEDIUM threshold")
axes[2].axvline(x=0.7, color="#d13438", linestyle="--", linewidth=2, label="HIGH threshold")
axes[2].set_title("ML Fraud Probability Distribution", fontsize=15, fontweight="bold")
axes[2].set_xlabel("Fraud Probability", fontsize=12)
axes[2].set_ylabel("Count", fontsize=12)
axes[2].legend(fontsize=10)
axes[2].set_facecolor("#fafafa")

plt.tight_layout(pad=3.0)
display(fig)
print("Dashboard 1 complete")

# COMMAND ----------
# MAGIC %md ## 2 - Financial exposure by risk band

# COMMAND ----------

from pyspark.sql.functions import col, sum as spark_sum, avg, count, round as spark_round

exposure = df_risk.groupBy("risk_band").agg(
    count("claim_id").alias("claim_count"),
    spark_round(spark_sum("claimed_amount"), 2).alias("total_exposure"),
    spark_round(avg("claimed_amount"), 2).alias("avg_claim"),
).toPandas().sort_values("risk_band")

fig2, axes2 = plt.subplots(1, 2, figsize=(14, 5))
fig2.patch.set_facecolor("#fafafa")

bars = axes2[0].bar(exposure["risk_band"], exposure["total_exposure"] / 1e6,
    color=[colors.get(r,"#888") for r in exposure["risk_band"]],
    edgecolor="white", width=0.5)
axes2[0].set_title("Total Financial Exposure by Risk Band", fontsize=14, fontweight="bold")
axes2[0].set_ylabel("Exposure (GBP Millions)", fontsize=12)
for bar, val in zip(bars, exposure["total_exposure"]):
    axes2[0].text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.01,
        "{:.1f}M".format(val/1e6), ha="center", va="bottom", fontweight="bold", fontsize=11)
axes2[0].set_facecolor("#fafafa")

bars2 = axes2[1].bar(exposure["risk_band"], exposure["avg_claim"],
    color=[colors.get(r,"#888") for r in exposure["risk_band"]],
    edgecolor="white", width=0.5)
axes2[1].set_title("Average Claim Value by Risk Band", fontsize=14, fontweight="bold")
axes2[1].set_ylabel("Average Claim (GBP)", fontsize=12)
for bar, val in zip(bars2, exposure["avg_claim"]):
    axes2[1].text(bar.get_x() + bar.get_width()/2, bar.get_height() + 100,
        "{:,.0f}".format(val), ha="center", va="bottom", fontweight="bold", fontsize=11)
axes2[1].set_facecolor("#fafafa")

plt.tight_layout(pad=3.0)
display(fig2)
print("Dashboard 2 complete")

# COMMAND ----------
# MAGIC %md ## 3 - Rule-based vs ML risk comparison

# COMMAND ----------

comparison = df_ml.groupBy("risk_band", "ml_risk_band").count()     .orderBy("risk_band", "ml_risk_band").toPandas()

pivot = comparison.pivot(index="risk_band", columns="ml_risk_band", values="count").fillna(0)

fig3, ax3 = plt.subplots(figsize=(8, 5))
fig3.patch.set_facecolor("#fafafa")
im = ax3.imshow(pivot.values, cmap="Blues", aspect="auto")
plt.colorbar(im, ax=ax3, label="Count")
ax3.set_xticks(range(len(pivot.columns)))
ax3.set_yticks(range(len(pivot.index)))
ax3.set_xticklabels(pivot.columns, fontsize=12)
ax3.set_yticklabels(pivot.index, fontsize=12)
ax3.set_xlabel("ML Risk Band", fontsize=13, fontweight="bold")
ax3.set_ylabel("Rule-Based Risk Band", fontsize=13, fontweight="bold")
ax3.set_title("Rule-Based vs ML Risk Classification", fontsize=14, fontweight="bold")
for i in range(len(pivot.index)):
    for j in range(len(pivot.columns)):
        val = int(pivot.values[i, j])
        ax3.text(j, i, str(val), ha="center", va="center", fontsize=14, fontweight="bold",
            color="white" if pivot.values[i,j] > pivot.values.max()/2 else "black")
plt.tight_layout()
display(fig3)
print("Dashboard 3 complete")

# COMMAND ----------
# MAGIC %md ## 4 - Key metrics

# COMMAND ----------

from pyspark.sql.functions import avg as spark_avg

total = df_risk.count()
high_risk = df_risk.filter(col("risk_band") == "HIGH").count()
total_exposure = df_risk.agg(spark_sum("claimed_amount")).collect()[0][0]
avg_ml_prob = df_ml.agg(spark_avg("ml_fraud_probability")).collect()[0][0]

print("=" * 55)
print("CLAIMS INTELLIGENCE PLATFORM - KEY METRICS")
print("=" * 55)
print("  Total claims analysed:    {:>8,}".format(total))
print("  HIGH risk claims:         {:>8,} ({}%)".format(high_risk, 100*high_risk//total))
print("  Total financial exposure: GBP {:>10,.0f}".format(total_exposure))
print("  Avg ML fraud probability: {:>8.1%}".format(avg_ml_prob))
print("  Best ML model:            GradientBoosting (Production)")
print("  Delta tables:             Bronze / Silver / Gold / ML-Scored")
print("=" * 55)
