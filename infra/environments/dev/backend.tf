# State backend configuration.
# Values passed at init time via -backend-config flags so we don't
# hardcode subscription/resource group names in source control.
#
# Both shared-key and Entra ID auth are accepted:
#   Local dev: uses shared key (default, since az login provides it)
#   CI/CD:     uses OIDC + Entra ID (via -backend-config="use_azuread_auth=true")
terraform {
  backend "azurerm" {}
}
