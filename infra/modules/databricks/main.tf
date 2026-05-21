# ============================================================
# Azure Databricks Workspace
# ============================================================
# Deployed with VNet injection so the cluster nodes run inside
# your private VNet — no public IPs on workers, traffic stays
# on the private network, can reach Data Lake and other services
# via private endpoints.
#
# VNet injection requires two dedicated subnets:
#   - public subnet:  Databricks control plane communication
#   - private subnet: cluster worker nodes
# Both subnets need their NSGs delegated to Databricks.
# ============================================================

resource "azurerm_databricks_workspace" "this" {
  name                        = "dbw-${var.name}"
  resource_group_name         = var.resource_group_name
  location                    = var.location
  sku                         = var.sku
  managed_resource_group_name = "rg-${var.name}-databricks-managed"

  custom_parameters {
    virtual_network_id                                   = var.virtual_network_id
    public_subnet_name                                   = var.public_subnet_name
    private_subnet_name                                  = var.private_subnet_name
    public_subnet_network_security_group_association_id  = var.public_subnet_nsg_id
    private_subnet_network_security_group_association_id = var.private_subnet_nsg_id
    no_public_ip                                         = true
  }

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "diag-${azurerm_databricks_workspace.this.name}"
  target_resource_id         = azurerm_databricks_workspace.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "accounts" }
  enabled_log { category = "clusters" }
  enabled_log { category = "jobs" }
  enabled_log { category = "notebook" }
}
