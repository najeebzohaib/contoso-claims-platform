resource "azurerm_cognitive_account" "this" {
  name                          = "cog-${var.name}-${var.name_suffix}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  kind                          = var.kind
  sku_name                      = var.sku
  public_network_access_enabled = var.public_network_access_enabled
  custom_subdomain_name         = "cog-${var.name}-${var.name_suffix}"

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "diag-${azurerm_cognitive_account.this.name}"
  target_resource_id         = azurerm_cognitive_account.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "Audit" }
  enabled_metric { category = "AllMetrics" }
}
