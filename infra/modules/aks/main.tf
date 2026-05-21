# ============================================================
# AKS Module
# ============================================================
# - Azure CNI Overlay (pods get their own CIDR, not VNet IPs)
# - Workload Identity + OIDC issuer enabled
# - System-assigned identity for the cluster itself
# - API server: public with authorized IP restriction
# ============================================================

resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "aks-${var.name}"
  kubernetes_version  = var.kubernetes_version

  # Workload Identity prerequisites
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name           = "system"
    node_count     = var.node_count
    vm_size        = var.node_vm_size
    vnet_subnet_id = var.aks_subnet_id
    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    # Pods get IPs from this CIDR (not from VNet)
    pod_cidr            = "192.168.0.0/16"
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
    load_balancer_sku   = "standard"
  }

  # Public API server with IP allowlist — pragmatic for learning.
  # ADR-002 documents this trade-off vs full private cluster.
  api_server_access_profile {
    authorized_ip_ranges = length(var.authorized_ip_ranges) > 0 ? var.authorized_ip_ranges : ["0.0.0.0/0"]
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  tags = var.tags
}

# Grant AKS pull access to ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}
