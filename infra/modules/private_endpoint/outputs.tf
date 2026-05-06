output "id" {
  description = "Resource ID of the private endpoint"
  value       = azurerm_private_endpoint.this.id
}

output "private_ip_address" {
  description = "Private IP allocated to the endpoint's NIC"
  value       = azurerm_private_endpoint.this.private_service_connection[0].private_ip_address
}

output "network_interface_id" {
  description = "Resource ID of the NIC the PE created"
  value       = azurerm_private_endpoint.this.network_interface[0].id
}
