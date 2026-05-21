resource "azurerm_search_service" "this" {
  name                          = "srch-${var.name}-${var.name_suffix}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.sku
  public_network_access_enabled = var.public_network_access_enabled

  local_authentication_enabled  = false

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "diag-${azurerm_search_service.this.name}"
  target_resource_id         = azurerm_search_service.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "OperationLogs" }
  enabled_metric { category = "AllMetrics" }
}
