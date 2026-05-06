# managed_identity module

Creates a User-Assigned Managed Identity (UAMI).

## Three identifiers and when to use them

A UAMI exposes three IDs. Knowing which to use matters for interviews:

| ID | Used for |
|----|----------|
| `principal_id` | RBAC role assignments (`azurerm_role_assignment.principal_id`) |
| `client_id` | OIDC federation, AKS Workload Identity annotations, app code (`DefaultAzureCredential` will pick this up via `AZURE_CLIENT_ID`) |
| `id` (resource ID) | Attaching the UAMI to compute (e.g. `identity_ids` on AKS, App Service) |

## When to use UAMI vs SAMI

| Choose UAMI when | Choose SAMI when |
|------------------|------------------|
| Multiple resources share the identity | One resource, one identity |
| Identity must survive compute recreation | Lifecycle tied to compute is fine |
| Using AKS Workload Identity | Simple App Service / Function |
| Federated credentials needed (GitHub OIDC) | No federation needed |

## Usage

```hcl
module "id_claims_api" {
  source = "../../modules/managed_identity"

  name                = "claims-api-dev"
  resource_group_name = azurerm_resource_group.main.name
  location            = "uksouth"
  tags                = module.core.tags
}

# Then assign roles:
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = module.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.id_claims_api.principal_id
}
```
