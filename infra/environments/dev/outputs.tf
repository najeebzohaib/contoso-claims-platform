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

output "key_vault" {
  description = "Dev Key Vault details"
  value = {
    id   = module.kv_dev.id
    name = module.kv_dev.name
    uri  = module.kv_dev.uri
  }
}

output "claims_api_identity" {
  description = "UAMI for the claims API"
  value = {
    id           = module.id_claims_api.id
    principal_id = module.id_claims_api.principal_id
    client_id    = module.id_claims_api.client_id
  }
}

output "kv_private_endpoint_ip" {
  description = "Private IP of the Key Vault private endpoint"
  value       = module.pe_kv_dev.private_ip_address
}

output "aks" {
  description = "AKS cluster details"
  value = {
    id              = module.aks_dev.id
    name            = module.aks_dev.name
    oidc_issuer_url = module.aks_dev.oidc_issuer_url
    node_rg         = module.aks_dev.node_resource_group
  }
}

output "acr" {
  description = "ACR details"
  value = {
    id           = module.acr_dev.id
    name         = module.acr_dev.name
    login_server = module.acr_dev.login_server
  }
}
