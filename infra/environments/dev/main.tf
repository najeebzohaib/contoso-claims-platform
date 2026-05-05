# ============================================================
# Dev Environment
# ============================================================
# Composes shared modules with dev-specific values.
# Resources created here are scoped to development workloads.
#
# Topology:
#   - Hub VNet (10.0.0.0/16) — shared services
#   - Dev Spoke VNet (10.10.0.0/16) — dev workloads
#   - Bidirectional peering between hub and dev
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

# ------------------------------------------------------------
# Resource Groups
# ------------------------------------------------------------

# Main RG for dev workloads (apps, data, etc.)
resource "azurerm_resource_group" "main" {
  name     = "rg-${module.core.name_prefix}-001"
  location = var.location
  tags     = module.core.tags
}

# Hub RG (shared infrastructure — would normally live in 'shared' env)
resource "azurerm_resource_group" "hub" {
  name     = "rg-claims-hub-${module.core.region_short}-001"
  location = var.location
  tags = merge(module.core.tags, {
    Environment = "shared"
  })
}

# ------------------------------------------------------------
# Observability
# ------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${module.core.name_prefix}-001"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  daily_quota_gb      = 1

  tags = module.core.tags
}

# ------------------------------------------------------------
# Hub VNet (shared services)
# ------------------------------------------------------------

module "vnet_hub" {
  source = "../../modules/networking"

  name                = "claims-hub-${module.core.region_short}"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  address_space       = ["10.0.0.0/16"]

  subnets = {
    # Reserved for future Azure Firewall (40 IPs minimum required)
    AzureFirewallSubnet = {
      cidr = "10.0.0.0/26"
    }

    # Reserved for future VPN/ExpressRoute gateway
    GatewaySubnet = {
      cidr = "10.0.0.64/27"
    }

    # Shared services subnet (e.g. private DNS resolver, jump boxes)
    shared = {
      cidr = "10.0.1.0/24"
    }
  }

  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  tags = merge(module.core.tags, {
    Environment = "shared"
  })
}

# ------------------------------------------------------------
# Dev Spoke VNet
# ------------------------------------------------------------

module "vnet_dev" {
  source = "../../modules/networking"

  name                = module.core.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  address_space       = ["10.10.0.0/16"]

  subnets = {
    apps = {
      cidr              = "10.10.1.0/24"
      service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
    }
    data = {
      cidr              = "10.10.2.0/24"
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
    }
    pe = {
      cidr                              = "10.10.3.0/24"
      private_endpoint_network_policies = "Disabled"
    }
    appgw = {
      cidr = "10.10.4.0/24"
    }
    aks = {
      cidr = "10.10.16.0/20"
    }
  }

  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  tags = module.core.tags
}

# ------------------------------------------------------------
# Hub <-> Dev Peering
# ------------------------------------------------------------

module "peer_hub_dev" {
  source = "../../modules/vnet_peering"

  name = "hub-dev"

  vnet_a = {
    name                = module.vnet_hub.vnet_name
    resource_group_name = azurerm_resource_group.hub.name
    id                  = module.vnet_hub.vnet_id
  }

  vnet_b = {
    name                = module.vnet_dev.vnet_name
    resource_group_name = azurerm_resource_group.main.name
    id                  = module.vnet_dev.vnet_id
  }

  # Hub → Dev: allow forwarded traffic (future firewall in hub will route)
  a_to_b = {
    allow_forwarded_traffic = true
  }

  # Dev → Hub: allow forwarded traffic
  b_to_a = {
    allow_forwarded_traffic = true
  }
}
