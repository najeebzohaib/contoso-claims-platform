# ============================================================
# CI/CD Bootstrap
# ============================================================
# Creates two SPs with federated credentials so GitHub Actions
# can authenticate to Azure WITHOUT storing any secrets.
#
# - sp-claims-ci-dev:  plan-only, runs on PR events
# - sp-claims-cd-dev:  apply, runs on push to main + environment approval
# ============================================================

data "azurerm_subscription" "current" {}
data "azuread_client_config" "current" {}

locals {
  github_subject_pr            = "repo:${var.github_org}/${var.github_repo}:pull_request"
  github_subject_main          = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
  github_subject_env_dev_apply = "repo:${var.github_org}/${var.github_repo}:environment:dev-apply"
}

# ------------------------------------------------------------
# CI (plan-only) Service Principal
# ------------------------------------------------------------

resource "azuread_application" "ci" {
  display_name = "sp-claims-ci-dev"
  owners       = [data.azuread_client_config.current.object_id]
  tags         = [for k, v in var.tags : "${k}:${v}"]
}

resource "azuread_service_principal" "ci" {
  client_id = azuread_application.ci.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# Federated credential: trust PRs in this repo
resource "azuread_application_federated_identity_credential" "ci_pr" {
  application_id = azuread_application.ci.id
  display_name   = "github-pr"
  description    = "GitHub Actions PR events from ${var.github_org}/${var.github_repo}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = local.github_subject_pr
}

# RBAC: Reader on subscription (can plan, can't change anything)
resource "azurerm_role_assignment" "ci_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.ci.object_id
  description          = "Plan-only access for PR workflow"
}

# RBAC: state access for the CI SP
# Plan requires write because state locking is a blob lease (write op).
# Despite this, the SP cannot modify Azure resources — only subscription
# Reader role applies there. Defense in depth via scope, not just role.
resource "azurerm_role_assignment" "ci_state_writer" {
  scope                = var.tfstate_storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.ci.object_id
}

# ------------------------------------------------------------
# CD (apply) Service Principal
# ------------------------------------------------------------

resource "azuread_application" "cd" {
  display_name = "sp-claims-cd-dev"
  owners       = [data.azuread_client_config.current.object_id]
  tags         = [for k, v in var.tags : "${k}:${v}"]
}

resource "azuread_service_principal" "cd" {
  client_id = azuread_application.cd.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# Federated credential 1: trust main branch (for tag-based releases etc.)
resource "azuread_application_federated_identity_credential" "cd_main" {
  application_id = azuread_application.cd.id
  display_name   = "github-main"
  description    = "GitHub Actions push to main branch"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = local.github_subject_main
}

# Federated credential 2: trust dev-apply environment (with approval)
resource "azuread_application_federated_identity_credential" "cd_env" {
  application_id = azuread_application.cd.id
  display_name   = "github-env-dev-apply"
  description    = "GitHub Actions deploys to 'dev-apply' environment"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = local.github_subject_env_dev_apply
}

# RBAC: Contributor on subscription
# (Scope this tighter in production — to resource groups only, not subscription)
resource "azurerm_role_assignment" "cd_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.cd.object_id
  description          = "Apply access for CD workflow"
}

# RBAC: User Access Administrator (needed for our role-assignment Terraform resources)
resource "azurerm_role_assignment" "cd_uaa" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.cd.object_id
  description          = "Manage RBAC assignments via Terraform"
}

# RBAC: write state file
resource "azurerm_role_assignment" "cd_state_writer" {
  scope                = var.tfstate_storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.cd.object_id
}
