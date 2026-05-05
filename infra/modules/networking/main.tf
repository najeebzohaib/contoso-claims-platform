# ============================================================
# Networking Module
# ============================================================
# Creates a VNet with subnets, NSGs, and diagnostic settings.
# Designed to be invoked once per VNet (hub or spoke).
# Peerings are handled by a separate module.
# ============================================================

# ------------------------------------------------------------
# Locals
# ------------------------------------------------------------

locals {
  vnet_name         = "vnet-${var.name}"
  nsg_name_template = "nsg-${var.name}-%s" # %s replaced by subnet key
}

# ------------------------------------------------------------
# Virtual Network
# ------------------------------------------------------------

resource "azurerm_virtual_network" "this" {
  name                = local.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  dns_servers         = var.dns_servers

  tags = var.tags
}

# ------------------------------------------------------------
# Subnets
# ------------------------------------------------------------
# We use for_each over the subnets map. This is preferable to
# count + list because:
#   - Adding/removing a subnet doesn't shift indices
#   - Resource addresses are stable (azurerm_subnet.this["apps"])
#   - Plan output is more readable
# ------------------------------------------------------------

resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                 = "snet-${var.name}-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.cidr]

  service_endpoints = each.value.service_endpoints

  # Whether private endpoints can attach without policy interference.
  # Set to "Disabled" for the dedicated PE subnet.
  private_endpoint_network_policies = each.value.private_endpoint_network_policies

  # Default outbound NAT for VMs. Microsoft is deprecating implicit
  # outbound; explicit is the future direction. We expose this as a flag
  # so security-strict workloads can disable it and force explicit egress.
  default_outbound_access_enabled = each.value.default_outbound_access_enabled

  # Service delegations (e.g. for App Service VNet integration, ACI, AKS in some modes)
  dynamic "delegation" {
    for_each = each.value.delegations
    content {
      name = "delegation-${delegation.value}"
      service_delegation {
        name    = delegation.value
        actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }
  }
}

# ------------------------------------------------------------
# Network Security Groups (one per subnet)
# ------------------------------------------------------------
# We always create an NSG per subnet, even with no custom rules.
# This guarantees:
#   1. Azure Policy "every subnet has NSG" is satisfied
#   2. Default deny-all-from-internet rule is in effect
#   3. Adding a rule later is a same-resource update
# ------------------------------------------------------------

resource "azurerm_network_security_group" "this" {
  for_each = var.subnets

  name                = format(local.nsg_name_template, each.key)
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Associate each NSG to its subnet
resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = var.subnets

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

# ------------------------------------------------------------
# Diagnostic Settings
# ------------------------------------------------------------
# Send VNet flow logs and NSG events to Log Analytics for visibility.
# Critical for any production-grade environment; we make it optional
# by checking if log_analytics_workspace_id was provided.
# ------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "vnet" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "diag-${local.vnet_name}"
  target_resource_id         = azurerm_virtual_network.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "nsg" {
  for_each = var.log_analytics_workspace_id != null ? var.subnets : {}

  name                       = "diag-${format(local.nsg_name_template, each.key)}"
  target_resource_id         = azurerm_network_security_group.this[each.key].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "NetworkSecurityGroupEvent"
  }

  enabled_log {
    category = "NetworkSecurityGroupRuleCounter"
  }
}
