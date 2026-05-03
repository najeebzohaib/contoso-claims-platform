variable "environment" {
  description = "Environment name: dev, staging, or prod"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "shared"], var.environment)
    error_message = "Environment must be: dev, staging, prod, or shared."
  }
}

variable "workload" {
  description = "Workload identifier (e.g. claims)"
  type        = string
  default     = "claims"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "uksouth"
}

variable "owner_email" {
  description = "Tenant owner email (financially responsible)"
  type        = string
}

variable "maintainer_email" {
  description = "Project author / maintainer email"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in form 'org/repo'"
  type        = string
}

variable "data_classification" {
  description = "Data sensitivity level"
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "Must be one of: public, internal, confidential, restricted."
  }
}

variable "additional_tags" {
  description = "Extra tags to merge into common tags"
  type        = map(string)
  default     = {}
}
