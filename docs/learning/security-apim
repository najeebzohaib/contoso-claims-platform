# Module 2b — API Management, Workload Identity, and Private Endpoints
## Based on the Contoso Claims Platform

**Time to complete:** 2-3 hours
**Builds on:** Module 1 (networking), Module 2a (Firewall, WAF)

---

## What You Will Understand After This Module

- What API Management actually does and why it exists
- Why Internal VNet mode is more secure than External
- What a policy is and how APIM applies them
- What identity means in Azure — users, service principals, managed identities
- Why Workload Identity is the gold standard for zero-credential architecture
- Exactly how a pod authenticates to Azure OpenAI without any stored secret
- What a private endpoint is at the network interface level
- Why DNS is the critical piece that makes private endpoints work
- How all three of these components work together in your platform

---

## Part 1 — What Problem API Management Solves

Imagine you have 10 backend services and 5 client applications calling them. Without APIM:

```
Client A → claims-api directly
Client B → claims-api directly
Client C → fraud-api directly
Client D → claims-api directly
Client E → fraud-api directly
```

Every client needs to know:
- The address of each backend service
- How to authenticate to each one
- How to handle rate limits, retries, errors
- Which version of each API to call

When the backend changes its URL, all clients break. When you add authentication, all clients need updating. When one client abuses the API, all others suffer.

APIM solves this by being a single, stable facade in front of all backends:

```
All clients → APIM (one address, one auth mechanism, one contract)
                ↓
         APIM routes to:
           → claims-api
           → fraud-api
           → any other backend
```

Clients only know about APIM. Backends only know about APIM. They are decoupled. You can change the backend URL, add authentication, enforce rate limits, or transform request/response formats — all in APIM without touching clients or backends.

📖 [Azure API Management overview](https://learn.microsoft.com/en-us/azure/api-management/api-management-key-concepts)

---

## Part 2 — APIM Architecture in Your Platform

Your APIM instance sits in the dev spoke VNet:

```
apim-claims-dev-uks
  Location:        UK South
  SKU:             Developer (no SLA — acceptable for dev/learning)
  VNet mode:       Internal
  Private IP:      10.10.5.4
  Subnet:          snet-claims-dev-uks-apim (10.10.5.0/24)
  Backend:         http://10.10.16.6 (AKS internal LB)
```

**The APIM components you need to know:**

**Gateway** — the runtime component that receives API requests and forwards them to backends. This is what lives at 10.10.5.4. In Internal VNet mode, only resources inside the VNet can reach it.

**Management plane** — the administrative interface for configuring APIs, policies, products, and users. Accessed via the Azure Portal or REST API. This uses port 3443 (why the NSG rule exists from Module 1).

**Developer portal** — a self-service website where API consumers can discover APIs, read documentation, and get access keys. Hosted at `apim-claims-dev-uks.developer.azure-api.net`.

📖 [APIM architecture overview](https://learn.microsoft.com/en-us/azure/api-management/api-management-key-concepts#api-management-components)

---

## Part 3 — APIM VNet Modes Explained

APIM supports three networking modes:

### External mode (default)
```
Internet → APIM public IP → backend
```
APIM has a public IP. Anyone on the internet can call your APIs if they have a key. The WAF is not enforced unless you explicitly place App Gateway in front. This is fine for public-facing APIs with no enterprise security requirements.

### Internal mode (your platform)
```
Internet → App Gateway (WAF) → APIM private IP → backend
```
APIM has no public IP. It can only be reached from within the VNet. The only path from the internet to APIM is through App Gateway. This means:
- WAF is always enforced — there is no way to bypass it
- APIM management endpoints are not reachable from the internet
- Even if someone discovers the APIM URL, they cannot reach it

This is the correct choice for financial services and regulated workloads.

### None (no VNet integration)
APIM calls backends over the internet. Used only when backends are public APIs. Not relevant for your platform.

**Why not just use Internal mode for everything?**

Internal APIM requires:
- A dedicated subnet (/27 minimum, you used /24)
- Specific NSG rules (port 3443, 6390)
- An App Gateway or VPN to access it from outside the VNet
- 45+ minutes to provision (versus ~10 minutes for External)

The complexity is justified for regulated workloads. For a simple public API with no compliance requirements, External mode is simpler and sufficient.

📖 [APIM Virtual network concepts](https://learn.microsoft.com/en-us/azure/api-management/virtual-network-concepts)
📖 [APIM with internal VNet and Application Gateway](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-integrate-internal-vnet-appgateway)

---

## Part 4 — APIM Policies

Policies are the most powerful feature of APIM. A policy is an XML document that runs on every request at four stages:

```xml
<policies>
  <inbound>   <!-- runs when request arrives at APIM, before forwarding -->
  </inbound>
  <backend>   <!-- controls how request is forwarded to backend -->
  </backend>
  <outbound>  <!-- runs on the response from backend, before returning to client -->
  </outbound>
  <on-error>  <!-- runs if an error occurs at any stage -->
  </on-error>
</policies>
```

### The CORS policy you applied

CORS (Cross-Origin Resource Sharing) is a browser security mechanism. A browser will refuse to let JavaScript on `localhost:3000` call an API at `4.158.34.10` unless the API explicitly says "I allow requests from this origin."

Your CORS policy:
```xml
<inbound>
  <base />
  <cors allow-credentials="false">
    <allowed-origins>
      <origin>*</origin>
    </allowed-origins>
    <allowed-methods>
      <method>GET</method>
      <method>POST</method>
      <method>OPTIONS</method>
    </allowed-methods>
    <allowed-headers>
      <header>*</header>
    </allowed-headers>
  </cors>
</inbound>
```

`<origin>*</origin>` allows any origin. In production you would restrict this to specific domains: `<origin>https://your-domain.com</origin>`.

### Other common policies

**Rate limiting:**
```xml
<inbound>
  <rate-limit calls="100" renewal-period="60" />
</inbound>
```
Maximum 100 calls per 60 seconds per subscription key. Exceeding this returns 429 Too Many Requests. Protects backend services and prevents runaway Azure OpenAI costs.

**JWT validation:**
```xml
<inbound>
  <validate-jwt header-name="Authorization" failed-validation-httpcode="401">
    <openid-config url="https://login.microsoftonline.com/{tenant}/.well-known/openid-configuration" />
    <required-claims>
      <claim name="aud" match="any">
        <value>your-app-id</value>
      </claim>
    </required-claims>
  </validate-jwt>
</inbound>
```
Validates that requests include a valid Azure AD JWT token. Unauthenticated requests return 401. This is how you add authentication to your API without changing the backend code — APIM validates the token, and if valid, the request proceeds to AKS.

**Request transformation:**
```xml
<inbound>
  <set-header name="X-Internal-Request" exists-action="override">
    <value>true</value>
  </set-header>
</inbound>
```
Adds a header to every request before forwarding to the backend. The backend can check for this header to confirm the request came through APIM (not directly).

📖 [APIM policies overview](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-policies)
📖 [APIM policy reference](https://learn.microsoft.com/en-us/azure/api-management/api-management-policies)
📖 [APIM CORS policy](https://learn.microsoft.com/en-us/azure/api-management/cors-policy)
📖 [APIM rate limiting](https://learn.microsoft.com/en-us/azure/api-management/rate-limit-policy)

---

## Part 5 — Identity in Azure: The Full Picture

Before understanding Workload Identity, you need to understand how identity works in Azure.

### Azure Active Directory (now called Microsoft Entra ID)

Azure AD is the identity provider for all of Azure. Every authentication and authorisation decision in Azure goes through Azure AD. When you log into the Portal, when a service calls an API, when Terraform deploys resources — Azure AD is involved every time.

Azure AD holds four types of security principals:

**User** — a human being with a username and password (or passkey, MFA, etc.). You log in as `zohaib.najeeb@gmail.com`.

**Group** — a collection of users. RBAC can be assigned to groups instead of individual users.

**Service Principal** — an identity for an application or automated process. Has a client ID and either a secret or a certificate. Used when a non-human needs to authenticate (CI/CD pipelines, scripts, third-party tools).

**Managed Identity** — like a service principal but managed entirely by Azure. No secrets, no certificates, no rotation. Azure handles everything. Two types:
- System-assigned: tied to a specific Azure resource, deleted when the resource is deleted
- User-assigned: independent resource, can be assigned to multiple Azure resources

📖 [Microsoft Entra ID (Azure AD) overview](https://learn.microsoft.com/en-us/entra/fundamentals/whatis)
📖 [Azure managed identities overview](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview)
📖 [Service principals in Azure](https://learn.microsoft.com/en-us/entra/identity/develop/app-objects-and-service-principals)

---

## Part 6 — Why Stored Credentials Are Dangerous

Every approach to authentication that involves storing a credential has the same fundamental problem: the credential can be stolen.

**Scenario: API key in environment variable**
```yaml
# Kubernetes deployment.yaml
env:
  - name: OPENAI_API_KEY
    value: "sk-proj-abc123..."   # hardcoded — visible in git history
```
Risk: anyone with access to the git repository, Kubernetes secrets, or the running pod can steal this key.

**Scenario: Service principal secret in Key Vault**
```python
# Slightly better — key is in Key Vault
secret = keyvault_client.get_secret("openai-api-key")
```
But how does the pod authenticate to Key Vault? It needs a credential to get the credential. This is the "secret zero" problem.

**Scenario: Managed Identity for Key Vault, API key for OpenAI**
The pod uses Managed Identity to get the Key Vault secret, then uses the API key from Key Vault to call OpenAI. Better — but the API key still exists somewhere and must be rotated periodically.

**The ideal: no credentials anywhere**

Workload Identity eliminates the API key entirely. The pod proves its identity using a cryptographic token issued by Kubernetes and verified by Azure AD. There is nothing to steal, nothing to rotate, nothing to accidentally commit to git.

---

## Part 7 — Workload Identity: How It Actually Works

This is one of the most important things to understand deeply. Walk through each step.

### The components involved

```
AKS cluster
  └── OIDC issuer URL (public endpoint)
        └── Issues signed JWTs for Kubernetes ServiceAccounts

Azure AD
  └── User Assigned Managed Identity (UAMI): id-claims-api-dev
        └── Client ID: 780d14ad-dc71-40e9-a7fe-72186d7c54d5
        └── Federated Identity Credential
              └── Issuer: AKS OIDC URL
              └── Subject: system:serviceaccount:claims:claims-api-sa
              └── Audience: api://AzureADTokenExchange

Kubernetes
  └── ServiceAccount: claims-api-sa (namespace: claims)
        └── Annotation: azure.workload.identity/client-id: 780d14ad...

Pod
  └── Label: azure.workload.identity/use: "true"
  └── Volume mount: /var/run/secrets/azure/tokens/azure-identity-token
```

### Step by step: what happens when a pod starts

**Step 1 — Kubernetes creates a projected token**

When the pod starts with `azure.workload.identity/use: "true"`, the AKS webhook (`azure-wi-webhook-controller-manager` — you saw this in your AKS workloads list) automatically:
- Mounts a projected volume with a short-lived JWT token
- Sets environment variables: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_FEDERATED_TOKEN_FILE`

The JWT token is signed by the AKS OIDC issuer. It contains:
```json
{
  "iss": "https://oidc.prod-aks.azure.com/your-tenant/your-cluster",
  "sub": "system:serviceaccount:claims:claims-api-sa",
  "aud": ["api://AzureADTokenExchange"],
  "exp": 1234567890
}
```

**Step 2 — Application code calls Azure AD**

When the Python code runs `DefaultAzureCredential()` or `ManagedIdentityCredential()`, the Azure Identity SDK:
1. Reads the token file at `/var/run/secrets/azure/tokens/azure-identity-token`
2. Reads `AZURE_CLIENT_ID` from the environment
3. Sends a request to Azure AD:
```
POST https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token
  client_id: 780d14ad-dc71-40e9-a7fe-72186d7c54d5
  client_assertion: [the JWT from the file]
  client_assertion_type: urn:ietf:params:oauth:client-assertion-type:jwt-bearer
  grant_type: urn:ietf:params:oauth:grant-type:jwt-bearer
  scope: https://cognitiveservices.azure.com/.default
```

**Step 3 — Azure AD validates the token**

Azure AD:
1. Reads the `iss` (issuer) from the JWT: the AKS OIDC URL
2. Fetches the public keys from that OIDC URL (this is why OIDC issuer must be public)
3. Verifies the JWT signature using those public keys
4. Checks the Federated Identity Credential: does this issuer + subject combination match a registered credential for client ID `780d14ad...`? Yes.
5. Issues an Azure AD access token for the requested scope (Azure OpenAI)

**Step 4 — Pod uses the Azure AD token**

The Azure Identity SDK receives the Azure AD access token and uses it to call OpenAI:
```
POST https://cog-claims-dev-0bd2.openai.azure.com/openai/deployments/gpt-4o/chat/completions
Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGci...
```

Azure OpenAI validates this token, confirms the identity has `Cognitive Services OpenAI User` role, and processes the request.

**What was never stored:**
- No API key
- No client secret
- No certificate
- No password

The only thing that existed was a short-lived JWT that expires in 24 hours and is automatically refreshed by the webhook.

### Why User-Assigned Managed Identity instead of System-Assigned?

System-assigned MI is tied to the AKS cluster resource. If you delete and recreate the cluster (which happens during upgrades), the MI changes and all RBAC assignments are lost. User-assigned MI is independent — it persists across cluster recreation and can be pre-assigned the necessary roles before the cluster exists.

📖 [Azure Workload Identity overview](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
📖 [Workload Identity federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation)
📖 [OIDC issuer in AKS](https://learn.microsoft.com/en-us/azure/aks/use-oidc-issuer)
📖 [Azure Identity SDK DefaultAzureCredential](https://learn.microsoft.com/en-us/azure/developer/python/sdk/authentication/credential-chains#defaultazurecredential-overview)

---

## Part 8 — RBAC: Controlling What Identities Can Do

Workload Identity proves who you are. RBAC controls what you can do.

### How RBAC works

RBAC has three components:

**Role definition** — a named set of permissions. Examples:
- `Reader` — read any resource, no write
- `Contributor` — read and write resources, no RBAC management
- `Cognitive Services OpenAI User` — call OpenAI inference endpoints only
- `Storage Blob Data Contributor` — read, write, delete blobs

**Security principal** — who the role is assigned to (user, group, service principal, managed identity)

**Scope** — which resources the role applies to:
- Subscription — all resources in the subscription
- Resource Group — all resources in the group
- Resource — one specific resource

**Assignment** — the combination: principal + role + scope

### Your platform's RBAC assignments for claims-api

```
Identity: id-claims-api-dev (UAMI)

Assignment 1:
  Role:   Cognitive Services OpenAI User
  Scope:  cog-claims-dev-0bd2 (the specific OpenAI resource)
  Allows: call GPT-4o inference endpoint
  Denies: manage OpenAI resource, view keys, change configuration

Assignment 2:
  Role:   Search Index Data Reader
  Scope:  srch-claims-dev-0bd2 (the specific AI Search resource)
  Allows: query the search index
  Denies: create/delete indexes, manage the search service

Assignment 3:
  Role:   Storage Blob Data Contributor
  Scope:  adlsclaimsdev0bd2 (the specific storage account)
  Allows: read, write, delete blobs
  Denies: manage the storage account, change firewall rules
```

**The principle of least privilege:** each assignment grants exactly what is needed and nothing more. If the claims-api pod is compromised:
- The attacker can call OpenAI — but cannot exfiltrate OpenAI keys or disable the service
- The attacker can read/write blobs — but cannot delete the storage account or change its configuration
- The attacker cannot read Key Vault secrets
- The attacker cannot modify the AKS cluster
- The attacker cannot create new Azure resources

This limits the blast radius of a compromise. The attacker is contained within the permissions granted.

📖 [Azure RBAC overview](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview)
📖 [Azure built-in roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles)
📖 [Best practices for Azure RBAC](https://learn.microsoft.com/en-us/azure/role-based-access-control/best-practices)
📖 [Cognitive Services roles](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/role-based-access-control)

---

## Part 9 — Private Endpoints: Network-Level Detail

In Module 1 you learned what private endpoints do conceptually. Here is how they work at the network interface level.

### What actually gets created

When you create a private endpoint for Azure OpenAI, Azure creates:

1. **A Network Interface Card (NIC)** inside your chosen subnet (pe subnet, 10.10.3.0/24). This NIC gets a private IP — say `10.10.3.5`.

2. **A private DNS zone A record** in `privatelink.openai.azure.com`:
   ```
   cog-claims-dev-0bd2 → 10.10.3.5
   ```

3. **A private link** — Azure's internal connection from your NIC at `10.10.3.5` to the OpenAI service running on Azure's backbone.

4. **Public network access disabled** on the OpenAI resource — `public_network_access_enabled = false` in Terraform.

```
Your VNet
  └── pe subnet (10.10.3.0/24)
        └── NIC: 10.10.3.5
              └── [Azure backbone] → Azure OpenAI service
                                     (no internet, no public IP involved)
```

### What happens to traffic

```
Pod (192.168.1.21) wants to call OpenAI:

1. DNS resolution:
   Pod asks: what is cog-claims-dev-0bd2.openai.azure.com?
   Azure DNS (168.63.129.16) checks private DNS zone
   Returns: 10.10.3.5

2. TCP connection:
   Pod opens TCP connection to 10.10.3.5:443
   Azure routes this to the NIC in the pe subnet

3. Private link forwarding:
   Azure private link forwards the connection to OpenAI's internal endpoint
   Traffic travels entirely on Azure's backbone network
   Never leaves the Azure network, never touches the internet

4. OpenAI processes request and returns response
   Response travels back through the same path
```

### Why public_network_access_enabled = false matters

If you create a private endpoint but leave public network access enabled, the service is reachable from BOTH the private endpoint AND the public internet. This defeats the purpose.

With `public_network_access_enabled = false`:
- Traffic from inside your VNet → private endpoint → works
- Traffic from the internet → OpenAI public URL → 403 Forbidden
- Traffic from another Azure subscription → OpenAI public URL → 403 Forbidden

The service is effectively invisible to anyone outside your VNet.

### The DNS problem (critical to understand)

Private endpoints only work if DNS resolves to the private IP. This seems obvious but has a subtle failure mode.

**Scenario: Private endpoint created, DNS zone not linked to VNet**

```
Pod asks: what is cog-claims-dev-0bd2.openai.azure.com?
Azure DNS checks: is there a private DNS zone linked to this VNet? No.
Azure DNS falls back to public DNS.
Public DNS returns: 20.50.x.x (public Azure IP)
Pod connects to: 20.50.x.x
OpenAI returns: 403 Forbidden (public access disabled)
```

The private endpoint exists and is correctly configured. But the pod never uses it because DNS returned the wrong IP. This is one of the most common private endpoint issues in practice.

**The fix:** Ensure the private DNS zone is linked to every VNet that needs to use the private endpoint. Your Terraform `private_endpoint` module creates both the endpoint and the DNS zone link in a single module call, so they cannot get out of sync.

📖 [Azure Private Endpoint overview](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)
📖 [Private endpoint DNS configuration](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
📖 [Azure Private Link overview](https://learn.microsoft.com/en-us/azure/private-link/private-link-overview)
📖 [Troubleshoot private endpoint connectivity](https://learn.microsoft.com/en-us/azure/private-link/troubleshoot-private-endpoint-connectivity)

---

## Part 10 — How All Three Work Together in Your Platform

Now let's trace a complete request through APIM, Workload Identity, and private endpoints together.

```
Browser submits: POST /claims/v1/{claimId}/analyse

─── APIM LAYER ──────────────────────────────────────────────
1. App Gateway forwards request to APIM (10.10.5.4)
2. APIM checks: is there an operation matching POST /v1/{claimId}/analyse?
   Yes: "Analyse Claim" operation
3. APIM runs inbound policy:
   - CORS headers validated
   - (JWT validation would run here if configured)
4. APIM forwards to backend: http://10.10.16.6/{claimId}/analyse

─── AKS LAYER ───────────────────────────────────────────────
5. Internal LB (10.10.16.6) routes to claims-api pod
6. FastAPI endpoint /v1/{claimId}/analyse receives request
7. Retrieves claim from in-memory store

─── WORKLOAD IDENTITY LAYER ─────────────────────────────────
8. Code calls: azure_credential.get_token("https://cognitiveservices.azure.com/.default")
9. Azure Identity SDK reads token file: /var/run/secrets/azure/tokens/azure-identity-token
10. SDK sends token exchange request to Azure AD
11. Azure AD validates Kubernetes JWT, issues Azure AD access token
12. SDK returns: access_token = "eyJ0eXAiOiJKV1Qi..."

─── PRIVATE ENDPOINT LAYER ──────────────────────────────────
13. Code calls OpenAI SDK with the access token
14. SDK resolves: cog-claims-dev-0bd2.openai.azure.com
15. DNS returns: 10.10.3.5 (private endpoint NIC IP)
16. TCP connection to 10.10.3.5:443
17. Private link delivers to Azure OpenAI service
18. OpenAI validates access token, confirms Cognitive Services OpenAI User role
19. OpenAI processes claim with GPT-4o
20. Returns structured JSON analysis

─── RETURN PATH ─────────────────────────────────────────────
21. FastAPI returns JSON to APIM
22. APIM runs outbound policy (none configured, passes through)
23. APIM returns response to App Gateway
24. App Gateway returns to browser
```

Every layer adds a security control:
- APIM enforces API contract and policies
- Workload Identity proves the pod's identity without credentials
- Private endpoint keeps OpenAI traffic inside Azure's network

None of these layers knows about the others. They are independent. If Workload Identity fails, the request fails at step 8 — APIM and private endpoints are unaffected. If the private endpoint DNS breaks, the request fails at step 15. Each layer can be diagnosed independently.

---

## Part 11 — Reading Your Terraform APIM and Identity Code

### APIM in Terraform

In `infra/modules/apim/main.tf`:

```hcl
resource "azurerm_api_management" "this" {
  name                = "apim-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = "Developer_1"   # Developer SKU, 1 unit

  virtual_network_type = "Internal"     # Internal VNet mode

  virtual_network_configuration {
    subnet_id = var.apim_subnet_id      # the apim subnet (10.10.5.0/24)
  }

  identity {
    type = "SystemAssigned"             # APIM's own managed identity
  }
}
```

`virtual_network_type = "Internal"` is the critical line. This puts APIM in Internal mode with no public IP.

`sku_name = "Developer_1"` means Developer tier, 1 unit. Developer tier has no SLA and is for non-production use. For production, you would use Standard_1 or Premium_1 (Premium supports multi-region and availability zones).

### Workload Identity in Terraform

The UAMI resource:
```hcl
resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
}
```

The Federated Identity Credential — this is what links the Kubernetes ServiceAccount to the Azure identity:
```hcl
resource "azurerm_federated_identity_credential" "this" {
  name                = "fic-${var.name}"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.this.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.aks_oidc_issuer_url   # from AKS cluster output
  subject             = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
}
```

The `subject` follows the exact format Kubernetes uses to identify service accounts: `system:serviceaccount:{namespace}:{serviceaccount-name}`. If this does not exactly match what Kubernetes puts in the JWT, Azure AD rejects the token exchange.

The RBAC assignment:
```hcl
resource "azurerm_role_assignment" "openai" {
  scope                = var.openai_resource_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}
```

### Private Endpoint in Terraform

In `infra/modules/private_endpoint/main.tf`:

```hcl
resource "azurerm_private_endpoint" "this" {
  name                = "pe-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id   # the pe subnet (10.10.3.0/24)

  private_service_connection {
    name                           = "psc-${var.name}"
    private_connection_resource_id = var.resource_id   # OpenAI resource ID
    is_manual_connection           = false
    subresource_names              = [var.subresource]  # "account" for OpenAI
  }

  private_dns_zone_group {
    name                 = "dns-${var.name}"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}
```

`private_dns_zone_group` — this is what automatically creates the A record in the private DNS zone when the private endpoint is created. The IP is determined by Azure at creation time and written to the DNS zone. You do not hardcode the IP.

📖 [azurerm_api_management Terraform](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management)
📖 [azurerm_user_assigned_identity Terraform](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity)
📖 [azurerm_federated_identity_credential Terraform](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential)
📖 [azurerm_private_endpoint Terraform](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint)

---

## Part 12 — Troubleshooting APIM, Workload Identity, and Private Endpoints

### APIM returns 502 Bad Gateway

502 means APIM received the request but could not reach the backend.

**Common causes:**
- Backend URL wrong (should be `http://10.10.16.6`, not `https://`)
- Backend not running (AKS pod not ready)
- NSG on AKS subnet blocking inbound from APIM subnet
- AKS internal load balancer not provisioned (check `kubectl get svc -n claims`)

**Diagnosis:**
```bash
# Check APIM logs
az monitor log-analytics query \
  --workspace log-claims-dev-uks-001 \
  --analytics-query "ApiManagementGatewayLogs | where ResponseCode == 502 | take 10"
```

### APIM returns 403 Forbidden

403 means APIM blocked the request — usually a policy or subscription key issue.

**Common causes:**
- Missing or invalid subscription key header
- CORS policy blocking the origin
- Custom policy blocking the request

**Quick test — bypass subscription key requirement:**
In the APIM portal, go to the API → Settings → Subscription required → uncheck. This removes the subscription key requirement for testing.

### Workload Identity: token exchange fails

**Symptom:** Pod logs show `CredentialUnavailableError` or `ClientAuthenticationError`.

**Diagnosis checklist:**
1. Is the pod label set? `azure.workload.identity/use: "true"`
2. Is the ServiceAccount annotation set? `azure.workload.identity/client-id: {client-id}`
3. Does the ServiceAccount name and namespace exactly match the federated credential subject?
4. Is the OIDC issuer URL in the federated credential exactly the AKS cluster's OIDC URL?

```bash
# Check OIDC issuer URL
az aks show \
  --resource-group rg-claims-dev-uks-001 \
  --name aks-claims-dev-uks \
  --query "oidcIssuerProfile.issuerUrl" -o tsv

# Check federated credential
az identity federated-credential list \
  --identity-name id-claims-api-dev \
  --resource-group rg-claims-dev-uks-001 \
  --query "[].{issuer:issuer, subject:subject}" -o table
```

The `issuer` in the federated credential must exactly match the OIDC issuer URL from AKS.

### Private endpoint: connection refused or wrong IP

**Symptom:** Calls to OpenAI fail with connection refused or return 403.

**Diagnosis:**
```bash
# From inside the pod, check DNS resolution
kubectl exec -n claims \
  $(kubectl get pod -n claims -l app=claims-api -o jsonpath='{.items[0].metadata.name}') \
  -- nslookup cog-claims-dev-0bd2.openai.azure.com

# The IP should be in 10.10.3.x range
# If it is a public IP (like 20.x.x.x), DNS is not using the private zone
```

If DNS returns a public IP, check:
1. Is the private DNS zone linked to the spoke VNet (not just the hub)?
2. Does the A record exist in the zone?
3. Is the pod using Azure's internal DNS (168.63.129.16)?

---

## Summary

| Concept | Your Platform | Key Point |
|---------|--------------|-----------|
| APIM | `apim-claims-dev-uks`, Internal VNet | No public IP — only reachable through App Gateway |
| APIM Policy | CORS on all operations | XML document running at inbound/outbound/error stages |
| UAMI | `id-claims-api-dev` | User-assigned — survives cluster recreation |
| Workload Identity | Pod label + SA annotation | Zero credentials — Kubernetes JWT exchanged for Azure AD token |
| Federated Credential | OIDC issuer + namespace + SA name | The trust link between Kubernetes and Azure AD |
| RBAC | 3 role assignments on specific resources | Least privilege — only what claims-api needs |
| Private Endpoint | NIC in pe subnet, 10.10.3.x | Traffic stays inside Azure's network |
| Private DNS Zone | `privatelink.openai.azure.com` etc. | Makes code resolve to private IP, not public |
| public_network_access | disabled on all PaaS | No internet path to the service exists |

---

## Documentation Reference

📖 [Azure API Management documentation hub](https://learn.microsoft.com/en-us/azure/api-management/)
📖 [APIM virtual network concepts](https://learn.microsoft.com/en-us/azure/api-management/virtual-network-concepts)
📖 [APIM with internal VNet and App Gateway](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-integrate-internal-vnet-appgateway)
📖 [APIM policies reference](https://learn.microsoft.com/en-us/azure/api-management/api-management-policies)
📖 [Microsoft Entra ID overview](https://learn.microsoft.com/en-us/entra/fundamentals/whatis)
📖 [Managed identities overview](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview)
📖 [Azure Workload Identity for AKS](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
📖 [Workload identity federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation)
📖 [Azure RBAC overview](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview)
📖 [Azure built-in roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles)
📖 [Azure Private Endpoint overview](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)
📖 [Private endpoint DNS configuration](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
📖 [Troubleshoot private endpoint connectivity](https://learn.microsoft.com/en-us/azure/private-link/troubleshoot-private-endpoint-connectivity)

---

## AZ-305 Exam Alignment

This module maps to two exam domains:

**Domain 1: Design Identity, Governance, and Monitoring (25-30%)**
- Design solutions for identity and access management
- Design solutions for securing applications

**Domain 4: Design Infrastructure Solutions (35-40%)**
- Design solutions for network connectivity and communication

📖 [AZ-305 exam skills outline](https://learn.microsoft.com/en-us/credentials/certifications/exams/az-305/)
📖 [Design identity solutions — study guide](https://learn.microsoft.com/en-us/azure/architecture/framework/security/design-identity)
📖 [Zero-trust security in Azure](https://learn.microsoft.com/en-us/azure/security/fundamentals/zero-trust)

---

*Next: Module 3 — Kubernetes and AKS*
