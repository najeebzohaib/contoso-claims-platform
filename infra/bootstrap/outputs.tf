# ============================================================
# outputs.tf
# ============================================================
# Values exported from this configuration. The environments/*
# configs need these to configure their own backends.
# Mark sensitive values to prevent accidental console exposure.
# ============================================================

output "resource_group_name" {
  description = "Name of the resource group containing tfstate resources"
  value       = azurerm_resource_group.tfstate.name
}

output "storage_account_name" {
  description = "Name of the storage account holding Terraform state"
  value       = azurerm_storage_account.tfstate.name
}

output "container_name" {
  description = "Name of the blob container for state files"
  value       = azurerm_storage_container.tfstate.name
}

output "backend_config_snippet" {
  description = "Ready-to-paste backend block for environment configs"
  value       = <<-CONFIG
    terraform {
      backend "azurerm" {
        resource_group_name  = "${azurerm_resource_group.tfstate.name}"
        storage_account_name = "${azurerm_storage_account.tfstate.name}"
        container_name       = "${azurerm_storage_container.tfstate.name}"
        key                  = "<environment>.terraform.tfstate"
      }
    }
  CONFIG
}
