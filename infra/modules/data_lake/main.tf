resource "azurerm_storage_account" "this" {
  name                     = "adls${var.name_prefix_compact}${var.name_suffix}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true

  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true

  tags = var.tags
}

resource "azurerm_storage_data_lake_gen2_filesystem" "this" {
  for_each           = toset(var.containers)
  name               = each.value
  storage_account_id = azurerm_storage_account.this.id
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "diag-${azurerm_storage_account.this.name}"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }
  enabled_metric { category = "Transaction" }
}
