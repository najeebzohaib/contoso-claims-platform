output "zone_id" {
  description = "Resource ID of the Private DNS zone"
  value       = azurerm_private_dns_zone.this.id
}

output "zone_name" {
  description = "Name of the Private DNS zone"
  value       = azurerm_private_dns_zone.this.name
}
