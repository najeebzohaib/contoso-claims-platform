# Architecture — Contoso Claims Intelligence Platform

## Hub-Spoke Network Topology

```mermaid
graph TB
    Internet((Internet))
    DDoS[DDoS Protection Standard]
    FW[Azure Firewall Premium<br/>IDPS + TLS Inspection]
    Bastion[Azure Bastion Standard<br/>Native Client + Tunneling]

    subgraph Hub ["Hub VNet 10.0.0.0/16"]
        FW
        Bastion
        GW[Gateway Subnet<br/>10.0.1.0/27]
    end

    subgraph DevSpoke ["Dev Spoke 10.10.0.0/16"]
        AppGW[App Gateway WAF v2<br/>10.10.4.0/24]
        APIM[API Management<br/>Internal VNet 10.10.5.0/24]
        AKS[AKS VMSS<br/>10.10.16.0/20]
        PE[Private Endpoints<br/>10.10.3.0/24]
        DBW[Databricks<br/>10.10.32-33.0/24]
    end

    subgraph ProdSpoke ["Prod Spoke 10.30.0.0/16"]
        AppGWP[App Gateway WAF v2]
        APIMP[API Management]
        AKSP[AKS VMSS]
        PEP[Private Endpoints]
        DBWP[Databricks]
    end

    Internet --> DDoS --> FW
    FW --> AppGW
    FW -.->|Peering| DevSpoke
    FW -.->|Peering| ProdSpoke
    Hub <-->|Peering| DevSpoke
    Hub <-->|Peering| ProdSpoke
    AppGW --> APIM --> AKS
    AKS --> PE

Request Flow — North/South Traffic
sequenceDiagram
    participant C as Client
    participant DDos as DDoS Protection
    participant FW as Azure Firewall Premium
    participant AGW as App Gateway WAF v2
    participant APIM as API Management
    participant AKS as AKS / claims-api
    participant OAI as Azure OpenAI
    participant Search as AI Search
    participant KV as Key Vault

    C->>DDos: HTTPS Request
    DDos->>FW: Volumetric check passed
    FW->>AGW: IDPS + TLS inspection passed
    AGW->>APIM: OWASP WAF passed, route to backend
    APIM->>AKS: Rate limit check, JWT validation, forward
    AKS->>KV: Fetch secrets (Workload Identity)
    AKS->>OAI: Analyse claim (private endpoint)
    AKS->>Search: Semantic search (private endpoint)
    AKS-->>APIM: Response
    APIM-->>AGW: Response + headers
    AGW-->>C: HTTPS Response

Identity & Zero Trust
graph LR
    subgraph Workload Identity
        AKS[AKS OIDC Issuer]
        SA[Kubernetes ServiceAccount<br/>claims:claims-api]
        UAMI[User Assigned MI<br/>id-claims-api-dev]
        FIC[Federated Identity<br/>Credential]
    end

    subgraph RBAC Assignments
        KV_Role[Key Vault Secrets User]
        OAI_Role[Cognitive Services OpenAI User]
        Search_Role[Search Index Data Reader]
        DL_Role[Storage Blob Data Contributor]
    end

    SA -->|bound to| UAMI
    AKS -->|issues OIDC token| FIC
    FIC -->|trusts| UAMI
    UAMI --> KV_Role
    UAMI --> OAI_Role
    UAMI --> Search_Role
    UAMI --> DL_Role

Data Platform — Medallion Architecture
graph LR
    subgraph Ingestion
        DocIntel[Document Intelligence<br/>PDF Extraction]
        API[Claims API<br/>REST Ingestion]
    end

    subgraph ADLS ["ADLS Gen2 — adlsclaimsdev0bd2"]
        Bronze[(Bronze<br/>Raw documents)]
        Silver[(Silver<br/>Validated + enriched)]
        Gold[(Gold<br/>Aggregated + ML-ready)]
    end

    subgraph Databricks ["Databricks Premium — VNet Injected"]
        NB1[Bronze → Silver<br/>Notebook]
        NB2[Silver → Gold<br/>Notebook]
        DL[Delta Lake]
    end

    subgraph Serving
        Search[AI Search Index]
        OAI[OpenAI Embeddings]
    end

    DocIntel --> Bronze
    API --> Bronze
    Bronze --> NB1 --> Silver
    Silver --> NB2 --> Gold
    NB1 -.-> DL
    NB2 -.-> DL
    Gold --> Search
    Gold --> OAI

CI/CD Pipeline
graph LR
    PR[Pull Request] --> Validate[terraform validate<br/>tflint + trivy]
    Validate --> Plan[terraform plan<br/>sp-claims-ci-dev<br/>Reader only]
    Plan --> Review[Plan output<br/>in PR comment]
    Review --> Merge[Merge to main]
    Merge --> Approval[GitHub Environment<br/>dev-apply<br/>Manual approval]
    Approval --> Apply[terraform apply<br/>sp-claims-cd-dev<br/>Contributor]
    Apply --> State[Remote state<br/>Azure Blob<br/>lease locking]

    style Approval fill:#ff9,stroke:#333

Security Controls Summary
Control
Implementation
Standard
Network segmentation
Hub-spoke + NSGs + UDR
Zero Trust
Perimeter protection
Firewall Premium IDPS
NCSC CAF
DDoS mitigation
DDoS Protection Standard
PCI-DSS
WAF
OWASP 3.2 Prevention
OWASP Top 10
API security
APIM rate limiting + JWT
OAuth 2.0
Identity
Workload Identity (no secrets)
Zero Trust
Secret management
Key Vault RBAC mode
CIS Azure
Private networking
Private Endpoints all PaaS
Zero Trust
VM access
Bastion (no public IPs)
CIS Azure
Audit logging
Diagnostic settings → Log Analytics
SOC 2
Threat detection
Firewall threat intelligence
NCSC

Architecture Decision Records
ADR-001 — Bootstrap storage security trade-offs
ADR-002 — AKS API server public vs private
ADR-003 — API Management placement pattern
ADR-004 — Azure Firewall and Zero Trust network


 EOF

cat > docs/architecture/adr/003-apim-pattern.md << 'EOF'
# ADR-003: API Management Placement Pattern

**Date:** 2025-05-21
**Status:** Accepted

## Context

The claims platform exposes APIs consumed by the React frontend and potentially by third-party partners. We need a consistent API gateway layer that provides rate limiting, authentication, request/response transformation, and a developer portal.

Key constraints:
- Financial services context requires all traffic to stay within private network boundaries
- Multiple API consumers with different rate limit tiers
- Need for API versioning and deprecation management
- Developer onboarding via self-service portal

## Decision

Deploy Azure API Management in **Internal VNet mode** behind Application Gateway.

Traffic flow:

Internet → App Gateway (WAF) → APIM (Internal) → AKS backend

APIM is placed in its own dedicated subnet (`10.10.5.0/24`) with no public IP exposure. The Application Gateway acts as the sole public entry point, providing WAF inspection before traffic reaches APIM.

## Consequences

**Positive:**
- All API traffic inspected by WAF before reaching APIM
- APIM private IP only reachable within VNet — no direct internet exposure
- Rate limiting, JWT validation, and transformation policies at gateway layer
- Developer portal accessible via Application Gateway for internal consumers
- API versioning and deprecation managed centrally
- Full audit trail in Log Analytics via APIM diagnostic settings

**Negative:**
- APIM Developer SKU has no SLA (acceptable for dev/test)
- 45-60 minute provisioning time
- Additional hop adds ~1-2ms latency
- Internal mode requires private DNS for `azure-api.net`

**Trade-off considered:**
Standard SKU with SLA (~£250/day) vs Developer SKU (~£45/day). For portfolio demonstration, Developer SKU is sufficient. Production would use Standard_1 minimum.

## Alternatives Rejected

- **APIM External mode:** Would expose APIM directly to internet without WAF protection. Rejected — does not meet financial services security baseline.
- **No APIM:** Direct App Gateway → AKS routing loses API versioning, rate limiting, and developer portal capabilities. Rejected.
- **Kong / nginx ingress only:** Open-source alternatives lack native Azure AD integration and enterprise support. Rejected for financial services context.
