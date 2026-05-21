locals {
  vnet_name             = "vnet-${var.name}"
  nsg_name_template     = "nsg-${var.name}-%s"
}

resource "azurerm_virtual_network" "this" {
  name                = local.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  dns_servers         = var.dns_servers
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                 = "snet-${var.name}-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.cidr]

  service_endpoints                 = each.value.service_endpoints
  private_endpoint_network_policies = each.value.private_endpoint_network_policies
  default_outbound_access_enabled   = each.value.default_outbound_access_enabled

  dynamic "delegation" {
    for_each = each.value.delegations
    content {
      name = "delegation-${delegation.value}"
      service_delegation {
        name = delegation.value
        actions = contains(
          ["Microsoft.Databricks/workspaces"],
          delegation.value
        ) ? [
          "Microsoft.Network/virtualNetworks/subnets/join/action",
          "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
          "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"
        ] : ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }
  }
}

resource "azurerm_network_security_group" "this" {
  for_each = var.subnets

  name                = format(local.nsg_name_template, each.key)
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = var.subnets

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

resource "azurerm_monitor_diagnostic_setting" "vnet" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "diag-${local.vnet_name}"
  target_resource_id         = azurerm_virtual_network.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_metric { category = "AllMetrics" }
}

resource "azurerm_monitor_diagnostic_setting" "nsg" {
  for_each = var.log_analytics_workspace_id != null ? var.subnets : {}

  name                       = "diag-${format(local.nsg_name_template, each.key)}"
  target_resource_id         = azurerm_network_security_group.this[each.key].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "NetworkSecurityGroupEvent" }
  enabled_log { category = "NetworkSecurityGroupRuleCounter" }
}
