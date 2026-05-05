output "resource_group_name" {
  description = "Name of the dev resource group"
  value       = azurerm_resource_group.main.name
}

output "log_analytics_workspace_id" {
  description = "Full resource ID of Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "vnet_hub" {
  description = "Hub VNet details"
  value = {
    id            = module.vnet_hub.vnet_id
    name          = module.vnet_hub.vnet_name
    address_space = module.vnet_hub.vnet_address_space
    subnet_ids    = module.vnet_hub.subnet_ids
  }
}

output "vnet_dev" {
  description = "Dev spoke VNet details"
  value = {
    id            = module.vnet_dev.vnet_id
    name          = module.vnet_dev.vnet_name
    address_space = module.vnet_dev.vnet_address_space
    subnet_ids    = module.vnet_dev.subnet_ids
  }
}

output "tags" {
  description = "Common tags applied to all resources in this environment"
  value       = module.core.tags
}
