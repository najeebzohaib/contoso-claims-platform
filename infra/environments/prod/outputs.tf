output "resource_group_name" {
  value = azurerm_resource_group.main.name
}
output "key_vault" {
  value = { id = module.kv_prod.id, name = module.kv_prod.name, uri = module.kv_prod.uri }
}
output "aks" {
  value = { id = module.aks_prod.id, name = module.aks_prod.name, oidc_issuer_url = module.aks_prod.oidc_issuer_url }
}
output "acr" {
  value = { name = module.acr_prod.name, login_server = module.acr_prod.login_server }
}
output "ai_services" {
  value = {
    openai_endpoint   = module.openai_prod.endpoint
    docintel_endpoint = module.docintel_prod.endpoint
    search_endpoint   = module.search_prod.endpoint
  }
}
output "data_platform" {
  value = {
    datalake_endpoint = module.datalake_prod.primary_dfs_endpoint
    databricks_url    = module.databricks_prod.workspace_url
  }
}
