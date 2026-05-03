# Modules declare their provider requirements but do NOT
# instantiate providers — that's the root module's job.
# This is a Terraform best practice that allows modules
# to be reused across configs with different provider configs.

terraform {
  required_version = "~> 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.10"
    }
  }
}
