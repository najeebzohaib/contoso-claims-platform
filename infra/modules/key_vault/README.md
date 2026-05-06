# key_vault module

Creates a Key Vault with enterprise-grade defaults.

## Defaults to scrutinize

| Default | Production override |
|---------|---------------------|
| `rbac_authorization_enabled = true` | Keep (legacy access policies are deprecated) |
| `public_network_access_enabled = false` | Keep — pair with private endpoint |
| `network_acls_default_action = "Deny"` | Keep |
| `purge_protection_enabled = false` | **Set to `true`** for prod (irreversible) |
| `soft_delete_retention_days = 7` | **Increase to 90** for prod |
| `sku = "standard"` | `premium` only if HSM-backed keys are required |

## Why we use RBAC, not access policies

RBAC role assignments scope to Azure-wide roles (Reader, Contributor, custom).
Access policies are per-vault, per-permission, per-principal — they don't
compose well, can't be inherited, and aren't searchable in IAM blade.

Microsoft is moving toward RBAC for all resources. Most new tutorials and
official Microsoft samples now show RBAC. Access policies should be considered
legacy.

## Usage

```hcl
module "kv_dev" {
  source = "../../modules/key_vault"

  name                = "claims-dev"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  name_suffix         = "0bd2"  # global uniqueness suffix

  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Production overrides
  # purge_protection_enabled    = true
  # soft_delete_retention_days  = 90

  tags = module.core.tags
}
```
