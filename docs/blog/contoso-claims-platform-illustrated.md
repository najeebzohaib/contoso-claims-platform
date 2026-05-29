# Building an Enterprise AI Claims Intelligence Platform on Azure

*A complete walkthrough of a production-grade Azure platform for insurance claims processing — with real screenshots, real load test results, and real GPT-4o AI analysis. Written as a reference for anyone joining the team or wanting to understand what was built and why.*

---

## Table of Contents

1. [What This Platform Does](#what-this-platform-does)
2. [Architecture Overview](#architecture-overview)
3. [Network Design — Hub and Spoke](#network-design)
4. [Security Layer 1 — DDoS Protection](#layer-1-ddos)
5. [Security Layer 2 — Azure Firewall Premium](#layer-2-firewall)
6. [Security Layer 3 — Application Gateway WAF](#layer-3-waf)
7. [Security Layer 4 — API Management](#layer-4-apim)
8. [Security Layer 5 — Workload Identity](#layer-5-workload-identity)
9. [Security Layer 6 — Private Endpoints](#layer-6-private-endpoints)
10. [The Claims API on AKS](#claims-api-on-aks)
11. [Azure OpenAI GPT-4o Integration](#openai-integration)
12. [The React Frontend](#react-frontend)
13. [Databricks Medallion Pipeline](#databricks-medallion)
14. [MLflow Fraud Detection](#mlflow-fraud-detection)
15. [Claims Intelligence Dashboard](#claims-dashboard)
16. [Observability — Sentinel and Log Analytics](#observability)
17. [Load Testing Results](#load-testing)
18. [Infrastructure as Code — Terraform](#terraform)
19. [CI/CD Pipeline](#cicd)
20. [Key Metrics Summary](#key-metrics)
21. [What to Do Next](#what-next)

---

## What This Platform Does {#what-this-platform-does}

The Contoso Claims Intelligence Platform processes insurance claims end-to-end using Azure AI services. A claim enters through a React web application, passes through five security layers, reaches a FastAPI service running on Kubernetes, and is analysed by Azure OpenAI GPT-4o — returning a structured risk score, fraud indicators, and a recommendation in real time.

In parallel, a Databricks data pipeline ingests raw claim events into a Bronze to Silver to Gold Delta Lake medallion architecture, trains a fraud detection ML model using MLflow, and produces risk-scored aggregations for business intelligence.

**Everything described in this document is live and running in Azure UK South.**

**Platform at a glance:**
- 200 claims processed through the medallion pipeline
- 17,928,654 GBP total financial exposure analysed
- 21 HIGH risk claims detected (10.5%)
- 3 ML models trained and tracked in MLflow Model Registry
- 368 requests per second sustained through WAF, APIM, and AKS with 0% errors
- 6 security layers from DDoS Protection to private endpoints

---

## Architecture Overview {#architecture-overview}

The platform follows a hub-spoke network topology with security enforced at every layer. Traffic from the internet passes through six security controls before reaching the application.

```
Internet
    |
[DDoS Protection Standard]       volumetric attack mitigation
    |
[Azure Firewall Premium]          Hub VNet 10.0.0.0/16
    |   IDPS, TLS inspection, threat intelligence
    |
[App Gateway WAF v2]              OWASP 3.2, zone redundant, autoscale
    |   public IP: 4.158.34.10
    |
[API Management - Internal VNet]  Spoke VNet 10.10.0.0/16
    |   private IP: 10.10.5.4
    |
[AKS - claims-api]                internal LB: 10.10.16.6
    |   FastAPI, Workload Identity, 3 replicas
    |
    +-- Azure OpenAI GPT-4o        (private endpoint)
    +-- Document Intelligence      (private endpoint)
    +-- AI Search                  (private endpoint)
    +-- Key Vault                  (private endpoint)
              |
        ADLS Gen2  Bronze / Silver / Gold
              |
        Databricks Premium  (VNet injected)
              |
        MLflow Model Registry  (GradientBoosting in Production)
```

---

## Network Design — Hub and Spoke {#network-design}

**What it is:** Hub-spoke is the standard enterprise network topology on Azure. A central hub VNet hosts shared security services. Workloads run in spoke VNets that peer to the hub. All traffic between spokes, and all egress to the internet, flows through the hub firewall.

**Why hub-spoke:** Network segmentation is a baseline requirement in regulated environments. Hub-spoke ensures workloads are isolated from each other and all internet-bound traffic is inspected centrally. NSG-only approaches fail this requirement because NSGs operate at Layer 4 and provide no application-layer inspection.

### Hub VNet (10.0.0.0/16)

| Subnet | CIDR | Purpose |
|--------|------|---------|
| AzureFirewallSubnet | 10.0.0.0/26 | Azure Firewall Premium |
| AzureFirewallManagementSubnet | 10.0.0.64/26 | Firewall management traffic |
| AzureBastionSubnet | 10.0.2.0/26 | Azure Bastion Standard |
| GatewaySubnet | 10.0.1.0/27 | Reserved for ExpressRoute/VPN |

### Dev Spoke (10.10.0.0/16)

| Subnet | CIDR | Purpose |
|--------|------|---------|
| appgw | 10.10.4.0/24 | Application Gateway WAF |
| apim | 10.10.5.0/24 | API Management (internal) |
| aks | 10.10.16.0/20 | AKS node pools |
| pe | 10.10.3.0/24 | Private endpoints |
| dbw-public | 10.10.32.0/24 | Databricks public subnet |
| dbw-private | 10.10.33.0/24 | Databricks private subnet |

All AKS egress is forced through the hub firewall via User Defined Routes: `0.0.0.0/0 to VirtualAppliance at 10.0.0.4`. Every package download, Azure API call, and container registry pull from an AKS node is inspected before leaving the network.

**Key Terraform lesson:** Azure Firewall requires a subnet named exactly `AzureFirewallSubnet` with no prefix or suffix. Networking modules that apply a naming prefix to all subnets will break Firewall provisioning. The fix is to create the Firewall, Management, and Bastion subnets as standalone resources outside the networking module. This is documented in ADR-004.

📖 [Azure hub-spoke reference architecture](https://learn.microsoft.com/en-us/azure/architecture/networking/architecture/hub-spoke)

---

## Security Layer 1 — DDoS Protection Standard {#layer-1-ddos}

**What it is:** Azure DDoS Protection Standard adds per-resource protection on top of the platform-level Basic tier. It learns the normal traffic pattern for each public IP and automatically mitigates volumetric, protocol, and application-layer attacks when traffic deviates.

**Why it was used:** The free Basic tier provides shared protection across all Azure customers with no per-resource visibility. Standard provides adaptive tuning specific to your traffic patterns, real-time mitigation telemetry streamed to Log Analytics, and a cost protection guarantee if a DDoS attack triggers auto-scaling.

One plan per subscription region is the Azure limit. The same plan is shared between dev and prod environments.

📖 [Azure DDoS Protection documentation](https://learn.microsoft.com/en-us/azure/ddos-protection/ddos-protection-overview)

---

## Security Layer 2 — Azure Firewall Premium {#layer-2-firewall}

**What it is:** Azure Firewall Premium is a fully stateful, cloud-native network security service with three capabilities unavailable in the Standard SKU.

**IDPS (Intrusion Detection and Prevention System):** 58,000+ Layer 7 threat signatures updated continuously. Detects port scans, lateral movement, C2 callbacks, and known exploit patterns. Configured in Alert mode for visibility; switchable to Deny for active blocking.

**TLS Inspection:** Decrypts, inspects, and re-encrypts HTTPS traffic. Without TLS inspection, a compromised container can exfiltrate data over HTTPS and the firewall sees only encrypted blobs. TLS inspection breaks open that tunnel for analysis.

**Threat Intelligence:** Microsoft's global threat feed automatically blocks traffic to and from known malicious IPs, domains, and URLs.

**Firewall policy rules:**
- Application rules: AzureKubernetesService FQDN tag, Ubuntu package mirrors, Azure blob and table storage
- Network rules: AzureCloud.uksouth UDP 1194 for AKS tunnelling
- Default deny: everything not explicitly allowed is blocked

> **Screenshot:** Azure Portal showing `fw-claims-hub-uks` — Premium SKU, private IP 10.0.0.4, threat intelligence in Alert mode, firewall policy `fwpol-claims-hub-uks` attached, 2 network rules and 3 application rules configured.

📖 [Azure Firewall Premium features](https://learn.microsoft.com/en-us/azure/firewall/premium-features)

---

## Security Layer 3 — Application Gateway WAF v2 {#layer-3-waf}

**What it is:** Azure Application Gateway v2 is a Layer 7 load balancer with an integrated Web Application Firewall. It is the only resource with a public IP address — the single entry point for all API traffic.

**Why WAF at the edge:** The WAF runs OWASP Core Rule Set 3.2 in Prevention mode, blocking SQL injection, XSS, path traversal, and remote file inclusion before requests reach APIM or AKS. Prevention mode blocks attacks rather than just logging them.

**Configuration:**
- Zone redundant across availability zones 1, 2, 3
- Autoscaling 0-10 instances
- Custom health probe to APIM at 10.10.5.4, path `/`, accepts 200-404
- SSL certificate for HTTPS listener on port 443
- HTTP listener on port 80 for direct API access

> **Screenshot 1:** WAF policy `wafpol-claims-dev-uks` — Enabled, showing Policy settings, Managed rules, Associations, and Custom rules sections.

> **Screenshot 2:** App Gateway health probes — `probe-apim`, HTTP protocol, host 10.10.5.4, path `/`, 30 second timeout.

> **Screenshot 3:** Health probe result — `bepool-apim`, backend address 10.10.5.4, Status **Healthy**, detail "Success. Received 404 status code". A 404 from the APIM root path is the expected response — it confirms APIM is reachable and responding.

**Why is a 404 considered healthy?** APIM returns 404 for requests to the root path `/` because no API is registered there. The health probe only needs to confirm that APIM is alive and responding — any HTTP response confirms this. The probe is configured to accept status codes 200-404.

📖 [Application Gateway WAF documentation](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/ag-overview)

---

## Security Layer 4 — API Management (Internal VNet Mode) {#layer-4-apim}

**What it is:** Azure API Management is a fully managed API gateway. In Internal VNet mode it has no public IP — it is only reachable through Application Gateway from within the network.

**Why Internal VNet mode:** External APIM (the default) exposes the gateway with a public IP. Anyone who discovers the APIM URL can bypass the WAF. Internal mode removes this attack surface — the only path to APIM is through the App Gateway, which enforces WAF rules on every request.

**What APIM provides:**
- Rate limiting to prevent runaway Azure OpenAI costs from abuse
- API versioning at `/claims/v1/`
- CORS policy allowing the React frontend to call the API from a browser
- Request logging to Log Analytics for audit and debugging
- Developer portal for self-service API discovery

**Claims API operations registered in APIM:**

| Method | Path | Purpose |
|--------|------|---------|
| POST | /v1/submit | Submit a new claim |
| GET | /v1/{claimId} | Get a claim by ID |
| POST | /v1/{claimId}/analyse | AI analysis via GPT-4o |
| GET | /v1 | List all claims |
| GET | /health | Health check |

**Traffic path through the platform:**
```
Internet
  -> App Gateway public IP 4.158.34.10
  -> APIM private IP 10.10.5.4 (Internal VNet, no public IP)
  -> AKS internal load balancer 10.10.16.6
  -> claims-api pod (FastAPI)
  -> Azure OpenAI private endpoint
```

> **Screenshot 1:** APIM Overview — `apim-claims-dev-uks`, Status Online, Virtual network Internal, Developer tier (no SLA), 2 APIs configured. Virtual IP addresses show both the public IP used by App Gateway for routing (4.158.236.243) and the private IP (10.10.5.4) that APIM actually listens on.

> **Screenshot 2:** APIM APIs page — Claims Intelligence API with all 5 operations listed: Analyse Claim (POST), Get Claim (GET), Health Check (GET), List Claims (GET), Submit Claim (POST). Backend HTTP endpoint points to `http://10.10.16.6` — the AKS internal load balancer.

**Key lesson — APIM NSG rules:** APIM Internal VNet mode requires two specific inbound NSG rules:
- Port 3443 from the `ApiManagement` service tag (management endpoint)
- Port 6390 from `AzureLoadBalancer` (health probe traffic)

Missing these causes a cryptic 422 error during provisioning. This is documented in ADR-003.

📖 [API Management networking concepts](https://learn.microsoft.com/en-us/azure/api-management/virtual-network-concepts)

---

## Security Layer 5 — Workload Identity {#layer-5-workload-identity}

**What it is:** Azure Workload Identity allows Kubernetes pods to authenticate to Azure services using federated credentials — no API keys, no secrets, no credentials stored anywhere in the cluster.

**Why this matters:** Every alternative involves stored credentials that create risk. Environment variables can be logged. Kubernetes secrets are base64-encoded, not encrypted by default. Managed identity client secrets require rotation. Workload Identity eliminates the credential entirely — there is nothing to steal, rotate, or accidentally log.

**How it works:**

1. AKS OIDC issuer enabled — AKS publishes a public OIDC endpoint that can sign JWTs representing Kubernetes service accounts

2. User Assigned Managed Identity `id-claims-api-dev` created in Azure AD

3. Federated Identity Credential created linking: OIDC issuer URL + Kubernetes namespace + ServiceAccount name to the UAMI

4. Kubernetes ServiceAccount annotated with UAMI client ID:
```yaml
metadata:
  annotations:
    azure.workload.identity/client-id: "780d14ad-dc71-40e9-a7fe-72186d7c54d5"
```

5. Pods with label `azure.workload.identity/use: "true"` receive a projected service account token

6. Azure Identity SDK detects the token file and exchanges it for a short-lived Azure AD access token

7. That access token calls OpenAI, AI Search, Key Vault over private endpoints

**RBAC assignments for claims-api (minimum required):**

| Role | Resource | Why |
|------|----------|-----|
| Cognitive Services OpenAI User | OpenAI | Call GPT-4o |
| Search Index Data Reader | AI Search | Query claims index |
| Storage Blob Data Contributor | ADLS Gen2 | Write to data lake |

📖 [Azure Workload Identity for AKS](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)

---

## Security Layer 6 — Private Endpoints {#layer-6-private-endpoints}

**What it is:** Private Endpoints give PaaS services a private IP address inside your VNet. All PaaS services have `public_network_access_enabled = false` — they are completely unreachable from the public internet.

**Why this is the final critical layer:** Perfect IAM still leaves PaaS services exposed to credential replay attacks, future authentication vulnerabilities, and network-level threats. Private endpoints remove all public network exposure — there is no internet-facing endpoint to attack.

**Private endpoints deployed:**

| Service | DNS Zone |
|---------|---------|
| Azure Container Registry | privatelink.azurecr.io |
| Azure Key Vault | privatelink.vaultcore.azure.net |
| Azure OpenAI | privatelink.openai.azure.com |
| Document Intelligence | privatelink.cognitiveservices.azure.com |
| AI Search | privatelink.search.windows.net |

Private DNS zones in the hub resource group are linked to all VNets. `cog-claims-dev-0bd2.openai.azure.com` resolves to a private IP — traffic never leaves Azure's network.

📖 [Azure Private Endpoint documentation](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)

---

## The Claims API on AKS {#claims-api-on-aks}

**What it is:** A Python FastAPI application running on Azure Kubernetes Service, processing claim submissions and calling Azure OpenAI for AI analysis.

**Why AKS over simpler options:** AKS was chosen over Azure Container Apps or App Service because it supports Workload Identity federation, the internal load balancer pattern required for APIM connectivity, and demonstrates Kubernetes expertise relevant to enterprise deployments.

**Cluster configuration:**

| Setting | Value |
|---------|-------|
| Kubernetes version | 1.34.7 |
| Node size | Standard_D4s_v5 (4 vCPU, 16GB) |
| Node count | 2 |
| Networking | Azure CNI Overlay |
| Pod CIDR | 192.168.0.0/16 |
| Service CIDR | 172.16.0.0/16 |
| Workload Identity | Enabled |
| OIDC issuer | Enabled |
| API server access | Authorised IP ranges |

> **Screenshot 1:** AKS cluster overview — Power state Running, cluster operation Succeeded, Kubernetes 1.34.7, Standard_D4s_v5 nodes, Azure CNI Overlay, authorised IP ranges enabled, container registry linked to `acrclaimsdev0bd2`.

> **Screenshot 2:** AKS Workloads — `claims-api` deployment 1/1 Ready in `claims` namespace (3 days old), plus all system components healthy: azure-wi-webhook 2/2, coredns 2/2, konnectivity-agent 2/2, metrics-server 2/2, ama-logs-rs 1/1.

> **Screenshot 3:** AKS Namespaces — `claims` namespace Active alongside the standard Kubernetes system namespaces.

> **Screenshot 4:** AKS Services — `claims-api` LoadBalancer type, Cluster IP 172.16.62.187, External IP **10.10.16.6** (Azure Internal Load Balancer — private subnet IP, not public), port 80:32097.

> **Screenshot 5:** AKS Node Pools — system pool, 2 nodes Running, Succeeded provisioning, Standard_D4s_v5, Ubuntu Linux, manual scale method.

> **Screenshot 6:** Claims namespace overview — claims-api 1/1 Ready, 3 days old.

> **Screenshot 7:** Pod detail — Running status, namespace claims, pod IP 192.168.1.21, controlled by ReplicaSet/claims-api-7bc8dd8c56, container claims-api Running with 0 restarts.

**The internal load balancer:** The `claims-api` Service uses annotation `service.beta.kubernetes.io/azure-load-balancer-internal: "true"`. This provisions an Azure Internal Load Balancer in the AKS subnet with IP 10.10.16.6. This IP is only reachable from within the VNet — APIM at 10.10.5.4 can reach it, but nothing on the internet can.

**Lesson on permissions:** AKS needs `Network Contributor` on the VNet to provision an internal load balancer. Without this, the Service stays in pending state indefinitely with a 403 error in the service controller logs.

📖 [AKS documentation](https://learn.microsoft.com/en-us/azure/aks/intro-kubernetes)
📖 [AKS internal load balancer](https://learn.microsoft.com/en-us/azure/aks/internal-lb)

---

## Azure OpenAI GPT-4o Integration {#openai-integration}

**What it is:** Azure OpenAI Service provides access to GPT-4o through a private, enterprise-grade API with data residency in UK South and no training on customer data.

**Why Azure OpenAI over the OpenAI API:** Azure OpenAI supports private endpoints — the claims-api calls GPT-4o over a private connection that never leaves Azure. The public OpenAI API is incompatible with the private endpoint architecture. Azure OpenAI also provides enterprise SLAs, usage monitoring, content filtering, and data residency required for financial services.

**Model deployment:**
- Model: gpt-4o version 2024-11-20
- Deployment: GlobalStandard
- Capacity: 10,000 TPM
- Authentication: Workload Identity token (no stored API key)

**The analysis prompt** instructs GPT-4o to act as an insurance claims analyst and return structured JSON containing keyFacts, riskScore (0-1), riskBand (LOW/MEDIUM/HIGH), fraudIndicators, recommendation (APPROVE/INVESTIGATE/REJECT), and a natural language summary.

> **Screenshot 1:** Terminal curl command showing the complete request and response — HTTP 1.1 200 OK from `http://4.158.34.10/claims/v1/{claimId}/analyse`, MEDIUM risk, INVESTIGATE recommendation, fraud indicators for future incident date and lack of supporting documentation.

> **Screenshot 2:** Formatted GPT-4o JSON response for claim CLM-20260528-F697DD0B:
> - keyFacts: PROPERTY, 45000 GBP, London, damages including electrical systems and server room, emergencyServicesInvolved: true
> - riskScore: 0.4, riskBand: MEDIUM
> - fraudIndicators: suspiciousIncidentDate: true, emergencyServicesEvidenceNeeded: true
> - recommendation: INVESTIGATE
> - summary explaining the future incident date concern and need for evidence verification

📖 [Azure OpenAI Service documentation](https://learn.microsoft.com/en-us/azure/ai-services/openai/)

---

## The React Frontend {#react-frontend}

**What it is:** A React single-page application deployed to Azure Static Web Apps providing claim submission, AI analysis, and search functionality.

**Why Static Web Apps:** Global CDN distribution, automatic HTTPS, and GitHub Actions CI/CD integration with no server infrastructure to manage.

**Three tabs:**

*Submit Claim* — form calling `POST /claims/v1/submit` via APIM, returning a Claim ID on success.

*Search Claims* — free-text search implemented as client-side filtering over the `/v1` endpoint. A routing conflict between `/v1/{claimId}` and `/v1/search` in APIM made the dedicated search endpoint unreliable.

*AI Analysis* — paste a Claim ID to call `POST /claims/v1/{claimId}/analyse`. Displays risk gauge, fraud indicators, and key facts extracted by GPT-4o.

> **Screenshot 1:** Submit form — Policy POL-BOE-2026-001, PROPERTY, 45000 GBP, flood description. Blue header shows "Contoso Claims Intelligence" with Azure stack badges. Security badges in dark blue bar: Azure Firewall Premium, App Gateway WAF, API Management, AKS + Workload Identity, Private Endpoints, Sentinel SIEM.

> **Screenshot 2:** Submission result — SUBMITTED card with CLM-20260528-7B52F1AE, Policy POL-BOE-2026-005, PROPERTY, 45,000 GBP, description, submission timestamp.

> **Screenshot 3:** AI Analysis tab — MEDIUM RISK and INVESTIGATE badges in amber, risk score gauge bar at 35%, AI Summary paragraph, FRAUD INDICATORS DETECTED section in red showing "Future incident date provided (2026-05-01)", KEY FACTS EXTRACTED grid with Claim Type, Claim Amount, Incident Date, Incident Description, Location London.

📖 [Azure Static Web Apps documentation](https://learn.microsoft.com/en-us/azure/static-web-apps/overview)

---

## Databricks Medallion Pipeline {#databricks-medallion}

**What it is:** Azure Databricks Premium processes raw claim events through Bronze (raw ingestion), Silver (validation and enrichment), and Gold (risk scoring and aggregations) Delta Lake layers.

**Why Databricks:** Databricks provides Spark for distributed processing, Delta Lake for ACID transactions and time travel on blob storage, MLflow for model tracking, and collaborative notebooks. Delta Lake time travel — querying data as it appeared at any point in time — is essential for financial regulatory compliance.

**Why the medallion pattern:**
- Bronze is an immutable audit log — never modified, never deleted
- Silver applies business rules but never discards records — quality flags are metadata, not filters
- Gold serves business consumers with optimised, aggregated data

> **Screenshot 1:** Azure Portal — `dbw-claims-dev-uks`, Active, Premium tier (RBAC), UK South, Managed Resource Group linked.

> **Screenshot 2:** Databricks Workspace Shared folder showing all 6 notebooks: claims-fraud-detection (experiment), claims_fraud_detection_mlflow, claims_intelligence_dashboard, claims_medallion_pipeline, claims_medallion_v2, claims_structured_streaming.

> **Screenshot 3:** `claims_medallion_v2` notebook — title "Contoso Claims Intelligence Platform — Medallion Pipeline: Bronze to Silver to Gold", showing ADLS Gen2 configuration with storage account and container definitions.

### Bronze Layer

Raw JSON ingested from `bronze/incoming/` into Delta Lake with zero transformation. Records stamped with `_ingested_at` and `_record_hash`.

### Silver Layer

Transformations applied:
- Type casting (strings to timestamps, normalised enums)
- Document Intelligence JSON parsed into typed columns
- Three data quality flags: `dq_missing_policy`, `dq_amount_mismatch` (>10% variance), `dq_low_confidence` (<0.7)
- Deduplication on `claim_id`

Records never deleted — DQ flags flow forward as metadata.

### Gold Layer

`claims_risk` — per-claim rule-based scores:

| Band | Score | Trigger |
|------|-------|---------|
| HIGH | 0.8 | Document Intelligence fraud indicators |
| HIGH | 0.7 | Amount mismatch >10% |
| MEDIUM | 0.6 | Low extraction confidence |
| MEDIUM | 0.7 | >180 days to submission |
| LOW | 0.1 | No indicators |

`claims_summary` — aggregated by claim type and status.

> **Screenshot 4:** Databricks Compute page — `claims-pipeline-v2` Running (green dot), 48GB memory, 12 cores, 3 DBU/h, Runtime 15.4 LTS (Apache Spark 3.5.0, Scala 2.12), Standard_D4s_v5 workers.

📖 [Databricks medallion architecture](https://www.databricks.com/glossary/medallion-architecture)
📖 [Delta Lake documentation](https://docs.delta.io/latest/index.html)

---

## MLflow Fraud Detection {#mlflow-fraud-detection}

**What it is:** MLflow tracks every training experiment and stores models in a versioned registry. Without MLflow, you do not know which model is in production, what parameters it used, or how it compares to alternatives.

**Three models compared:**
- GradientBoostingClassifier (n_estimators=100, max_depth=4, learning_rate=0.1)
- RandomForestClassifier (n_estimators=100, max_depth=6)
- LogisticRegression (max_iter=1000)

**Features engineered from Gold Delta table:**
- `days_to_submit` — lateness of claim filing
- `amount_band` — claimed amount bucketed 0-3
- `has_fraud_indicators` — Document Intelligence flags
- `docintel_confidence` — extraction quality score
- `amount_mismatch` — claimed vs extracted variance >10%
- `claim_type_enc` — claim type encoded 0-3

Every run logs parameters, metrics (AUC, F1, precision, recall, cv_auc_mean), and the model artifact with input/output signature.

> **Screenshot 1:** Databricks Experiments — `claims-fraud-detection` experiment listed.

> **Screenshot 2:** `claims_fraud_detection_mlflow` notebook open — title "Claims Fraud Detection — MLflow + Scikit-learn", subtitle "Feature Engineering to Model Training to Experiment Tracking to Model Registry".

> **Screenshot 3:** MLflow experiment runs list — 6 runs (2 sets of 3 models), all green Succeeded, durations 11-17 seconds, model links registered.

> **Screenshot 4:** MLflow runs with metrics columns showing cv_auc_mean, f1, precision, recall. GradientBoosting and RandomForest: all 1.0. LogisticRegression: f1=0.889, precision=0.8.

> **Screenshot 5:** MLflow chart view — bar charts comparing all 6 runs across metrics simultaneously, colour-coded by model.

> **Screenshot 6:** Parallel Coordinates Plot comparing 3 runs on cv_auc_mean — visual parameter comparison.

> **Screenshot 7:** Run comparison — GradientBoosting vs RandomForest vs LogisticRegression side by side with parameters and metrics.

> **Screenshot 8:** Metrics comparison table — cv_auc_mean, f1, precision, recall, roc_auc for all 3 models.

> **Screenshot 9:** GradientBoosting run detail — Status Finished, 13.8 seconds, model registered as `claims-fraud-gradientboosting v2`, 5 metrics, 20 parameters.

> **Screenshot 10:** GradientBoosting Model Metrics charts — 5 bar charts all showing 1.00 for cv_auc_mean, f1, precision, recall, roc_auc.

> **Screenshot 11:** MLflow Registered Models — 3 models in Workspace Model Registry: claims-fraud-gradientboosting, claims-fraud-logisticregression, claims-fraud-randomforest, all Version 2.

> **Screenshot 12:** GradientBoosting model versions — Version 2 and Version 1 both registered and active.

> **Screenshot 13:** Model stage transition menu — Staging, Production, Archived options visible.

> **Screenshot 14:** Model promoted to Production — activity log showing "applied a stage transition None to Production" just seconds ago.

> **Screenshot 15:** Databricks Job Runs — `claims-fraud-detection` Running live, `medallion-stats` Succeeded, `medallion-run-4` Succeeded.

> **Screenshot 16:** Live notebook run — fraud-detection-mlflow-v2 executing, Status Running, 22 seconds elapsed, cluster `claims-pipeline-v2` running.

**Note on AUC = 1.0:** The models achieve perfect AUC because `has_fraud_indicators` is directly derived from the same logic that sets `risk_band = HIGH`. In production insurance fraud detection you would expect AUC 0.75-0.85. The pipeline architecture, experiment tracking, and model registry workflow are production-quality.

📖 [MLflow documentation](https://mlflow.org/docs/latest/index.html)

---

## Claims Intelligence Dashboard {#claims-dashboard}

**What it is:** A Databricks notebook producing three visualisations from the Gold Delta tables: risk distribution, financial exposure by risk band, and a rule-based vs ML comparison heatmap.

> **Screenshot 1:** Risk Band Distribution pie chart (HIGH 10.5%, MEDIUM 21.0%, LOW 68.5%), Risk by Claim Type bar chart across HEALTH/LIABILITY/MOTOR/PROPERTY, and ML Fraud Probability Distribution histogram with thresholds marked at 0.4 MEDIUM and 0.7 HIGH.

> **Screenshot 2:** Total Financial Exposure by Risk Band — HIGH 3.6M GBP, LOW 10.5M GBP, MEDIUM 3.8M GBP. Average Claim Value — HIGH 173,029 GBP, LOW 76,455 GBP, MEDIUM 90,971 GBP. High-value claims cluster in the HIGH risk band as expected.

> **Screenshot 3:** Rule-based vs ML Risk Classification heatmap — HIGH/HIGH: 21, LOW/LOW: 137, MEDIUM/LOW: 42. Near-diagonal pattern shows the rule-based and ML approaches are substantially aligned.

> **Screenshot 4:** Key metrics output showing: 200 total claims, 21 HIGH risk (10%), 17,928,654 GBP exposure, 10.5% avg ML fraud probability, GradientBoosting in Production, Delta tables: Bronze/Silver/Gold/ML-Scored.

---

## Observability — Sentinel and Log Analytics {#observability}

**What it is:** Every Azure resource streams diagnostic logs to a central Log Analytics workspace. Microsoft Sentinel provides SIEM capability on top of that workspace.

**Why centralised observability:** Without it, diagnosing a distributed system requires checking each resource individually. With Log Analytics and Sentinel, a single KQL query correlates Firewall IDPS alerts, Key Vault anomalies, and AKS egress into a unified timeline. A security analyst can see that the same IP that triggered a WAF rule also made an unusual Key Vault call 30 seconds later.

**Resources streaming to Log Analytics:**

| Resource | Data |
|----------|------|
| Azure Firewall | Application rules, network rules, IDPS alerts |
| App Gateway WAF | Access logs, WAF triggers, performance |
| API Management | Gateway logs, request data |
| AKS | Container logs, audit logs, cluster metrics |
| Key Vault | All audit events and access logs |
| Azure OpenAI | Request metrics, token usage |
| Databricks | Job runs, cluster events |
| AI Search | Operation logs, query metrics |

**Sentinel configuration:**
- Onboarded to Log Analytics workspace
- 3 alert rule sets: Azure Security Center, AAD Identity Protection, Defender ATP
- 12 Microsoft data connectors connected

> **Screenshot 1:** Microsoft Sentinel Overview — 0 incidents (the platform is secure), 3 active connectors, 4 analytics rules, data received graph showing ingestion activity.

> **Screenshot 2:** Sentinel Data Connectors — 12 connected including Azure Firewall, Azure Key Vault, Azure Storage Account, Azure WAF, Microsoft Defender for Cloud Apps, Microsoft Defender for Endpoint, Microsoft Defender for Identity.

📖 [Microsoft Sentinel documentation](https://learn.microsoft.com/en-us/azure/sentinel/overview)
📖 [Log Analytics documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-overview)

---

## Load Testing Results {#load-testing}

**Test configuration:** 20 virtual users, 3 minutes, JMeter test plan, WAF in Detection mode (Prevention mode blocks Azure Load Testing IPs).

**Full stack tested:** Internet to App Gateway WAF to APIM to AKS (3 replicas) to FastAPI.

| Metric | Health Check | Submit Claim | Total |
|--------|-------------|--------------|-------|
| Requests | 33,491 | 33,479 | **66,970** |
| Throughput | 184 req/s | 184 req/s | **368 req/s** |
| Median | 8ms | 6ms | **7ms** |
| p75 | 12ms | 8ms | 10ms |
| p95 | 510ms | 480ms | 490ms |
| p99 | 1,100ms | 1,090ms | **1,090ms** |
| Errors | **0%** | **0%** | **0%** |

> **Screenshot 1:** Azure Load Testing resource `alt-claims-dev-uks` overview.

> **Screenshot 2:** Run 3 WAF Detection results — Completed, 66,970 requests, 0% error rate, 367.97 req/s, 26ms P90, 3 minutes 5 seconds duration, 19 virtual users average.

> **Screenshot 3:** Client-side metrics charts — virtual users reach 20, response time stable around 25ms, requests/sec 365 aggregate flatline, errors: 0 for the entire duration.

> **Screenshot 4:** Engine health — CPU 7.95%, Memory 10.8%, Network 276KB/s, 20 virtual users max.

📖 [Azure Load Testing documentation](https://learn.microsoft.com/en-us/azure/load-testing/)

---

## Infrastructure as Code — Terraform {#terraform}

**What it is:** The entire platform is defined in Terraform 1.9.8. Every resource is expressed as code, version-controlled, and reproducible.

**Why Terraform:** Infrastructure as code provides reproducibility, auditability (every change is a git commit), peer review (terraform plan in pull request comments), and safety (plan shows exactly what will change before apply). The 19 modules mean the same code creates dev and prod with different variable values.

**Key patterns:**

`for_each` on subnets:
```hcl
resource "azurerm_subnet" "this" {
  for_each         = var.subnets
  name             = "snet-${var.name}-${each.key}"
  address_prefixes = [each.value.cidr]
}
```

Conditional diagnostics:
```hcl
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.log_analytics_workspace_id != null ? 1 : 0
}
```

**Architecture Decision Records:**

| ADR | Decision |
|-----|----------|
| ADR-001 | Bootstrap storage has purge protection disabled — Terraform cannot manage a resource that blocks Terraform from running |
| ADR-002 | AKS API server uses public endpoint with IP allowlist — private cluster requires additional DNS infrastructure |
| ADR-003 | APIM uses Internal VNet mode behind App Gateway — External mode bypasses WAF |
| ADR-004 | Azure Firewall Premium chosen over NSG-only — NSGs provide no Layer 7 inspection or IDPS |

📖 [Terraform AzureRM provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

---

## CI/CD Pipeline {#cicd}

**What it is:** GitHub Actions with OIDC federation — no secrets stored in GitHub.

**Pipeline structure:**

Pull requests trigger: terraform validate, tflint linting, trivy security scanning, gitleaks secret detection, terraform plan (read-only service principal), plan posted as PR comment.

Merge to main triggers: manual approval via GitHub Environment `dev-apply`, terraform apply (Contributor service principal), remote state stored in Azure Blob with lease locking.

Two service principals with separate scopes prevent CI (which runs on every PR including forks) from ever being able to deploy. Only the CD principal with explicit manual approval can apply changes.

📖 [GitHub Actions OIDC with Azure](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-oidc)

---

## Key Metrics Summary {#key-metrics}

### Platform

| Metric | Value |
|--------|-------|
| Terraform modules | 19 |
| Azure resources (dev) | ~50 |
| Environments | 2 (dev + prod) |
| Databricks notebooks | 6 |
| CI/CD workflows | 4 |

### Load test

| Metric | Value |
|--------|-------|
| Throughput | 368 req/s |
| Median response | 7ms |
| p95 response | 490ms |
| p99 response | 1,090ms |
| Error rate | 0% |
| Total requests | 66,970 |

### Data pipeline

| Metric | Value |
|--------|-------|
| Claims processed | 200 |
| Total exposure | 17,928,654 GBP |
| HIGH risk claims | 21 (10.5%) |
| ML models trained | 3 |
| Models in registry | 3 (Version 2) |
| Best model | GradientBoosting (Production) |

### Security layers

| Layer | Control | Deployed |
|-------|---------|---------|
| 1 | DDoS Protection Standard | Yes |
| 2 | Azure Firewall Premium IDPS | Yes |
| 3 | App Gateway WAF v2 OWASP 3.2 | Yes |
| 4 | API Management Internal VNet | Yes |
| 5 | Workload Identity (zero credentials) | Yes |
| 6 | Private Endpoints all PaaS services | Yes |

---

## What to Do Next (for a team member joining) {#what-next}

If you are reading this as someone new to the project:

1. **Clone the repository:** `git clone https://github.com/najeebzohaib/contoso-claims-platform`

2. **Read the ADRs first:** `docs/architecture/adr/` — understand why decisions were made before trying to change them

3. **Read the Terraform modules:** Start with `infra/modules/networking/main.tf` and `infra/modules/aks/main.tf`

4. **Run terraform plan in dev:** `cd infra/environments/dev && terraform plan` to see what is currently deployed

5. **Get your IP added to the AKS authorised IP range** before trying to use kubectl

6. **Port-forward to test the API locally:**
```bash
kubectl port-forward -n claims svc/claims-api 8080:80
curl http://localhost:8080/health
```

7. **Open the Databricks workspace:** `https://adb-7405608044495474.14.azuredatabricks.net` and browse the Shared notebooks and MLflow experiments

8. **Read the learning guide** in `docs/learning/` for exam preparation aligned to AZ-305

---

*Source code: github.com/najeebzohaib/contoso-claims-platform*

*Stack: Terraform 1.9.8, Azure UK South, Kubernetes 1.34.7, FastAPI, Databricks 15.4 LTS, MLflow, GitHub Actions OIDC*
