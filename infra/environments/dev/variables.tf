variable "location" {
  description = "Azure region"
  type        = string
  default     = "uksouth"
}

variable "owner_email" {
  description = "Tenant owner email"
  type        = string
}

variable "maintainer_email" {
  description = "Project maintainer email"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in form 'org/repo'"
  type        = string
  default     = "najeebzohaib/contoso-claims-platform"
}

variable "log_analytics_retention_days" {
  description = "Retention period for Log Analytics. Cost grows with this."
  type        = number
  default     = 30 # Dev environment: minimum allowed is 30
}
