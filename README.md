# Contoso Claims Intelligence Platform

An enterprise-grade Azure platform for AI-powered insurance claims processing, built to financial services security standards.

## Live Demo
- **Frontend:** https://polite-stone-09da56a0f.7.azurestaticapps.net
- **API:** https://4.158.34.10/claims/health

## Architecture

Six security layers: DDoS Protection → Azure Firewall Premium → App Gateway WAF v2 → API Management → AKS (Workload Identity) → Private Endpoints


Internet → DDoS → Firewall Premium → AppGW WAF → APIM → AKS → Azure OpenAI GPT-4o → Document Intelligence → AI Search → Key Vault ADLS Gen2 Bronze/Silver/Gold Databricks Premium (MLflow)

## What It Does

- **Claims submission** via FastAPI on AKS with Workload Identity (zero credentials)
- **GPT-4o analysis** — risk scoring, fraud detection, structured recommendations
- **Databricks medallion pipeline** — Bronze → Silver → Gold Delta Lake tables
- **MLflow fraud detection** — 3 ML models trained, tracked, registered, and promoted to Production
- **Semantic search** via Azure AI Search

## Load Test Results

| Metric | Value |
|--------|-------|
| Throughput | 368 req/s |
| Median response | 7ms |
| p99 response | 1,090ms |
| Error rate | 0% |
| Test duration | 3 minutes, 20 virtual users |

## Infrastructure

19 Terraform modules · 2 environments (dev + prod) · GitHub Actions OIDC CI/CD


infra/ modules/ # 19 reusable modules environments/ dev/ # terraform.tfvars, backend.config (gitignored) prod/ src/ claims-api/ # FastAPI application + Kubernetes manifests frontend/ # React UI → Azure Static Web Apps notebooks/ # Databricks MLflow fraud detection loadtests/ # Azure Load Testing JMX docs/ architecture/ # Architecture diagrams + ADRs blog/ # Technical blog post

## Security

| Layer | Control |
|-------|---------|
| 1 | DDoS Protection Standard |
| 2 | Azure Firewall Premium (IDPS, TLS inspection) |
| 3 | Application Gateway WAF v2 (OWASP 3.2) |
| 4 | API Management Internal VNet |
| 5 | Workload Identity (zero credentials) |
| 6 | Private Endpoints (all PaaS services) |

## Tech Stack

**Infrastructure:** Terraform 1.9.8, Azure UK South, GitHub Actions OIDC  
**Application:** Python FastAPI, AKS, Azure Container Registry  
**AI:** Azure OpenAI GPT-4o, Document Intelligence, AI Search  
**Data:** Databricks Premium, Delta Lake, ADLS Gen2, MLflow  
**Security:** Azure Firewall Premium, WAF, APIM, Sentinel, Key Vault  
**Observability:** Log Analytics, Microsoft Sentinel, Application Insights  

## Blog Post

Full technical write-up: [docs/blog/contoso-claims-intelligence-platform.md](docs/blog/contoso-claims-intelligence-platform.md)
