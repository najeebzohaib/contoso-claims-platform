# Building an Enterprise AI Claims Intelligence Platform on Azure

*A production-grade cloud platform for insurance claims processing — AI-powered risk scoring, fraud detection, Zero Trust security, and a full data engineering pipeline on Delta Lake.*

---

## What This Is

This post walks through the design and implementation of the **Contoso Claims Intelligence Platform** — a fully operational Azure platform I built to demonstrate enterprise-grade cloud architecture at financial services standard. Every component described here is running in Azure UK South.

The platform processes insurance claims end-to-end: submission through an API, AI analysis via Azure OpenAI GPT-4o, document extraction via Document Intelligence, semantic search via AI Search, and a complete data pipeline on Databricks that transforms raw events into risk-scored Delta Lake tables.

**Live endpoints:**
- React UI: https://polite-stone-09da56a0f.7.azurestaticapps.net
- API health: http://4.158.34.10/claims/health
- Source code: https://github.com/najeebzohaib/contoso-claims-platform

---

## High-Level Architecture

The platform follows a hub-spoke network topology with six layers of security between the internet and the workload. Traffic enters through DDoS Protection → Azure Firewall Premium → Application Gateway WAF → API Management → AKS → Azure AI services, all connected via private endpoints with no public PaaS access.
<img width="1472" height="1640" alt="image" src="https://github.com/user-attachments/assets/02a2f8f8-2809-433d-acdb-fdf216db937b" />




---

## Hub-Spoke Network Design

**What it is:** Hub-spoke is the standard enterprise network topology on Azure. A central hub VNet hosts shared security and connectivity services. Workloads run in spoke VNets that peer to the hub. All traffic between spokes, and all egress to the internet, flows through the hub.

**Why I used it:** Network segmentation is a core requirement in regulated industries. Hub-spoke ensures that workloads are isolated from each other and that all internet-bound traffic is inspected by a centralised firewall — not handled ad-hoc per workload. NSG-only approaches fail this bar because they provide no Layer 7 inspection and no centralised egress logging.

**Hub VNet (10.0.0.0/16):**
- `AzureFirewallSubnet` 10.0.0.0/26 — Azure Firewall Premium
- `AzureFirewallManagementSubnet` 10.0.0.64/26 — Firewall management traffic
- `AzureBastionSubnet` 10.0.2.0/26 — Azure Bastion Standard
- `GatewaySubnet` 10.0.1.0/27 — reserved for ExpressRoute/VPN

**Dev Spoke (10.10.0.0/16):**
- `appgw` 10.10.4.0/24, `apim` 10.10.5.0/24, `aks` 10.10.16.0/20
- `pe` 10.10.3.0/24 (private endpoints), `dbw-public/private` 10.10.32-33.0/24

**Prod Spoke (10.30.0.0/16)** — identical topology with production-hardened settings (90-day retention, purge protection, confidential data classification).

All spoke egress uses User Defined Routes forcing `0.0.0.0/0` through the firewall private IP. Every AKS node outbound call — container registry pulls, Azure API calls, Ubuntu package updates — is inspected before leaving the network.

📖 [Azure hub-spoke network topology](https://learn.microsoft.com/en-us/azure/architecture/networking/architecture/hub-spoke)

---

## Six Layers of Security

### Layer 1 — DDoS Protection Standard

**What it is:** Azure DDoS Protection Standard provides always-on traffic monitoring and automatic mitigation of volumetric, protocol, and application-layer attacks. It is applied at the VNet level.

**Why I used it:** The free Basic tier provides only platform-level protection shared across all Azure customers. Standard provides per-resource adaptive tuning based on your traffic baseline, real-time mitigation telemetry, and a cost protection guarantee. For an insurance platform where availability is critical, Standard is the right choice.

Key capabilities:
- Adaptive tuning — learns normal traffic patterns and builds per-resource baselines
- Real-time telemetry — attack traffic, dropped packets, vectors visible in Azure Monitor
- Cost protection — Azure credits if a DDoS attack causes your resources to scale out

📖 [Azure DDoS Protection documentation](https://learn.microsoft.com/en-us/azure/ddos-protection/ddos-protection-overview)

---

### Layer 2 — Azure Firewall Premium

**What it is:** Azure Firewall is a fully stateful, cloud-native network security service. The Premium SKU adds capabilities specifically required for high-security workloads: IDPS, TLS inspection, and web categories.

**Why I used it:** NSGs operate at Layer 4 (IP/port). Azure Firewall Premium operates at Layer 7 (application layer) and provides three capabilities unavailable anywhere else:

**IDPS (Intrusion Detection and Prevention):** 58,000+ Layer 7 threat signatures updated in real-time by Microsoft. Running in Alert mode for visibility; can be switched to Deny for active blocking. Detects port scans, lateral movement, known malware C2 patterns.

**TLS Inspection:** Decrypts, inspects, and re-encrypts HTTPS traffic. This is critical for detecting C2 callbacks from compromised containers — attackers use HTTPS to blend in with legitimate traffic. Without TLS inspection, the firewall sees only encrypted blobs.

**Threat Intelligence:** Microsoft's global threat intelligence feed automatically blocks traffic to/from known malicious IPs, domains, and URLs.

The firewall policy explicitly allows AKS egress to container registries, Azure APIs, and Ubuntu package mirrors. Everything else is default-deny — preventing supply chain attacks where a compromised package attempts to exfiltrate data.

📖 [Azure Firewall Premium features](https://learn.microsoft.com/en-us/azure/firewall/premium-features)

---

### Layer 3 — Application Gateway v2 with WAF

**What it is:** Azure Application Gateway is a Layer 7 load balancer with an integrated Web Application Firewall. The v2 SKU is zone-redundant and supports autoscaling.

**Why I used it:** Application Gateway WAF is the public entry point for all API traffic. It provides OWASP rule-based protection at the edge, before requests reach APIM or AKS. Running in Prevention mode (not just Detection) means the WAF actively blocks attacks rather than just logging them.

Configuration:
- OWASP Core Rule Set 3.2 in Prevention mode
- Zone redundant across availability zones 1, 2, 3
- Autoscaling 0–10 instances
- Custom health probe to APIM with 200–404 acceptable status codes

**Terraform lesson:** Azure retired the inline `waf_configuration` block in `azurerm_application_gateway` in favour of standalone `azurerm_web_application_firewall_policy` resources. Upgrading provider versions required refactoring the module — an important reminder that Terraform modules need ongoing maintenance as providers evolve.

📖 [Application Gateway WAF documentation](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/ag-overview)

---

### Layer 4 — API Management (Internal VNet Mode)

**What it is:** Azure API Management is a fully managed API gateway. In Internal VNet mode it has no public IP and is only reachable through a load balancer or (as here) through Application Gateway.

**Why I used it:** APIM provides a structured API layer between the WAF and the backend services. Internal VNet mode ensures all traffic passes through the WAF first — there is no path to APIM that bypasses Application Gateway. This is the recommended enterprise pattern for regulated workloads.

APIM provides:
- Rate limiting — prevents API abuse and cost spikes from the OpenAI backend
- API versioning at `/claims/v1/`
- JWT validation policies (ready for Azure AD integration)
- Developer portal for self-service API discovery
- Request/response transformation and logging

Traffic path: `Internet → App Gateway (4.158.34.10) → APIM (10.10.5.4) → AKS internal LB (10.10.16.6)`

**Lesson learned:** APIM Internal VNet mode requires port 3443 inbound from the `ApiManagement` service tag and port 6390 from `AzureLoadBalancer`. Missing these NSG rules causes a cryptic 422 error during provisioning that references the management endpoint — not obvious from the documentation. Documented in ADR-003.

📖 [API Management networking concepts](https://learn.microsoft.com/en-us/azure/api-management/virtual-network-concepts)

---

### Layer 5 — Workload Identity (Zero Credential Architecture)

**What it is:** Azure Workload Identity allows Kubernetes pods to authenticate to Azure services using federated identity credentials — no secrets, no service principal credentials, nothing stored in the cluster.

**Why I used it:** Every alternative involves stored credentials that can be compromised: environment variables, Kubernetes secrets, mounted files. Workload Identity eliminates the secret entirely. The pod proves its identity through OIDC federation between AKS and Azure AD.

The flow:
1. AKS OIDC issuer enabled — provides a public OIDC endpoint
2. Kubernetes ServiceAccount annotated with the UAMI client ID
3. Federated Identity Credential links the OIDC issuer + ServiceAccount to the UAMI
4. Pods annotated with `azure.workload.identity/use: "true"` receive a projected service account token
5. `DefaultAzureCredential` exchanges the projected token for an Azure AD access token
6. Access token used to call OpenAI, AI Search, Key Vault — all via private endpoints

The UAMI (`id-claims-api-dev`) has exactly three RBAC assignments:
- `Cognitive Services OpenAI User` — call GPT-4o
- `Search Index Data Reader` — query AI Search
- `Storage Blob Data Contributor` — write to data lake

Nothing else. Principle of least privilege enforced at the identity level.

📖 [Azure Workload Identity documentation](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)

---

### Layer 6 — Private Endpoints (No Public PaaS)

**What it is:** Azure Private Endpoints give PaaS services a private IP address inside your VNet. Combined with `public_network_access_enabled = false`, this means the service is unreachable from the public internet entirely.

**Why I used it:** Without private endpoints, PaaS services (Key Vault, OpenAI, Storage) are reachable from the internet by anyone with valid credentials. Private endpoints eliminate this attack surface — there is no public endpoint to attack.

| Service | Private Endpoint | DNS Zone |
|---------|-----------------|----------|
| Key Vault | pe-kv-claims-dev-uks | privatelink.vaultcore.azure.net |
| ACR | pe-acr-claims-dev-uks | privatelink.azurecr.io |
| OpenAI | pe-openai-claims-dev-uks | privatelink.openai.azure.com |
| Document Intelligence | pe-docintel-claims-dev-uks | privatelink.cognitiveservices.azure.com |
| AI Search | pe-search-claims-dev-uks | privatelink.search.windows.net |

Private DNS zones in the hub resource group are linked to both hub and spoke VNets. The claims-api pods resolve `cog-claims-dev-0bd2.openai.azure.com` to a private IP — traffic never leaves the Azure network.

📖 [Azure Private Endpoint documentation](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)

---

## The Claims API

**What it is:** A FastAPI Python application running on AKS as a Kubernetes Deployment with 3 replicas behind an internal load balancer.

**Why FastAPI:** Async-native, auto-generated OpenAPI docs, Pydantic validation, and excellent performance. It produces the `/docs` endpoint APIM can import from directly.

Key endpoints:
- `POST /claims/v1/submit` — validate and store a new claim
- `GET /claims/v1/{claimId}` — retrieve claim by ID
- `POST /claims/v1/{claimId}/analyse` — GPT-4o risk analysis
- `GET /claims/v1/search?q=` — semantic search via AI Search

The analyse endpoint calls GPT-4o with a structured prompt that returns JSON:

```json
{
  "keyFacts": {
    "claimType": "PROPERTY",
    "claimAmount": 25000.0,
    "emergencyServicesInvolved": true
  },
  "riskScore": 0.4,
  "riskBand": "MEDIUM",
  "fraudIndicators": [
    "Third-party initiated claim without direct claimant contact"
  ],
  "recommendation": "INVESTIGATE",
  "summary": "The claim involves potential property damage due to flooding..."
}
```

GPT-4o is called via Workload Identity token — no API key stored anywhere. The token is fetched from `DefaultAzureCredential`, passed as `api_key` to the AzureOpenAI client with an explicit `httpx.Client()` to avoid proxy conflicts with the Azure Identity SDK.

📖 [Azure OpenAI Service documentation](https://learn.microsoft.com/en-us/azure/ai-services/openai/)
📖 [AKS documentation](https://learn.microsoft.com/en-us/azure/aks/)

---

## Databricks Medallion Architecture

**What it is:** The medallion architecture is a data design pattern that organises data in a lakehouse into three layers — Bronze (raw), Silver (validated), Gold (aggregated) — each building on the previous with increasing quality and structure.

**Why I used it:** The medallion pattern is the standard for financial data lakes. It provides full audit lineage (you can always trace a Gold record back to the original Bronze event), separation of concerns (ingestion, quality, and business logic are independent), and supports regulatory requirements for point-in-time data reconstruction via Delta Lake time travel.

**Why Delta Lake:** Delta Lake adds ACID transactions, schema enforcement, and time travel to Parquet files on blob storage. Without Delta, a failed pipeline job leaves partial writes. With Delta, every write is transactional — either it succeeds fully or the table is unchanged.


<img width="1472" height="760" alt="image" src="https://github.com/user-attachments/assets/d10c109e-6536-4871-97bc-4be17a59fd09" />

### Bronze — Raw Ingestion

Raw JSON claim records land in `bronze/incoming/` and are read directly into a Delta table with schema applied on read. Zero transformation. Every record is stamped with `_ingested_at` and `_record_hash` for deduplication detection.

### Silver — Validated and Enriched

- Type casting: strings to timestamps, normalised uppercase enums
- Document Intelligence field parsing: the `extracted_fields` JSON column is expanded into typed columns (`docintel_confidence`, `docintel_amount`, `docintel_fraud_indicators`)
- Three data quality flags: `dq_missing_policy`, `dq_amount_mismatch` (>10% variance), `dq_low_confidence` (<0.7)
- Deduplication on `claim_id`

Records are never deleted in Silver. DQ flags are metadata — downstream consumers decide how to handle them. Dropping data destroys audit lineage.

### Gold — Risk Scoring and Aggregations

`claims_risk` — per-claim risk assessment:

| Risk Band | Score | Trigger |
|-----------|-------|---------|
| HIGH | 0.8 | Document Intelligence fraud indicators present |
| HIGH | 0.7 | Claimed vs extracted amount mismatch |
| MEDIUM | 0.6 | Low extraction confidence |
| MEDIUM | 0.7 | >180 days incident to submission |
| MEDIUM | 0.5 | 90–180 days to submission |
| LOW | 0.1 | No indicators |

`claims_summary` — aggregated by claim type and status for BI and reporting:

| claim_type | status | count | total_claimed | avg_claimed |
|------------|--------|-------|---------------|-------------|
| MOTOR | APPROVED | 42 | £1,847,293 | £43,983 |
| PROPERTY | INVESTIGATION | 18 | £2,156,441 | £119,802 |
| LIABILITY | SUBMITTED | 31 | £892,103 | £28,778 |

The pipeline processed 200 realistic claims across 3 Delta tables in a single Spark job on a Standard_D4s_v5 × 2 worker cluster.

📖 [Databricks medallion architecture](https://www.databricks.com/glossary/medallion-architecture)
📖 [Delta Lake documentation](https://docs.delta.io/latest/index.html)
📖 [Azure Databricks documentation](https://learn.microsoft.com/en-us/azure/databricks/)

---

## Infrastructure as Code — Terraform

**What it is:** Terraform is a declarative infrastructure-as-code tool. You describe the desired state of your infrastructure, and Terraform computes the diff against the current state and applies changes safely.

**Why I used it:** The entire platform — 19 modules, two environments, ~4,000 lines of HCL — is defined in code. Every resource can be destroyed and recreated identically. Changes are reviewed as pull requests. The state is stored remotely in Azure Blob Storage with lease-based locking.

The module structure follows single-responsibility:
infra/modules/
├── acr/              ├── ai_search/       ├── ai_services/
├── aks/              ├── apim/            ├── app_gateway/
├── app_insights/     ├── bastion/         ├── core/
├── data_lake/        ├── databricks/      ├── firewall/
├── key_vault/        ├── managed_identity/├── networking/
├── private_dns/      ├── private_endpoint/├── sentinel/
└── static_web_app/   └── vnet_peering/

Key patterns used throughout:

`for_each` on subnets — one resource block manages all subnets:
```hcl
resource "azurerm_subnet" "this" {
  for_each         = var.subnets
  name             = "snet-${var.name}-${each.key}"
  address_prefixes = [each.value.cidr]
}
```

Conditional diagnostic settings — modules work with or without Log Analytics:
```hcl
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.log_analytics_workspace_id != null ? 1 : 0
}
```

**Key lesson — Azure reserved subnet names:** Azure Firewall requires a subnet named exactly `AzureFirewallSubnet`. Our networking module prefixes all subnets (`snet-{name}-{key}`), producing `snet-claims-hub-uks-AzureFirewallSubnet` — which Azure rejects. The fix is to create the Firewall, Management, and Bastion subnets as standalone `azurerm_subnet` resources outside the networking module. Documented in ADR-004. The same applies to `AzureFirewallManagementSubnet` and `AzureBastionSubnet`.

📖 [Terraform AzureRM provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

---

## CI/CD Pipeline

**What it is:** The CI/CD pipeline uses GitHub Actions with OIDC federation — no secrets stored in GitHub at all.

**Why OIDC instead of stored credentials:** A stored client secret can be leaked, rotated incorrectly, or forgotten. OIDC federation means GitHub Actions proves its identity to Azure AD using a short-lived, signed JWT — there is nothing to leak or rotate.

Two service principals with different scopes:
- `sp-claims-ci-dev` — Reader only, used for `terraform plan` on pull requests
- `sp-claims-cd-dev` — Contributor, used for `terraform apply` after manual approval

The split prevents CI (which runs on every PR, including from forks) from ever being able to deploy changes. Only the CD principal — used only after explicit approval in the GitHub Environment — can apply.
Pull Request opened
└── terraform validate + tflint + trivy security scan
└── terraform plan (read-only service principal)
└── Plan output posted as PR comment
Merged to main
└── Manual approval required (GitHub Environment: dev-apply)
└── terraform apply (Contributor service principal)
└── Remote state: Azure Blob with lease locking

The concurrency group `terraform-apply-dev` prevents multiple apply runs from running simultaneously — without this, rapid pushes queue stale plans that can destroy resources added by newer commits.

📖 [GitHub Actions OIDC with Azure](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-oidc)

---

## Load Test Results

Azure Load Testing was used to validate the platform under sustained load. 20 virtual users, 3 minutes, full stack end-to-end.

| Metric | Submit Claim | Health Check | Total |
|--------|-------------|--------------|-------|
| Requests | 33,479 | 33,491 | **66,970** |
| Throughput | 184 req/s | 184 req/s | **368 req/s** |
| Median response | 6ms | 8ms | **7ms** |
| p75 | 8ms | 12ms | 10ms |
| p95 | 480ms | 510ms | 490ms |
| p99 | 1,090ms | 1,100ms | **1,090ms** |
| Error rate | **0%** | **0%** | **0%** |

368 requests per second through five security layers with zero errors and sub-10ms median response. The p95/p99 latency reflects APIM policy evaluation overhead — acceptable for a claims processing platform.

📖 [Azure Load Testing documentation](https://learn.microsoft.com/en-us/azure/load-testing/)

---

## Observability

**What it is:** Observability is the ability to understand what is happening inside a system from its external outputs — logs, metrics, and traces.

**Why this matters:** In regulated industries, you must be able to answer "what happened, when, and why" for any event. This requires logs from every layer of the stack, correlated in one place.

Every resource streams diagnostic data to a central Log Analytics workspace:

| Source | Data Streamed |
|--------|--------------|
| Azure Firewall | Application rules, network rules, IDPS alerts |
| App Gateway WAF | Access logs, WAF rule triggers |
| APIM | Gateway logs, request data |
| AKS | Container logs, cluster metrics, audit logs |
| Key Vault | All audit events and access logs |
| OpenAI | Request metrics, token usage |
| Databricks | Job runs, cluster events |
| AI Search | Operation logs, query metrics |

**Microsoft Sentinel** is a cloud-native SIEM (Security Information and Event Management) system onboarded on top of the same Log Analytics workspace. It correlates signals across all platform components — a Firewall IDPS alert, a Key Vault anomaly, and unusual AKS pod egress become a single correlated incident rather than three separate unrelated alerts.

Alert rules configured:
- Azure Security Center incidents
- Azure Active Directory Identity Protection
- Microsoft Defender ATP

📖 [Log Analytics documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-overview)
📖 [Microsoft Sentinel documentation](https://learn.microsoft.com/en-us/azure/sentinel/overview)

---

## Dev vs Production

| Setting | Dev | Prod |
|---------|-----|------|
| Key Vault purge protection | Disabled | **Enabled** |
| Key Vault soft-delete retention | 7 days | **90 days** |
| Log Analytics retention | 30 days | **90 days** |
| Data classification tag | `internal` | **`confidential`** |
| Hub VNet | 10.0.0.0/16 | 10.1.0.0/16 |
| Spoke VNet | 10.10.0.0/16 | 10.30.0.0/16 |
| DDoS Protection | Shared plan | Shared plan |

Both environments are deployed from identical Terraform modules — only variable values differ. There is no environment-specific code.

---

## Architecture Decision Records

Four ADRs document the key design decisions made during the build:

**ADR-001 — Bootstrap storage security:** Why `purge_protection_enabled = false` on the Terraform state storage account. Terraform cannot manage a resource that prevents Terraform from deleting itself. Mitigated by GRS replication and 30-day soft delete retention.

**ADR-002 — AKS API server access:** Public API server with IP allowlist versus a private cluster. A private cluster requires additional DNS infrastructure and a jumpbox or Bastion for kubectl operations. IP-restricted public server provides equivalent security with simpler operations for this use case.

**ADR-003 — APIM Internal VNet mode:** Internal VNet behind Application Gateway versus External APIM. External APIM exposes the gateway directly to the internet without WAF protection. Internal mode ensures all traffic passes through the WAF first.

**ADR-004 — Azure Firewall versus NSG-only:** NSGs operate at Layer 4 with no IDPS, no TLS inspection, and no centralised egress logging. Azure Firewall Premium provides all three and satisfies the defence-in-depth requirement for regulated workloads.

---

## What I Would Do Differently

- **Redis Cache for claims state** — the API currently uses an in-memory dictionary, not shared across pods or persistent across restarts. Production requires Azure Cache for Redis.
- **APIM Standard SKU** — Developer SKU has no SLA. Standard_1 provides 99.95% availability.
- **Private AKS API server** — public server with IP allowlist is acceptable for dev; production should use a private cluster with Bastion for kubectl access.
- **Defender for Cloud** — Microsoft Defender for Containers should be enabled for runtime threat detection inside AKS pods.
- **Load test with WAF Prevention from the start** — the load test ran with WAF in Detection mode. Production load testing should run with Prevention enabled and OWASP rules tuned to eliminate false positives before go-live.

---

## Conclusion

This platform demonstrates what enterprise Azure architecture looks like in practice — not in a tutorial, but under real load with real AI workloads.

The key things it demonstrates for a senior cloud architecture role:

1. **Security as a design principle** — six layers from the ground up, not bolted on
2. **Zero Trust in practice** — Workload Identity, private endpoints, no standing credentials
3. **IaC at scale** — 19 reusable Terraform modules, two environments, OIDC CI/CD
4. **AI integration patterns** — Azure OpenAI behind private endpoints, called with federated identity
5. **Financial data engineering** — medallion architecture with Delta Lake and full audit lineage
6. **Operational excellence** — Log Analytics, Sentinel, App Insights, diagnostics on every resource

---

*Source code: [github.com/najeebzohaib/contoso-claims-platform](https://github.com/najeebzohaib/contoso-claims-platform)*

*Stack: Terraform 1.9.8 · Azure UK South · GitHub Actions OIDC · FastAPI · Databricks Delta Lake*


---

## Databricks ML Results

After running the fraud detection pipeline on 200 claims:

| Metric | Value |
|--------|-------|
| Total claims analysed | 200 |
| HIGH risk claims | 21 (10.5%) |
| Total financial exposure | £17,928,654 |
| Avg ML fraud probability | 10.5% |
| Best model | GradientBoosting (AUC=1.0 on synthetic data) |
| Models in registry | 3 (GradientBoosting, RandomForest, LogisticRegression) |
| Production model | claims-fraud-gradientboosting v2 |

Note: AUC=1.0 reflects synthetic data where features directly encode the label.
Real-world insurance data would yield AUC 0.75-0.85.
