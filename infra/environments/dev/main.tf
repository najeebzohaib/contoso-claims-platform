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
    # AzureFirewallSubnet, AzureFirewallManagementSubnet and
    # AzureBastionSubnet are standalone resources below —
    # Azure requires exact names without any prefix.
    GatewaySubnet = {
      cidr = "10.0.1.0/27"
    }
    shared = {
      cidr = "10.0.3.0/24"
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
    apim = {
      cidr = "10.10.5.0/24"
    }
    dbw-public = {
      cidr = "10.10.32.0/24"
      delegations = ["Microsoft.Databricks/workspaces"]
    }
    dbw-private = {
      cidr = "10.10.33.0/24"
      delegations = ["Microsoft.Databricks/workspaces"]
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


# ------------------------------------------------------------
# Key Vault Administrator access for the human admin
# ------------------------------------------------------------
# Grant Amina (tenant owner) "Key Vault Administrator" via her
# stable Entra ID object ID. We use the object ID directly rather
# than UPN because Amina is a guest in this tenant — UPN lookups
# of guests are unreliable.
#
# NOTE: We deliberately do NOT use data.azurerm_client_config.current
# here — that resolves to whichever identity runs apply, causing
# role-assignment thrash between local runs (Amina) and CI/CD (CD SP).
resource "azurerm_role_assignment" "tenant_admin_kv_admin" {
  scope                = module.kv_dev.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.tenant_admin_object_id

  description = "Standing admin access for tenant owner (dev convenience; PIM in prod)"
}

# ============================================================
# Session 7: ACR + AKS + Workload Identity federation
# ============================================================

# Private DNS for ACR
module "dns_acr" {
  source = "../../modules/private_dns"

  zone_name           = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.hub.name

  vnet_links = {
    hub = { vnet_id = module.vnet_hub.vnet_id }
    dev = { vnet_id = module.vnet_dev.vnet_id }
  }

  tags = merge(module.core.tags, { Environment = "shared" })
}

# Azure Container Registry
module "acr_dev" {
  source = "../../modules/acr"

  name_prefix_compact        = module.core.name_prefix_compact
  name_suffix                = var.name_suffix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = module.core.tags
}

# Private endpoint for ACR
module "pe_acr_dev" {
  source = "../../modules/private_endpoint"

  name                = "acr-${module.core.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location

  subnet_id          = module.vnet_dev.subnet_ids["pe"]
  target_resource_id = module.acr_dev.id
  subresource_names  = ["registry"]

  private_dns_zone_ids = [module.dns_acr.zone_id]
  tags                 = module.core.tags
}

# Your current public IP — restricts kubectl access to your machine only
# Update if your IP changes
variable "my_public_ip" {
  description = "Your current public IP for AKS API server allowlist"
  type        = string
  default     = "0.0.0.0/0" # override in tfvars
}

# AKS cluster
module "aks_dev" {
  source = "../../modules/aks"

  name                       = module.core.name_prefix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  aks_subnet_id              = module.vnet_dev.subnet_ids["aks"]
  acr_id                     = module.acr_dev.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  authorized_ip_ranges       = [var.my_public_ip]
  tags                       = module.core.tags
}

# Workload Identity: federate the claims-api UAMI with AKS OIDC issuer
# This is what lets a pod authenticate to Key Vault without any secret
resource "azurerm_federated_identity_credential" "claims_api" {
  name                = "claims-api-aks-dev"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = module.id_claims_api.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks_dev.oidc_issuer_url
  subject             = "system:serviceaccount:claims:claims-api"
}

# ============================================================
# Session 8: AI Services — OpenAI, Document Intelligence, AI Search
# ============================================================

# Private DNS zones for AI services
module "dns_openai" {
  source = "../../modules/private_dns"

  zone_name           = "privatelink.openai.azure.com"
  resource_group_name = azurerm_resource_group.hub.name

  vnet_links = {
    hub = { vnet_id = module.vnet_hub.vnet_id }
    dev = { vnet_id = module.vnet_dev.vnet_id }
  }

  tags = merge(module.core.tags, { Environment = "shared" })
}

module "dns_cognitiveservices" {
  source = "../../modules/private_dns"

  zone_name           = "privatelink.cognitiveservices.azure.com"
  resource_group_name = azurerm_resource_group.hub.name

  vnet_links = {
    hub = { vnet_id = module.vnet_hub.vnet_id }
    dev = { vnet_id = module.vnet_dev.vnet_id }
  }

  tags = merge(module.core.tags, { Environment = "shared" })
}

module "dns_search" {
  source = "../../modules/private_dns"

  zone_name           = "privatelink.search.windows.net"
  resource_group_name = azurerm_resource_group.hub.name

  vnet_links = {
    hub = { vnet_id = module.vnet_hub.vnet_id }
    dev = { vnet_id = module.vnet_dev.vnet_id }
  }

  tags = merge(module.core.tags, { Environment = "shared" })
}

# Azure OpenAI
module "openai_dev" {
  source = "../../modules/ai_services"

  name                       = "claims-dev"
  name_suffix                = var.name_suffix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  kind                       = "OpenAI"
  sku                        = "S0"
  public_network_access_enabled = false
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = module.core.tags
}

# Private endpoint for OpenAI
module "pe_openai_dev" {
  source = "../../modules/private_endpoint"

  name                = "openai-${module.core.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  subnet_id           = module.vnet_dev.subnet_ids["pe"]
  target_resource_id  = module.openai_dev.id
  subresource_names   = ["account"]

  private_dns_zone_ids = [
    module.dns_openai.zone_id,
    module.dns_cognitiveservices.zone_id
  ]

  tags = module.core.tags
}

# Azure Document Intelligence (Form Recognizer)
module "docintel_dev" {
  source = "../../modules/ai_services"

  name                       = "docintel-dev"
  name_suffix                = var.name_suffix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  kind                       = "FormRecognizer"
  sku                        = "S0"
  public_network_access_enabled = false
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = module.core.tags
}

# Private endpoint for Document Intelligence
module "pe_docintel_dev" {
  source = "../../modules/private_endpoint"

  name                = "docintel-${module.core.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  subnet_id           = module.vnet_dev.subnet_ids["pe"]
  target_resource_id  = module.docintel_dev.id
  subresource_names   = ["account"]

  private_dns_zone_ids = [module.dns_cognitiveservices.zone_id]

  tags = module.core.tags
}

# Azure AI Search
module "search_dev" {
  source = "../../modules/ai_search"

  name                       = "claims-dev"
  name_suffix                = var.name_suffix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  sku                        = "basic"
  public_network_access_enabled = false
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = module.core.tags
}

# Private endpoint for AI Search
module "pe_search_dev" {
  source = "../../modules/private_endpoint"

  name                = "search-${module.core.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  subnet_id           = module.vnet_dev.subnet_ids["pe"]
  target_resource_id  = module.search_dev.id
  subresource_names   = ["searchService"]

  private_dns_zone_ids = [module.dns_search.zone_id]

  tags = module.core.tags
}

# RBAC: grant claims-api UAMI access to OpenAI and Search
resource "azurerm_role_assignment" "claims_api_openai" {
  scope                = module.openai_dev.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = module.id_claims_api.principal_id
  description          = "Allow claims-api to call Azure OpenAI"
}

resource "azurerm_role_assignment" "claims_api_search_reader" {
  scope                = module.search_dev.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = module.id_claims_api.principal_id
  description          = "Allow claims-api to query AI Search index"
}

# ============================================================
# Session 9: Data Platform — Data Lake Gen2 + Databricks
# ============================================================

# Private DNS for Databricks
module "dns_databricks" {
  source = "../../modules/private_dns"

  zone_name           = "privatelink.azuredatabricks.net"
  resource_group_name = azurerm_resource_group.hub.name

  vnet_links = {
    hub = { vnet_id = module.vnet_hub.vnet_id }
    dev = { vnet_id = module.vnet_dev.vnet_id }
  }

  tags = merge(module.core.tags, { Environment = "shared" })
}

# Data Lake Gen2 with medallion containers
module "datalake_dev" {
  source = "../../modules/data_lake"

  name_prefix_compact        = module.core.name_prefix_compact
  name_suffix                = var.name_suffix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  containers                 = ["bronze", "silver", "gold"]
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = module.core.tags
}

# Grant claims-api UAMI access to Data Lake
resource "azurerm_role_assignment" "claims_api_datalake" {
  scope                = module.datalake_dev.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.id_claims_api.principal_id
  description          = "Allow claims-api to write to Data Lake bronze layer"
}

# Databricks workspace with VNet injection
module "databricks_dev" {
  source = "../../modules/databricks"

  name                = module.core.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = "premium"

  virtual_network_id    = module.vnet_dev.vnet_id
  public_subnet_name    = "snet-${module.core.name_prefix}-dbw-public"
  private_subnet_name   = "snet-${module.core.name_prefix}-dbw-private"
  public_subnet_nsg_id  = module.vnet_dev.nsg_ids["dbw-public"]
  private_subnet_nsg_id = module.vnet_dev.nsg_ids["dbw-private"]

  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = module.core.tags
}


# ============================================================
# Hub special subnets — Azure requires exact subnet names
# The networking module prefixes all names so these must be
# standalone resources outside the module.
# ============================================================

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = module.vnet_hub.vnet_name
  address_prefixes     = ["10.0.0.0/26"]
}

resource "azurerm_subnet" "firewall_mgmt" {
  name                 = "AzureFirewallManagementSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = module.vnet_hub.vnet_name
  address_prefixes     = ["10.0.0.64/26"]
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = module.vnet_hub.vnet_name
  address_prefixes     = ["10.0.2.0/26"]
}

# ============================================================
# Session A: Azure Firewall Premium + DDoS + Bastion
# ============================================================

# DDoS Protection Plan (shared across VNets)
resource "azurerm_network_ddos_protection_plan" "hub" {
  name                = "ddos-${module.core.name_prefix}-hub"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  tags                = merge(module.core.tags, { Environment = "shared" })
}

# Azure Firewall Premium
module "firewall_hub" {
  source = "../../modules/firewall"

  name                       = "claims-hub-${module.core.region_short}"
  resource_group_name        = azurerm_resource_group.hub.name
  location                   = var.location
  firewall_subnet_id         = azurerm_subnet.firewall.id
  management_subnet_id       = azurerm_subnet.firewall_mgmt.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = merge(module.core.tags, { Environment = "shared" })
}

# Azure Bastion (Standard SKU — enables native client, tunneling)
module "bastion_hub" {
  source = "../../modules/bastion"

  name                       = "claims-hub-${module.core.region_short}"
  resource_group_name        = azurerm_resource_group.hub.name
  location                   = var.location
  bastion_subnet_id          = azurerm_subnet.bastion.id
  sku                        = "Standard"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = merge(module.core.tags, { Environment = "shared" })
}

# User Defined Routes — force spoke traffic through firewall
resource "azurerm_route_table" "dev_to_firewall" {
  name                          = "rt-${module.core.name_prefix}-to-fw"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = var.location
  bgp_route_propagation_enabled = false
  tags                          = module.core.tags

  route {
    name                   = "to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = module.firewall_hub.private_ip
  }
}

# Associate route table with AKS and apps subnets
resource "azurerm_subnet_route_table_association" "aks_to_fw" {
  subnet_id      = module.vnet_dev.subnet_ids["aks"]
  route_table_id = azurerm_route_table.dev_to_firewall.id
}

resource "azurerm_subnet_route_table_association" "apps_to_fw" {
  subnet_id      = module.vnet_dev.subnet_ids["apps"]
  route_table_id = azurerm_route_table.dev_to_firewall.id
}

# ============================================================
# Session B: Application Gateway (WAF) + APIM
# ============================================================

# Application Gateway with WAF v2
module "appgw_dev" {
  source = "../../modules/app_gateway"

  name                       = module.core.name_prefix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  subnet_id                  = module.vnet_dev.subnet_ids["appgw"]
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = module.core.tags
  backend_fqdn               = "10.10.5.4"
}

# API Management — Internal VNet mode
module "apim_dev" {
  source = "../../modules/apim"

  name                       = module.core.name_prefix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  publisher_email            = var.owner_email
  subnet_id                  = module.vnet_dev.subnet_ids["apim"]
  sku_name                   = "Developer_1"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = module.core.tags
}

# Private DNS zone for APIM internal mode
module "dns_apim" {
  source = "../../modules/private_dns"

  zone_name           = "azure-api.net"
  resource_group_name = azurerm_resource_group.hub.name

  vnet_links = {
    hub = { vnet_id = module.vnet_hub.vnet_id }
    dev = { vnet_id = module.vnet_dev.vnet_id }
  }

  tags = merge(module.core.tags, { Environment = "shared" })
}

# ============================================================
# React Frontend — Azure Static Web App
# ============================================================

module "swa_dev" {
  source = "../../modules/static_web_app"

  name                = module.core.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = "eastus2"  # SWA has limited region support
  sku_tier            = "Standard"
  tags                = module.core.tags
}
