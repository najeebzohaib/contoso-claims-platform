output "id"              { value = azurerm_firewall.this.id }
output "name"            { value = azurerm_firewall.this.name }
output "private_ip"      { value = azurerm_firewall.this.ip_configuration[0].private_ip_address }
output "public_ip"       { value = azurerm_public_ip.firewall.ip_address }
output "policy_id"       { value = azurerm_firewall_policy.this.id }
