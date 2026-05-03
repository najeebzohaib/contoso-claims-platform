# ============================================================
# backend.tf
# ============================================================
# State backend configuration. The actual values are passed
# at init time via -backend-config flags so we don't hardcode
# subscription/resource group names in version control.
#
# This is called "partial configuration" and it's the standard
# pattern in enterprise Terraform.
# ============================================================

terraform {
  backend "azurerm" {
    # All values passed at init time:
    #   terraform init \
    #     -backend-config="resource_group_name=<rg>" \
    #     -backend-config="storage_account_name=<sa>" \
    #     -backend-config="container_name=<container>" \
    #     -backend-config="key=dev.terraform.tfstate"
    #
    # Or via a backend config file:
    #   terraform init -backend-config=backend.config
    use_azuread_auth = false
  }
}
