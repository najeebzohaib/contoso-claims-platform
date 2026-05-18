output "tenant_id" {
  value = data.azuread_client_config.current.tenant_id
}

output "subscription_id" {
  value = data.azurerm_subscription.current.subscription_id
}

output "ci_client_id" {
  description = "Client ID for CI (plan-only) SP — store as AZURE_CLIENT_ID_CI in GitHub"
  value       = azuread_application.ci.client_id
}

output "cd_client_id" {
  description = "Client ID for CD (apply) SP — store as AZURE_CLIENT_ID_CD in GitHub"
  value       = azuread_application.cd.client_id
}

output "github_secrets_summary" {
  description = "Values to set as GitHub Actions secrets"
  value       = <<-EOT

    Set these in https://github.com/${var.github_org}/${var.github_repo}/settings/secrets/actions

    Repository secrets:
      AZURE_TENANT_ID        = ${data.azuread_client_config.current.tenant_id}
      AZURE_SUBSCRIPTION_ID  = ${data.azurerm_subscription.current.subscription_id}
      AZURE_CLIENT_ID_CI     = ${azuread_application.ci.client_id}
      AZURE_CLIENT_ID_CD     = ${azuread_application.cd.client_id}

  EOT
}
