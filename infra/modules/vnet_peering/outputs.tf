output "a_to_b_id" {
  description = "Resource ID of the A→B peering"
  value       = azurerm_virtual_network_peering.a_to_b.id
}

output "b_to_a_id" {
  description = "Resource ID of the B→A peering"
  value       = azurerm_virtual_network_peering.b_to_a.id
}
