variable "name" {
  description = "Logical name (becomes 'kv-{name}-{suffix}'). Max 24 chars total."
  type        = string

  validation {
    condition     = length(var.name) <= 16
    error_message = "Name must be <=16 chars (Key Vault names max 24 chars; module adds prefix and suffix)."
  }
}

variable "resource_group_name" {
  description = "Resource group to deploy the vault in"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant. If null, uses current az login tenant."
  type        = string
  default     = null
}

variable "sku" {
  description = "SKU: 'standard' or 'premium' (premium adds HSM-backed keys)"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku)
    error_message = "SKU must be 'standard' or 'premium'."
  }
}

variable "soft_delete_retention_days" {
  description = "Days to retain soft-deleted secrets (7-90). Required."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Retention must be 7-90 days."
  }
}

variable "purge_protection_enabled" {
  description = "Enable purge protection. Once enabled, CANNOT be disabled. Required for prod."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Allow access from public internet. Set false in production once private endpoint is in place."
  type        = bool
  default     = false
}

variable "network_acls_default_action" {
  description = "Default action when no rule matches: Allow or Deny"
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_acls_default_action)
    error_message = "Must be 'Allow' or 'Deny'."
  }
}

variable "network_acls_bypass" {
  description = "Allow Azure services to bypass network rules (typical: 'AzureServices')"
  type        = string
  default     = "AzureServices"
}

variable "network_acls_ip_rules" {
  description = "List of CIDR ranges allowed to access (in addition to private endpoints)"
  type        = list(string)
  default     = []
}

variable "network_acls_subnet_ids" {
  description = "Subnet IDs allowed via service endpoint (alternative to private endpoint)"
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for diagnostic settings"
  type        = string
  default     = null
}

variable "name_suffix" {
  description = "Random suffix for global uniqueness (typically project's bootstrap suffix)"
  type        = string
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
  default     = {}
}
