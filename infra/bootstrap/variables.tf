# ============================================================
# variables.tf
# ============================================================
# Inputs to this configuration. Strict validation ensures
# bad inputs fail fast at plan time rather than confusingly
# at apply time.
# ============================================================

variable "location" {
  description = "Azure region for all bootstrap resources"
  type        = string
  default     = "uksouth"

  validation {
    condition     = contains(["uksouth", "ukwest", "westeurope", "northeurope"], var.location)
    error_message = "Location must be one of: uksouth, ukwest, westeurope, northeurope."
  }
}

variable "project_name" {
  description = "Project name used for resource naming. Lowercase alphanumeric only."
  type        = string
  default     = "claims"

  validation {
    condition     = can(regex("^[a-z0-9]{3,12}$", var.project_name))
    error_message = "Project name must be 3-12 lowercase alphanumeric characters."
  }
}

variable "owner_email" {
  description = "Email of the resource owner, applied as a tag for cost attribution"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", var.owner_email))
    error_message = "Must be a valid email address."
  }
}

variable "github_org" {
  description = "GitHub organization or username (used for OIDC federation in CI/CD)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (used for OIDC federation in CI/CD)"
  type        = string
  default     = "contoso-claims-platform"
}
