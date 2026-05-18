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

# ============================================================
# Security Plane: Private DNS, Managed Identity, Key Vault, PE
# ============================================================

# ------------------------------------------------------------
# Private DNS zone for Key Vault
# Lives in the hub RG — shared across all spokes
# ------------------------------------------------------------

module "dns_keyvault" {
  source = "../../modules/private_dns"

  zone_name           = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.hub.name

  vnet_links = {
    hub = { vnet_id = module.vnet_hub.vnet_id }
    dev = { vnet_id = module.vnet_dev.vnet_id }
  }

  tags = merge(module.core.tags, {
    Environment = "shared"
  })
}

# ------------------------------------------------------------
# Managed Identity for the future claims API
# ------------------------------------------------------------

module "id_claims_api" {
  source = "../../modules/managed_identity"

  name                = "claims-api-${module.core.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = module.core.tags
}

# ------------------------------------------------------------
# Key Vault — central secrets store
# ------------------------------------------------------------

module "kv_dev" {
  source = "../../modules/key_vault"

  name                = "clmdev"
  name_suffix         = var.name_suffix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location

  # Dev: shorter retention, no purge protection
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  # Public access disabled; PE will be the access path
  public_network_access_enabled = false

  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  tags = module.core.tags
}

# ------------------------------------------------------------
# Private Endpoint connecting Key Vault into dev spoke
# ------------------------------------------------------------

module "pe_kv_dev" {
  source = "../../modules/private_endpoint"

  name                = "kv-${module.core.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location

  subnet_id          = module.vnet_dev.subnet_ids["pe"]
  target_resource_id = module.kv_dev.id
  subresource_names  = ["vault"]

  private_dns_zone_ids = [module.dns_keyvault.zone_id]

  tags = module.core.tags
}

# ------------------------------------------------------------
# RBAC: grant the claims-api identity read access to KV secrets
# This is the "no secrets in code" pattern in action
# ------------------------------------------------------------

resource "azurerm_role_assignment" "claims_api_kv_secrets_user" {
  scope                = module.kv_dev.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.id_claims_api.principal_id

  description = "Allow claims-api workload to read secrets from dev Key Vault"
}

# Grant your own user account "Key Vault Administrator" so you can
# put secrets into the vault for testing. In production, this
# would be a PIM-eligible role assignment, not a standing one.
data "azurerm_client_config" "current_user" {}

resource "azurerm_role_assignment" "current_user_kv_admin" {
  scope                = module.kv_dev.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current_user.object_id

  description = "Standing admin access for Amina (acceptable in dev; PIM in prod)"
}

# Testing CI/CD pipeline end-to-end
