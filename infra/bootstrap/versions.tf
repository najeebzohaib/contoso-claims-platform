# ============================================================
# versions.tf
# ============================================================
# Locks Terraform and provider versions. This is the contract
# between our code and the tooling: any change here requires
# deliberate review.
#
# Pessimistic version constraint (~>) allows automatic patches
# but blocks major-version changes that may include breaking
# updates.
# ============================================================

terraform {
  required_version = "~> 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.10"
    }

    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  # Features block is required by azurerm provider 3.x+
  # Enables specific behaviors per resource type
  features {
    key_vault {
      # Don't auto-purge soft-deleted Key Vaults on destroy
      # Forces deliberate cleanup to prevent accidental data loss
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }

    resource_group {
      # Refuse to delete RGs containing resources Terraform doesn't track
      # Prevents accidental wipe of manually-created resources
      prevent_deletion_if_contains_resources = true
    }
  }
}

provider "azuread" {
  # Uses the same auth context as azurerm (your az login)
}
