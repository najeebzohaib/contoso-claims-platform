# Contoso Claims Intelligence Platform

An enterprise-grade Azure platform demonstrating production-ready architecture patterns for intelligent document processing, AI-powered claims analysis, and secure API management. Built as a portfolio project targeting financial services architecture standards.

## Architecture Overview


Internet → DDoS Protection → Azure Firewall Premium → App Gateway (WAF v2) → API Management (Internal) → AKS (VMSS) → Azure OpenAI / AI Search / Document Intelligence → Data Lake Gen2 (Bronze/Silver/Gold) → Databricks (Delta Lake)

### Security Layers
| Layer | Control | Implementation |
|-------|---------|----------------|
| Edge | DDoS Protection Standard | Hub VNet |
| Perimeter | Azure Firewall Premium | Hub, IDPS + TLS inspection |
| Ingress | Application Gateway WAF v2 | OWASP 3.2, Prevention mode |
| API | API Management (Internal VNet) | Rate limiting, auth policies |
| Identity | Workload Identity + UAMI | Zero standing credentials |
| Network | Private Endpoints only | All PaaS services |
| Secrets | Key Vault (RBAC mode) | No local auth |
| Access | Azure Bastion Standard | No public VM exposure |

## Platform Components

### Networking (Hub-Spoke)
| Resource | Purpose |
|----------|---------|
| Hub VNet `10.0.0.0/16` | Shared services, firewall, bastion |
| Dev Spoke `10.10.0.0/16` | Development workloads |
| Prod Spoke `10.30.0.0/16` | Production workloads |
| Azure Firewall Premium | North-South + East-West traffic control |
| Azure Bastion Standard | Secure VM/AKS node access |
| DDoS Protection Standard | Volumetric attack protection |

### Compute
| Resource | SKU | Purpose |
|----------|-----|---------|
| AKS `aks-claims-dev-uks` | Standard_D4s_v5 × 2 | Claims API pods |
| AKS Node Pools | VMSS (under the hood) | Horizontal scaling |
| Azure Container Registry | Premium | Private image store |

### AI Services
| Resource | Purpose |
|----------|---------|
| Azure OpenAI `cog-claims-dev-0bd2` | GPT-4 claims summarisation |
| Document Intelligence `cog-docintel-dev-0bd2` | PDF/form extraction |
| AI Search `srch-claims-dev-0bd2` | Semantic search over claims |

### Data Platform
| Resource | Purpose |
|----------|---------|
| ADLS Gen2 `adlsclaimsdev0bd2` | Bronze/Silver/Gold medallion |
| Databricks Premium `dbw-claims-dev-uks` | Spark processing, Delta Lake |
| Key Vault `kv-clmdev-0bd2` | Secrets, RBAC mode |

### API & Ingress
| Resource | SKU | Purpose |
|----------|-----|---------|
| Application Gateway | WAF_v2 | Public ingress, OWASP WAF |
| API Management | Developer_1 | API gateway, rate limiting |

### Observability
| Resource | Purpose |
|----------|---------|
| Log Analytics | Central log aggregation |
| Diagnostic Settings | All resources stream logs |
| Azure Monitor | Metrics and alerting |

## Environments

| Setting | Dev | Prod |
|---------|-----|------|
| Key Vault purge protection | No | **Yes** |
| Key Vault retention | 7 days | **90 days** |
| Log Analytics retention | 30 days | **90 days** |
| Data classification | internal | **confidential** |
| AKS API server | IP restricted | IP restricted |

## Repository Structure


infra/ ├── environments/ │ ├── dev/ # Dev environment root module │ └── prod/ # Prod environment root module ├── modules/ │ ├── acr/ # Azure Container Registry │ ├── ai_search/ # Azure AI Search │ ├── ai_services/ # OpenAI + Document Intelligence │ ├── aks/ # AKS with Workload Identity │ ├── apim/ # API Management (Internal VNet) │ ├── app_gateway/ # Application Gateway WAF v2 │ ├── bastion/ # Azure Bastion Standard │ ├── core/ # Naming + tagging conventions │ ├── data_lake/ # ADLS Gen2 + medallion containers │ ├── databricks/ # Databricks Premium + VNet injection │ ├── firewall/ # Azure Firewall Premium │ ├── key_vault/ # Key Vault (RBAC mode) │ ├── managed_identity/ # User Assigned Managed Identity │ ├── networking/ # VNet + subnets + NSGs │ ├── private_dns/ # Private DNS zones + VNet links │ ├── private_endpoint/ # Generic private endpoint │ └── vnet_peering/ # Bidirectional VNet peering docs/ ├── architecture/ │ ├── ARCHITECTURE.md │ └── adr/ # Architecture Decision Records .github/ └── workflows/ ├── terraform-validate.yml ├── terraform-plan.yml └── terraform-apply.yml

## CI/CD

OIDC federation — no secrets stored in GitHub:
- `sp-claims-ci-dev` — Reader, runs on PR (validate + plan)
- `sp-claims-cd-dev` — Contributor, runs on merge to main (apply)
- Concurrency group prevents stale queued runs

## Prerequisites

- Terraform 1.9.8 (via `tenv`)
- Azure CLI authenticated
- `backend.config` and `terraform.tfvars` (gitignored — see `*.example.*` files)

## Deploy

```bash
# Dev
cd infra/environments/dev
terraform init -backend-config=backend.config
terraform plan -out=dev.tfplan
terraform apply dev.tfplan

# Prod
cd infra/environments/prod
terraform init -backend-config=backend.config
terraform plan -out=prod.tfplan
terraform apply prod.tfplan

