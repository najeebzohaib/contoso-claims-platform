# ============================================================
# Dev Environment
# ============================================================
# Composes shared modules with dev-specific values.
# Resources created here are scoped to development workloads.
# ============================================================

# Core module: tags + naming conventions
module "core" {
  source = "../../modules/core"

  environment         = "dev"
  workload            = "claims"
  location            = var.location
  owner_email         = var.owner_email
  maintainer_email    = var.maintainer_email
  github_repo         = var.github_repo
  data_classification = "internal"
}

# Resource group: container for all dev resources
resource "azurerm_resource_group" "main" {
  name     = "rg-${module.core.name_prefix}-001"
  location = var.location
  tags     = module.core.tags
}

# Log Analytics workspace: central observability sink
# Every other resource in dev sends diagnostics here.
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${module.core.name_prefix}-001"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # PerGB2018 = pay-as-you-go pricing tier (the modern default)
  # Older configs may use "Free" or "Standard" — these are deprecated
  sku = "PerGB2018"

  retention_in_days = var.log_analytics_retention_days

  # Daily quota cap to prevent runaway costs from a misconfigured app
  # 1 GB/day is generous for dev; production might be higher
  daily_quota_gb = 1

  tags = module.core.tags
}
