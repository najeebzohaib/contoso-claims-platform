output "id" {
  value = azurerm_api_management.this.id
}
output "name" {
  value = azurerm_api_management.this.name
}
output "gateway_url" {
  value = azurerm_api_management.this.gateway_url
}
output "portal_url" {
  value = azurerm_api_management.this.developer_portal_url
}
output "private_ip_addresses" {
  value = azurerm_api_management.this.private_ip_addresses
}
output "principal_id" {
  value = azurerm_api_management.this.identity[0].principal_id
}
