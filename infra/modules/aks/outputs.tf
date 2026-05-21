output "id" {
  value = azurerm_kubernetes_cluster.this.id
}
output "name" {
  value = azurerm_kubernetes_cluster.this.name
}
output "kube_config" {
  value     = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive = true
}
output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.this.oidc_issuer_url
}
output "kubelet_identity_id" {
  value = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}
output "node_resource_group" {
  value = azurerm_kubernetes_cluster.this.node_resource_group
}
