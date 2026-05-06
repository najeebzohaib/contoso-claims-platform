# ============================================================
# private_dns module
# ============================================================
# Note: Private DNS zones are GLOBAL resources (not regional).
# Linking a zone to a VNet is a per-VNet operation.
#
# `registration_enabled` should be FALSE for privatelink.* zones.
# (true is for VM auto-registration scenarios — wrong fit here)
# ============================================================

resource "azurerm_private_dns_zone" "this" {
  name                = var.zone_name
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = var.vnet_links

  name                  = "link-${each.key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = each.value.vnet_id
  registration_enabled  = each.value.registration_enabled

  tags = var.tags
}
