# ============================================================
# vnet_peering module
# ============================================================
# A peering is bidirectional but configured as two separate
# resources (one per direction). Both must succeed for traffic
# to flow.
#
# Common patterns:
#   Hub→Spoke: allow_gateway_transit = true (if hub has gateway)
#              allow_forwarded_traffic = true
#   Spoke→Hub: use_remote_gateways = true (if hub has gateway)
#              allow_forwarded_traffic = true
# ============================================================

resource "azurerm_virtual_network_peering" "a_to_b" {
  name                      = "peer-${var.name}-a-to-b"
  resource_group_name       = var.vnet_a.resource_group_name
  virtual_network_name      = var.vnet_a.name
  remote_virtual_network_id = var.vnet_b.id

  allow_virtual_network_access = var.a_to_b.allow_virtual_network_access
  allow_forwarded_traffic      = var.a_to_b.allow_forwarded_traffic
  allow_gateway_transit        = var.a_to_b.allow_gateway_transit
  use_remote_gateways          = var.a_to_b.use_remote_gateways
}

resource "azurerm_virtual_network_peering" "b_to_a" {
  name                      = "peer-${var.name}-b-to-a"
  resource_group_name       = var.vnet_b.resource_group_name
  virtual_network_name      = var.vnet_b.name
  remote_virtual_network_id = var.vnet_a.id

  allow_virtual_network_access = var.b_to_a.allow_virtual_network_access
  allow_forwarded_traffic      = var.b_to_a.allow_forwarded_traffic
  allow_gateway_transit        = var.b_to_a.allow_gateway_transit
  use_remote_gateways          = var.b_to_a.use_remote_gateways
}
