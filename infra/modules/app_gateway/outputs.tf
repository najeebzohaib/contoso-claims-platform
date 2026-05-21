output "id" {
  value = azurerm_application_gateway.this.id
}
output "name" {
  value = azurerm_application_gateway.this.name
}
output "public_ip" {
  value = azurerm_public_ip.appgw.ip_address
}
