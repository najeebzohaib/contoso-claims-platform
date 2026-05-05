# ============================================================
# Networking module variables
# ============================================================

variable "name" {
  description = "Name of the VNet (without 'vnet-' prefix; module adds it)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name))
    error_message = "Name must be 3-40 lowercase alphanumeric/hyphen characters."
  }
}

variable "resource_group_name" {
  description = "Resource group to deploy networking resources into"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "address_space" {
  description = "List of CIDR blocks for the VNet (typically a single /16)"
  type        = list(string)

  validation {
    condition     = length(var.address_space) >= 1
    error_message = "At least one address space CIDR is required."
  }
}

variable "subnets" {
  description = <<-DOC
    Map of subnets to create. Key is the subnet short name (becomes part of resource name).

    Each subnet object can include:
      - cidr                     : (required) CIDR block, must be within VNet address_space
      - service_endpoints        : list of service endpoints (e.g. ["Microsoft.KeyVault"])
      - delegations              : list of service delegations (e.g. for App Service plans)
      - private_endpoint_network_policies : "Enabled" or "Disabled" — Disabled is required to host PEs
      - default_outbound_access_enabled   : default is true; set false for stricter posture

    Example:
      subnets = {
        apps = { cidr = "10.10.1.0/24" }
        pe   = {
          cidr                              = "10.10.3.0/24"
          private_endpoint_network_policies = "Disabled"
        }
      }
  DOC
  type = map(object({
    cidr                              = string
    service_endpoints                 = optional(list(string), [])
    delegations                       = optional(list(string), [])
    private_endpoint_network_policies = optional(string, "Enabled")
    default_outbound_access_enabled   = optional(bool, true)
  }))
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostic settings (recommended)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "dns_servers" {
  description = "Optional custom DNS servers (otherwise Azure default 168.63.129.16 is used)"
  type        = list(string)
  default     = []
}
