# ============================================================
# vnet_peering module variables
# ============================================================
# Creates a single bidirectional peering between two VNets.
# Each peering side is configured independently.
# ============================================================

variable "name" {
  description = "Logical name for the peering pair (used in resource names)"
  type        = string
}

variable "vnet_a" {
  description = "First VNet in the peering pair"
  type = object({
    name                = string
    resource_group_name = string
    id                  = string
  })
}

variable "vnet_b" {
  description = "Second VNet in the peering pair"
  type = object({
    name                = string
    resource_group_name = string
    id                  = string
  })
}

variable "a_to_b" {
  description = "Settings for the A→B peering direction"
  type = object({
    allow_virtual_network_access = optional(bool, true)
    allow_forwarded_traffic      = optional(bool, false)
    allow_gateway_transit        = optional(bool, false)
    use_remote_gateways          = optional(bool, false)
  })
  default = {}
}

variable "b_to_a" {
  description = "Settings for the B→A peering direction"
  type = object({
    allow_virtual_network_access = optional(bool, true)
    allow_forwarded_traffic      = optional(bool, false)
    allow_gateway_transit        = optional(bool, false)
    use_remote_gateways          = optional(bool, false)
  })
  default = {}
}
