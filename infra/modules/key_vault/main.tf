# ============================================================
# key_vault module
# ============================================================
# Creates a Key Vault with security best practices:
#   - RBAC authorization (NOT legacy access policies)
#   - Soft delete + configurable retention
#   - Optional purge protection
#   - Optional public access lockdown
#   - Network ACLs default to Deny
#   - Diagnostic logging to Log Analytics
# ============================================================

# Pull tenant ID from current Azure CLI context if not provided
data "azurerm_client_config" "current" {}

locals {
  effective_tenant_id = coalesce(var.tenant_id, data.azurerm_client_config.current.tenant_id)

  # Naming: kv-{name}-{suffix}, max 24 chars total
  vault_name = "kv-${var.name}-${var.name_suffix}"
}

resource "azurerm_key_vault" "this" {
  name                = local.vault_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = local.effective_tenant_id
  sku_name            = var.sku

  # ----- Authorization model -----
  # RBAC (Azure-wide roles) instead of legacy access policies
  rbac_authorization_enabled = true

  # ----- Data protection -----
  soft_delete_retention_days = var.soft_delete_retention_days
  purge_protection_enabled   = var.purge_protection_enabled

  # ----- Network access -----
  public_network_access_enabled = var.public_network_access_enabled

  network_acls {
    default_action             = var.network_acls_default_action
    bypass                     = var.network_acls_bypass
    ip_rules                   = var.network_acls_ip_rules
    virtual_network_subnet_ids = var.network_acls_subnet_ids
  }

  # ----- Other security defaults -----
  enabled_for_disk_encryption     = false
  enabled_for_deployment          = false
  enabled_for_template_deployment = false

  tags = var.tags

  lifecycle {
    # Tags often update from management group inheritance and other sources
    # We don't want every plan to show tag drift
    ignore_changes = [tags["DeployedAt"]]
  }
}

# ----- Diagnostic settings -----
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "diag-${local.vault_name}"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
