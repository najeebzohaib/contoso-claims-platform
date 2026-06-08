# Module 6 — Terraform and Infrastructure as Code
## Based on the Contoso Claims Platform

**Time to complete:** 2-3 hours
**Builds on:** All previous modules (you need to understand what each resource does before understanding how it is declared)

---

## What You Will Understand After This Module

- What Infrastructure as Code is and why it matters
- How Terraform works — providers, resources, state, plan, apply
- How your 19 modules are structured and why
- What Terraform state is and why it is critical
- How variables, outputs, and locals work
- How your dev and prod environments share the same modules
- What happens during terraform plan and terraform apply
- How CI/CD integrates with Terraform via OIDC
- Common Terraform patterns used in your platform
- What goes wrong and how to fix it

---

## Part 1 — What Infrastructure as Code Is

Before IaC, infrastructure was created by:
- Clicking through web portals (Azure Portal)
- Running ad-hoc CLI commands
- Writing shell scripts

All three approaches have the same fundamental problem: **the infrastructure exists only in the cloud, not in code.** This means:

- You cannot reproduce it exactly — "I think I clicked the right settings"
- You cannot review changes — no git diff, no pull request
- You cannot roll back — what was the configuration last week?
- You cannot audit — who changed what and when?
- You cannot test — no way to validate before applying

Infrastructure as Code treats infrastructure configuration the same way as application code:
- Stored in git — full history of every change
- Reviewed via pull requests — changes require approval
- Tested before applying — terraform plan shows exactly what will change
- Reproducible — run the same code, get the same infrastructure
- Automated — no manual steps, no human error

**Your platform has ~4,000 lines of Terraform HCL** that define every Azure resource. If every Azure resource was deleted today, `terraform apply` would recreate the entire platform in ~20 minutes.

---

## Part 2 — How Terraform Works

Terraform operates in three phases:

### 1. Write

You write resource declarations in HCL (HashiCorp Configuration Language):

```hcl
resource "azurerm_resource_group" "main" {
  name     = "rg-claims-dev-uks-001"
  location = "uksouth"
  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

This declares: "I want a resource group with this name, location, and tags."

### 2. Plan

`terraform plan` compares the declared state (your HCL files) with the current real state (what actually exists in Azure) and shows the difference:

```
+ azurerm_resource_group.main will be created
  + name     = "rg-claims-dev-uks-001"
  + location = "uksouth"

~ azurerm_virtual_network.this will be updated in-place
  ~ tags = {
      + "NewTag" = "value"
        "Environment" = "dev"
    }

- azurerm_firewall.this will be destroyed
```

`+` = will be created
`~` = will be updated (in-place or by recreation)
`-` = will be destroyed

**Never apply without reading the plan.** A `-` next to a database or storage account means data loss.

### 3. Apply

`terraform apply` executes the plan — calls Azure APIs to create, update, or delete resources. It shows progress in real time and updates the state file when each resource is created.

📖 [Terraform overview](https://developer.hashicorp.com/terraform/intro)
📖 [Terraform workflow](https://developer.hashicorp.com/terraform/intro/core-workflow)
📖 [AzureRM Terraform provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

---

## Part 3 — Terraform State

This is the most important concept in Terraform to understand deeply.

### What state is

Terraform keeps a record of every resource it manages in a **state file** (`terraform.tfstate`). The state file maps your HCL resource declarations to real Azure resource IDs.

```json
{
  "resources": [
    {
      "type": "azurerm_virtual_network",
      "name": "this",
      "instances": [
        {
          "attributes": {
            "id": "/subscriptions/43fb1283.../resourceGroups/rg-claims-dev-uks-001/providers/Microsoft.Network/virtualNetworks/vnet-claims-dev-uks",
            "name": "vnet-claims-dev-uks",
            "address_space": ["10.10.0.0/16"],
            "location": "uksouth"
          }
        }
      ]
    }
  ]
}
```

Terraform uses the state to:
1. Know which real resources correspond to which HCL declarations
2. Detect drift — changes made outside Terraform
3. Determine what needs to change when you run `terraform plan`

### Remote state in your platform

Your state file is stored in Azure Blob Storage, not on your local machine:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-claims-tfstate"
    storage_account_name = "stclaimstfstate001"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
  }
}
```

**Why remote state?**

If the state file is on your laptop:
- A second developer cannot run Terraform (they do not have the state)
- If your laptop is lost, the state is lost
- Two developers running Terraform simultaneously could corrupt the state

Remote state in Azure Blob Storage solves this:
- Stored centrally — any machine can access it
- **Lease locking** — Azure Blob lease prevents two `terraform apply` runs simultaneously
- Versioned — Blob versioning preserves previous state versions for recovery

### State locking

When `terraform apply` starts, it acquires a lease on the state blob. Any other apply that tries to start sees the lock and refuses:

```
Error: Error acquiring the state lock

Lock Info:
  ID:        c3d4e5f6-...
  Path:      stclaimstfstate001/tfstate/dev.terraform.tfstate
  Operation: OperationTypeApply
  Who:       zohaib@Zohaib
  Created:   2026-05-28 14:23:11
```

If an apply crashes without releasing the lock, you can force-unlock it:
```bash
terraform force-unlock LOCK-ID
```

Use this carefully — only when you are certain no other apply is running.

### State drift

If someone creates a resource manually in the Azure Portal (not via Terraform), Terraform does not know about it. If someone deletes a Terraform-managed resource via the Portal, Terraform still has it in state but it no longer exists.

**Refresh state to detect drift:**
```bash
terraform refresh
# Updates state to match actual Azure resources
# Shows what changed outside Terraform
```

**Import a manually created resource:**
```bash
terraform import azurerm_resource_group.main \
  /subscriptions/43fb1283.../resourceGroups/rg-claims-dev-uks-001
# Adds the real resource to Terraform state without recreating it
```

**Remove a resource from state (without deleting it):**
```bash
terraform state rm azurerm_firewall.this
# Removes from state but leaves the resource in Azure
# Used when you deleted the Firewall manually and want Terraform to stop managing it
```

This is exactly what you did during the Firewall cleanup.

📖 [Terraform state](https://developer.hashicorp.com/terraform/language/state)
📖 [Remote state with Azure Blob Storage](https://developer.hashicorp.com/terraform/language/settings/backends/azurerm)
📖 [State locking](https://developer.hashicorp.com/terraform/language/state/locking)
📖 [terraform state commands](https://developer.hashicorp.com/terraform/cli/commands/state)

---

## Part 4 — Providers

A provider is a Terraform plugin that knows how to interact with a specific API. Your platform uses:

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"     # any 3.x version >= 3.116
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.53"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
```

**azurerm** — manages Azure Resource Manager resources (VNets, VMs, AKS, storage, etc.)

**azuread** — manages Azure Active Directory resources (users, groups, service principals, federated identity credentials). Separate from azurerm because it uses a different API.

**kubernetes** — manages Kubernetes resources (deployments, services, namespaces). Used to create the `claims` namespace and apply the workload identity ServiceAccount.

**Version constraints:**

`~> 3.116` means "any version >=3.116 and <4.0". This allows patch and minor updates but not major version upgrades (which may have breaking changes).

Always pin provider versions in production. Without a pin, `terraform init` might download a new major version that breaks your configuration.

📖 [Terraform providers](https://developer.hashicorp.com/terraform/language/providers)
📖 [AzureRM provider documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
📖 [Provider version constraints](https://developer.hashicorp.com/terraform/language/expressions/version-constraints)

---

## Part 5 — Resources, Variables, Outputs, Locals

### Resources

A resource block declares one Azure resource:

```hcl
resource "azurerm_virtual_network" "this" {  # type = "azurerm_virtual_network", name = "this"
  name                = "vnet-${var.name}"   # interpolation using a variable
  address_space       = [var.address_space]
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}
```

The resource type (`azurerm_virtual_network`) maps exactly to an Azure resource type. Every argument maps to a property in the Azure API. The Terraform documentation shows every available argument.

### Variables

Variables are inputs to your modules — they parameterise the configuration:

```hcl
# Variable declaration (in variables.tf)
variable "address_space" {
  type        = string
  description = "The CIDR range for this VNet"
  default     = "10.0.0.0/16"
}

variable "subnets" {
  type = map(object({
    cidr             = string
    service_endpoints = optional(list(string), [])
  }))
  description = "Map of subnet names to their configurations"
}
```

Variables are set by the calling module:

```hcl
# In environments/dev/main.tf
module "networking_dev" {
  source        = "../../modules/networking"
  address_space = "10.10.0.0/16"    # dev spoke range
  subnets = {
    appgw = { cidr = "10.10.4.0/24" }
    apim  = { cidr = "10.10.5.0/24" }
    aks   = { cidr = "10.10.16.0/20" }
    pe    = { cidr = "10.10.3.0/24" }
  }
}
```

### Outputs

Outputs expose values from a module for use by other modules:

```hcl
# In modules/networking/outputs.tf
output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "subnet_ids" {
  value = { for k, v in azurerm_subnet.this : k => v.id }
}
```

The AKS module needs the subnet ID for the node pool. It gets it from the networking module output:

```hcl
module "aks_dev" {
  source         = "../../modules/aks"
  aks_subnet_id  = module.networking_dev.subnet_ids["aks"]  # output from networking module
}
```

### Locals

Locals are computed values within a module — like variables but derived from other values:

```hcl
locals {
  name_prefix = "claims-${var.environment}-${var.region_short}"
  # e.g. "claims-dev-uks"
  
  common_tags = {
    Environment        = var.environment
    ManagedBy          = "Terraform"
    CostCenter         = var.cost_center
    DataClassification = "internal"
    Maintainer         = var.maintainer_email
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}-001"
  location = var.location
  tags     = local.common_tags
}
```

Using locals for naming and tags ensures consistency — every resource gets the same naming convention and the same set of tags.

📖 [Terraform resources](https://developer.hashicorp.com/terraform/language/resources)
📖 [Terraform variables](https://developer.hashicorp.com/terraform/language/values/variables)
📖 [Terraform outputs](https://developer.hashicorp.com/terraform/language/values/outputs)
📖 [Terraform locals](https://developer.hashicorp.com/terraform/language/values/locals)

---

## Part 6 — Your Module Structure

Your platform has 19 modules. Each module encapsulates one concern:

```
infra/
  modules/
    core/              → naming conventions and tagging
    networking/        → VNet, subnets, NSGs, peering, DNS
    firewall/          → Azure Firewall Premium + policy + rules
    app_gateway/       → Application Gateway v2 + WAF policy
    apim/              → API Management Internal VNet
    aks/               → AKS cluster + node pool
    acr/               → Azure Container Registry Premium
    key_vault/         → Key Vault RBAC mode
    managed_identity/  → User Assigned Managed Identity + federated credential
    private_endpoint/  → Private endpoint + DNS zone + VNet link
    private_dns/       → Private DNS zone (standalone)
    ai_services/       → Azure OpenAI + Document Intelligence
    ai_search/         → Azure AI Search
    data_lake/         → ADLS Gen2 + containers (bronze/silver/gold)
    databricks/        → Databricks Premium workspace + VNet injection
    bastion/           → Azure Bastion Standard
    sentinel/          → Microsoft Sentinel onboarding
    static_web_app/    → Azure Static Web Apps
    app_insights/      → Application Insights
  environments/
    dev/
      main.tf          → calls all modules with dev-specific values
      variables.tf
      outputs.tf
      terraform.tfvars → actual values (gitignored)
      backend.config   → state storage config (gitignored)
    prod/
      main.tf          → calls all modules with prod-specific values
```

### Why modules?

**Reusability** — `module "networking_dev"` and `module "networking_prod"` both use `modules/networking` with different `address_space` values. One module, two environments.

**Encapsulation** — the AKS module does not need to know how the VNet was created. It just needs a subnet ID. The interface (inputs/outputs) is clean and stable.

**Testability** — you can test a module in isolation without deploying the entire platform.

**Consistency** — both environments get the same resource configuration. The only differences are in variable values.

### The core module

The `core` module is special — it generates naming conventions and tags:

```hcl
module "core" {
  source = "../../modules/core"

  project     = "claims"
  environment = "dev"
  location    = "uksouth"
  cost_center = "learning"
  maintainer  = "zohaib.najeeb@gmail.com"
}

# Every other module uses core outputs:
module "networking_dev" {
  source      = "../../modules/networking"
  name        = module.core.name_prefix      # "claims-dev-uks"
  tags        = module.core.tags             # standard tag set
  location    = module.core.location
  region_short = module.core.region_short    # "uks"
}
```

This ensures every resource in the platform has consistent naming (`vnet-claims-dev-uks`, `aks-claims-dev-uks`, `apim-claims-dev-uks`) and the same tags for cost management and governance.

📖 [Terraform modules](https://developer.hashicorp.com/terraform/language/modules)
📖 [Module composition](https://developer.hashicorp.com/terraform/language/modules/develop/composition)
📖 [Module best practices](https://developer.hashicorp.com/terraform/language/modules/develop/best-practices)

---

## Part 7 — Key Terraform Patterns in Your Platform

### for_each — creating multiple resources from a map

Used extensively in your networking module to create subnets:

```hcl
resource "azurerm_subnet" "this" {
  for_each             = var.subnets
  name                 = "snet-${var.name}-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.cidr]
}
```

`for_each` creates one resource instance per map entry. `each.key` is the map key (`"appgw"`, `"apim"`, `"aks"`). `each.value` is the object associated with that key (`{ cidr = "10.10.4.0/24" }`).

The Terraform state stores each instance as `azurerm_subnet.this["appgw"]`, `azurerm_subnet.this["apim"]`, etc. If you add a new subnet to the map, Terraform creates only that new subnet without touching the existing ones.

### count — conditional resources

```hcl
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.log_analytics_workspace_id != null ? 1 : 0
  # Create this resource only if a Log Analytics workspace ID was provided
  # If null: count=0, resource not created
  # If set: count=1, resource created
  
  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_virtual_network.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id
}
```

The ternary `condition ? true_value : false_value` is a common pattern for optional resources. If you do not provide a Log Analytics workspace ID, the diagnostic setting is not created but the module still works.

### depends_on — explicit dependencies

Terraform automatically infers dependencies from references. If resource B references `resource_a.this.id`, Terraform knows A must be created before B.

Sometimes the dependency is not expressed through a reference:

```hcl
resource "azurerm_role_assignment" "aks_network" {
  scope                = azurerm_virtual_network.this.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.this.identity[0].principal_id

  # AKS needs this role before it can create the internal load balancer
  # Terraform cannot infer this dependency from the resource references
  depends_on = [azurerm_kubernetes_cluster.this]
}
```

### dynamic blocks — conditional sub-blocks

```hcl
resource "azurerm_network_security_group" "this" {
  name                = "nsg-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location

  dynamic "security_rule" {
    for_each = var.security_rules   # iterate over a list of rule objects
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      destination_port_range     = security_rule.value.port
      source_address_prefix      = security_rule.value.source
      destination_address_prefix = "*"
    }
  }
}
```

`dynamic` blocks generate repeated sub-blocks from a collection. Without `dynamic`, you would need to hardcode every security rule individually.

📖 [for_each meta-argument](https://developer.hashicorp.com/terraform/language/meta-arguments/for_each)
📖 [count meta-argument](https://developer.hashicorp.com/terraform/language/meta-arguments/count)
📖 [depends_on meta-argument](https://developer.hashicorp.com/terraform/language/meta-arguments/depends_on)
📖 [dynamic blocks](https://developer.hashicorp.com/terraform/language/expressions/dynamic-blocks)

---

## Part 8 — The Dev and Prod Environments

Your two environments share the same 19 modules but have different configurations:

```hcl
# environments/dev/main.tf
module "networking_dev" {
  source        = "../../modules/networking"
  name          = "claims-dev-uks"
  address_space = "10.10.0.0/16"    # dev spoke
  subnets = {
    aks = { cidr = "10.10.16.0/20" }
    # ...
  }
}

# environments/prod/main.tf
module "networking_prod" {
  source        = "../../modules/networking"
  name          = "claims-prod-uks"
  address_space = "10.30.0.0/16"    # prod spoke — different range
  subnets = {
    aks = { cidr = "10.30.16.0/20" }
    # ...
  }
}
```

**Key differences between dev and prod:**

| Setting | Dev | Prod |
|---------|-----|------|
| AKS node count | 2 | 3+ |
| AKS SKU | Free tier | Standard tier |
| APIM SKU | Developer_1 | Standard_1 |
| VNet range | 10.10.0.0/16 | 10.30.0.0/16 |
| Spoke hub peering | 10.10↔10.0 | 10.30↔10.0 |
| State file | dev.terraform.tfstate | prod.terraform.tfstate |
| Service principal | sp-claims-ci/cd-dev | sp-claims-ci/cd-prod |

Both environments use the same module code. A bug fixed in a module benefits both environments.

### Separate state files

Dev and prod have separate state files:
```
stclaimstfstate001/tfstate/dev.terraform.tfstate
stclaimstfstate001/tfstate/prod.terraform.tfstate
```

Running `terraform destroy` in the dev environment cannot affect the prod state. They are completely independent.

---

## Part 9 — CI/CD with GitHub Actions and OIDC

Your CI/CD pipeline automates Terraform workflows. No one manually runs `terraform apply` in production.

### OIDC authentication

In Module 2b you learned how Workload Identity works in AKS. Your CI/CD uses the same concept for GitHub Actions:

```
GitHub Actions workflow runs
  → GitHub issues a signed JWT token
  → Terraform uses the JWT to request an Azure AD access token
  → Azure AD validates the JWT (checks GitHub's OIDC issuer)
  → Azure AD issues access token for the service principal
  → Terraform uses the access token to call Azure APIs
```

No stored client secrets in GitHub. The JWT is short-lived and scoped to the specific repository and branch.

### Two service principals, two roles

```
sp-claims-ci-dev  → Reader role
  Used by: terraform-plan workflow (runs on every PR)
  Can: read any resource, run terraform plan
  Cannot: create, modify, or delete anything

sp-claims-cd-dev  → Contributor + User Access Administrator
  Used by: terraform-apply workflow (runs on merge to main)
  Can: create, modify, delete resources
  Can: manage RBAC assignments (needed for role_assignment resources)
```

The split is a security control. PR workflows run on code submitted by anyone (including forks). If a malicious PR could deploy infrastructure, that would be a serious vulnerability. With Reader-only permissions, the worst a malicious plan can do is read existing resources.

### The workflow files

```yaml
# .github/workflows/terraform-plan.yml
name: Terraform Plan

on:
  pull_request:
    paths:
      - 'infra/**'    # only trigger on infra changes

jobs:
  plan:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # required for OIDC token
      contents: read
      pull-requests: write  # to post plan as PR comment

    steps:
      - uses: actions/checkout@v4

      - name: Azure login (CI — read only)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID_CI }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Terraform init
        run: terraform init -backend-config=backend.config
        working-directory: infra/environments/dev

      - name: Terraform plan
        run: terraform plan -out=tfplan
        working-directory: infra/environments/dev

      - name: Post plan to PR
        # Posts the plan output as a comment on the pull request
```

```yaml
# .github/workflows/terraform-apply.yml
name: Terraform Apply

on:
  push:
    branches: [main]    # only on merge to main
    paths:
      - 'infra/**'

  workflow_dispatch:    # allows manual trigger

jobs:
  apply:
    runs-on: ubuntu-latest
    environment: dev-apply    # requires manual approval in GitHub

    steps:
      - name: Azure login (CD — contributor)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID_CD }}
          # ...

      - name: Terraform apply
        run: terraform apply -auto-approve
```

`environment: dev-apply` — this is a GitHub Environment with a required reviewer configured. The apply workflow pauses and waits for a human to approve it before proceeding. This is the manual gate that prevents automated but unreviewed deployments.

📖 [GitHub Actions OIDC with Azure](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-oidc)
📖 [Terraform GitHub Actions](https://developer.hashicorp.com/terraform/tutorials/automation/github-actions)
📖 [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)

---

## Part 10 — Architecture Decision Records

Your platform includes 5 ADRs in `docs/architecture/adr/`. An ADR documents a significant architectural decision — what was decided, why, and what alternatives were considered.

ADRs are valuable because:
- New team members understand why the platform is built the way it is
- You avoid re-litigating the same decisions every few months
- When requirements change, you revisit the ADR with full context

### Your ADRs

**ADR-001: Bootstrap storage has purge protection disabled**

Decision: The Terraform state storage account has `blob_soft_delete_retention_days = 0` and `purge_protection_enabled = false`.

Why: Terraform cannot manage a resource that is protected from deletion. If the state storage account itself has deletion protection enabled via Terraform, you create a catch-22: you cannot delete the protection because the resource is protected, but Terraform wants to manage the protection.

Alternative considered: Enable purge protection and manage it outside Terraform. Rejected — too many things managed outside Terraform.

**ADR-002: AKS API server uses public endpoint with IP allowlist**

Decision: AKS API server is publicly accessible but restricted to specific IP ranges.

Why: Private AKS cluster requires a private DNS zone and VPN or Bastion to access the API server from outside the VNet. This adds significant complexity and cost for a learning environment.

Alternative considered: Private cluster with Bastion for access. Deferred — acceptable for production, over-engineered for learning.

**ADR-003: APIM uses Internal VNet mode behind App Gateway**

Decision: APIM is deployed in Internal mode and can only be reached through App Gateway.

Why: External APIM has a public IP that bypasses WAF. Internal mode ensures all traffic passes through WAF inspection.

Lesson learned: Internal APIM requires NSG rules for port 3443 from ApiManagement service tag and port 6390 from AzureLoadBalancer. Missing these causes a 422 error during provisioning with no clear error message.

**ADR-004: AzureFirewallSubnet must be a standalone resource**

Decision: The Firewall and Bastion subnets are created as standalone `azurerm_subnet` resources, not managed by the networking module's `for_each` loop.

Why: Azure Firewall requires the subnet to be named exactly `AzureFirewallSubnet` with no prefix or suffix. The networking module applies a naming prefix to all subnets it creates (`snet-claims-dev-uks-{key}`). Applying this prefix to the Firewall subnet causes provisioning to fail.

**ADR-005: Workload Identity preferred over stored credentials**

Decision: All Azure service authentication uses Workload Identity. No API keys or client secrets stored anywhere.

Why: Stored credentials create operational burden (rotation schedules, secret scanning, accidental commits) and security risk. Workload Identity eliminates the credential entirely.

📖 [Architecture Decision Records](https://adr.github.io/)
📖 [ADR template](https://github.com/joelparkerhenderson/architecture-decision-record)

---

## Part 11 — Common Terraform Problems and Solutions

These are the real problems you encountered building this platform.

### Problem: terraform plan shows unexpected destroy

```
- azurerm_subnet.this["appgw"] will be destroyed
```

**Why this happens:** Changing a `for_each` key renames the resource in state. If you renamed the subnet from `"appgw"` to `"app-gateway"`, Terraform sees the old key deleted and a new key added — a destroy and create pair.

**Fix:** Use `terraform state mv` to rename the resource in state before applying:
```bash
terraform state mv \
  'azurerm_subnet.this["appgw"]' \
  'azurerm_subnet.this["app-gateway"]'
```

Now Terraform sees a rename in state and does not destroy anything.

### Problem: Resource stuck in Creating/Updating state

**Why this happens:** Azure operations are asynchronous. Terraform polls until the operation completes. If Azure takes longer than usual (APIM takes 45 minutes to deploy), Terraform may time out.

**Fix:** Run `terraform apply` again — it picks up from the current state and retries incomplete operations.

### Problem: Error acquiring state lock

```
Error: Error acquiring the state lock
Lock Info: Who: zohaib@Zohaib
```

**Why this happens:** A previous apply did not complete cleanly and left the lock file in the blob.

**Fix:**
```bash
terraform force-unlock LOCK-ID
```

Only do this when you are certain no other apply is running.

### Problem: AKS nodes stuck in Pending after start

**Why this happens:** AKS was stopped and restarted. Nodes are Starting but kubectl reports no nodes.

**Fix:**
```bash
# Refresh credentials
az aks get-credentials \
  --resource-group rg-claims-dev-uks-001 \
  --name aks-claims-dev-uks \
  --overwrite-existing

# Wait for nodes (takes 3-5 minutes)
kubectl get nodes --watch
```

### Problem: Firewall-related errors after deleting Firewall manually

**Why this happens:** The UDR still points to the Firewall's private IP. The Firewall policy resource still exists in state.

**Fix:**
```bash
# Remove deleted resources from state
terraform state rm module.firewall_hub.azurerm_firewall.this
terraform state rm azurerm_route_table.dev_to_firewall

# Comment out the Firewall and UDR from main.tf
# Then plan and apply to remove remaining references
terraform plan
terraform apply
```

You went through exactly this process in your session.

### Problem: GitHub push rejected — secret scanning

```
remote: - Push cannot contain secrets
remote: Azure Storage Account Access Key
```

**Why this happens:** A storage account key was hardcoded in a notebook file.

**Fix:**
```python
# Replace actual key with placeholder
spark.conf.set(
    "fs.azure.account.key.adlsclaimsdev0bd2.dfs.core.windows.net",
    "<STORAGE_KEY_FROM_KEYVAULT>"  # placeholder
)
```

Then amend the commit to rewrite history:
```bash
git add .
git commit --amend --no-edit
git push --force-with-lease
```

📖 [Terraform troubleshooting](https://developer.hashicorp.com/terraform/internals/debugging)
📖 [terraform state commands](https://developer.hashicorp.com/terraform/cli/commands/state)

---

## Part 12 — Reading Your Terraform Code

Open `infra/environments/dev/main.tf`. Here is how to read it.

### The top-level structure

```hcl
# 1. Terraform settings block — providers and backend
terraform {
  required_providers { ... }
  backend "azurerm" { ... }
}

# 2. Provider configuration
provider "azurerm" { ... }

# 3. Core module — naming and tagging
module "core" { ... }

# 4. Resource groups
resource "azurerm_resource_group" "main" { ... }
resource "azurerm_resource_group" "hub" { ... }

# 5. Networking — hub and spoke
module "networking_hub" { ... }
module "networking_dev" { ... }
module "vnet_peering" { ... }

# 6. Security
module "firewall_hub" { ... }      # commented out — deleted
module "bastion_hub" { ... }
module "appgw_dev" { ... }
module "apim_dev" { ... }

# 7. Compute
module "acr_dev" { ... }
module "aks_dev" { ... }

# 8. AI services
module "ai_services_dev" { ... }
module "ai_search_dev" { ... }

# 9. Data
module "data_lake_dev" { ... }
module "databricks_dev" { ... }

# 10. Identity
module "claims_api_identity" { ... }   # UAMI + federated credential

# 11. Private endpoints
module "pe_openai_dev" { ... }
module "pe_keyvault_dev" { ... }
# ... etc

# 12. Observability
module "app_insights_dev" { ... }
module "sentinel_dev" { ... }
```

The order matters for readability but Terraform handles actual dependencies automatically through the dependency graph.

### Following a dependency chain

Start with any resource and trace its dependencies:

```
AKS cluster needs:
  → aks_subnet_id  (from module.networking_dev.subnet_ids["aks"])
  → acr_id         (from module.acr_dev.id)
  → log_analytics_workspace_id (from azurerm_log_analytics_workspace.main.id)

Networking module needs:
  → resource_group_name (from azurerm_resource_group.main.name)
  → hub_vnet_id         (from module.networking_hub.vnet_id)
```

You can visualise this graph:
```bash
cd infra/environments/dev
terraform graph | dot -Tsvg > graph.svg
```

This creates an SVG of the full dependency graph — every resource and its dependencies.

📖 [Terraform dependency graph](https://developer.hashicorp.com/terraform/cli/commands/graph)
📖 [Terraform configuration language](https://developer.hashicorp.com/terraform/language)

---

## Summary

| Concept | Your Platform | Key Point |
|---------|--------------|-----------|
| State file | Azure Blob, dev.terraform.tfstate | Maps HCL declarations to real Azure resource IDs |
| Remote state | stclaimstfstate001 | Enables team collaboration, prevents concurrent applies |
| State locking | Azure Blob lease | Prevents two applies running simultaneously |
| Providers | azurerm 3.116, azuread, kubernetes | Plugins that know how to call Azure APIs |
| Modules | 19 modules | Reusable, encapsulated, testable units |
| for_each | Subnets, private endpoints | Creates N resources from a map |
| count | Diagnostic settings | Conditional resource creation |
| Core module | Naming + tagging | Consistent names and tags across all resources |
| Two environments | dev (10.10) + prod (10.30) | Same modules, different variable values |
| Two SPs | CI (Reader) + CD (Contributor) | Least privilege — PR workflows cannot deploy |
| OIDC | GitHub Actions → Azure AD | No stored secrets in GitHub |
| ADRs | ADR-001 to ADR-005 | Documented decisions with rationale |

---

## Documentation Reference

📖 [Terraform documentation hub](https://developer.hashicorp.com/terraform)
📖 [Terraform language reference](https://developer.hashicorp.com/terraform/language)
📖 [Terraform CLI reference](https://developer.hashicorp.com/terraform/cli)
📖 [AzureRM provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
📖 [Terraform state](https://developer.hashicorp.com/terraform/language/state)
📖 [Remote state with Azure](https://developer.hashicorp.com/terraform/language/settings/backends/azurerm)
📖 [Terraform modules](https://developer.hashicorp.com/terraform/language/modules)
📖 [for_each](https://developer.hashicorp.com/terraform/language/meta-arguments/for_each)
📖 [count](https://developer.hashicorp.com/terraform/language/meta-arguments/count)
📖 [dynamic blocks](https://developer.hashicorp.com/terraform/language/expressions/dynamic-blocks)
📖 [GitHub Actions OIDC with Azure](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-oidc)
📖 [Terraform GitHub Actions tutorial](https://developer.hashicorp.com/terraform/tutorials/automation/github-actions)
📖 [Architecture Decision Records](https://adr.github.io/)

---

## AZ-305 Exam Alignment

**Domain 1: Design Identity, Governance, and Monitoring (25-30%)**
- Design governance solutions (tagging, naming, policy)

**Domain 4: Design Infrastructure Solutions (35-40%)**
- Design infrastructure provisioning solutions

📖 [AZ-305 exam skills outline](https://learn.microsoft.com/en-us/credentials/certifications/exams/az-305/)
📖 [Azure landing zones — IaC patterns](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/implementation-options)
📖 [Azure naming conventions](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming)
📖 [Azure tagging strategy](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging)

---

## What Next

You now have six modules covering every component of the platform:

| Module | Topic |
|--------|-------|
| 1 | Azure Networking — VNets, subnets, NSGs, UDRs, DNS |
| 2a | Firewall and WAF |
| 2b | APIM, Workload Identity, Private Endpoints |
| 3 | Kubernetes and AKS |
| 4 | Azure AI Services |
| 5 | Databricks and Data Engineering |
| 6 | Terraform and Infrastructure as Code |

**Suggested next steps:**

1. **Re-read the modules** on your weakest areas with the Azure Portal open — find each resource described and look at its configuration

2. **Do the kubectl exercises from Module 3** — connect to the cluster and run the commands

3. **Read your actual Terraform code** — open `infra/environments/dev/main.tf` and trace the dependency chain for any one resource

4. **Start AZ-305 exam prep** — John Savill's AZ-305 study cram on YouTube is the best free resource. Use your platform as a reference as you study each topic.

5. **When ready: Delta Live Tables** — the next Databricks feature worth building. It adds data quality expectations and lineage tracking on top of the medallion architecture.
