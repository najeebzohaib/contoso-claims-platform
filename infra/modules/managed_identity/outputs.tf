output "id" {
  description = "Full resource ID of the managed identity"
  value       = azurerm_user_assigned_identity.this.id
}

output "name" {
  description = "Name of the managed identity"
  value       = azurerm_user_assigned_identity.this.name
}

output "principal_id" {
  description = "Object ID of the identity in Entra ID — use this for RBAC role assignments"
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "client_id" {
  description = "Application (client) ID — use this for OIDC federation and AKS Workload Identity"
  value       = azurerm_user_assigned_identity.this.client_id
}

output "tenant_id" {
  description = "Tenant ID where the identity lives"
  value       = azurerm_user_assigned_identity.this.tenant_id
}
