output "id" {
  value = azurerm_storage_account.this.id
}
output "name" {
  value = azurerm_storage_account.this.name
}
output "primary_dfs_endpoint" {
  value = azurerm_storage_account.this.primary_dfs_endpoint
}
output "container_names" {
  value = keys(azurerm_storage_data_lake_gen2_filesystem.this)
}
