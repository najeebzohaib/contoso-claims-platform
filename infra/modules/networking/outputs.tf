output "vnet_id" {
  description = "Full resource ID of the VNet"
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the VNet"
  value       = azurerm_virtual_network.this.name
}

output "vnet_address_space" {
  description = "Address space of the VNet"
  value       = azurerm_virtual_network.this.address_space
}

output "subnet_ids" {
  description = "Map of subnet name to subnet ID"
  value       = { for k, s in azurerm_subnet.this : k => s.id }
}

output "subnet_cidrs" {
  description = "Map of subnet name to CIDR"
  value       = { for k, s in azurerm_subnet.this : k => s.address_prefixes[0] }
}

output "nsg_ids" {
  description = "Map of subnet name to NSG ID"
  value       = { for k, n in azurerm_network_security_group.this : k => n.id }
}
