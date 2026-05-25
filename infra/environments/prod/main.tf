# ============================================================
# Production Environment
# ============================================================
# Stricter than dev:
#   - Key Vault: purge protection enabled, 90-day retention
#   - AKS: API server restricted to developer IP only
#   - Log Analytics: 90-day retention
#   - All same private networking patterns as dev
# ============================================================

module "core" {
  source = "../../modules/core"

  environment         = "prod"
  workload            = "claims"
  location            = var.location
  owner_email         = var.owner_email
  maintainer_email    = var.maintainer_email
  github_repo         = var.github_repo
  data_classification = "confidential"
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${module.core.name_prefix}-001"
  location = var.location
  tags     = module.core.tags
}

resource "azurerm_resource_group" "hub" {
  name     = "rg-claims-hub-prod-${module.core.region_short}-001"
  location = var.location
  tags     = merge(module.core.tags, { Environment = "shared" })
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${module.core.name_prefix}-001"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  daily_quota_gb      = 5
  tags                = module.core.tags
}

module "vnet_hub" {
  source = "../../modules/networking"

  name                = "claims-hub-prod-${module.core.region_short}"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  address_space       = ["10.1.0.0/16"]

  subnets = {
    # AzureFirewallSubnet, AzureFirewallManagementSubnet and
    # AzureBastionSubnet are standalone resources — exact names required
    GatewaySubnet = { cidr = "10.1.0.128/27" }
    shared        = { cidr = "10.1.1.0/24" }
  }

  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = merge(module.core.tags, { Environment = "shared" })
}

module "vnet_prod" {
  source = "../../modules/networking"

  name                = module.core.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  address_space       = ["10.30.0.0/16"]

  subnets = {
    apps = {
      cidr              = "10.30.1.0/24"
      service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
    }
    data = {
      cidr              = "10.30.2.0/24"
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
    }
    pe = {
      cidr                              = "10.30.3.0/24"
      private_endpoint_network_policies = "Disabled"
    }
    appgw = { cidr = "10.30.4.0/24" }
    apim  = { cidr = "10.30.5.0/24" }
    aks   = { cidr = "10.30.16.0/20" }
    apim  = { cidr = "10.30.5.0/24" }
    dbw-public = {
      cidr        = "10.30.32.0/24"
      delegations = ["Microsoft.Databricks/workspaces"]
    }
    dbw-private = {
      cidr        = "10.30.33.0/24"
      delegations = ["Microsoft.Databricks/workspaces"]
    }
  }

  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = module.core.tags
}

module "peer_hub_prod" {
  source = "../../modules/vnet_peering"

  name = "hub-prod"

  vnet_a = {
    name                = module.vnet_hub.vnet_name
    resource_group_name = azurerm_resource_group.hub.name
    id                  = module.vnet_hub.vnet_id
  }

  vnet_b = {
    name                = module.vnet_prod.vnet_name
    resource_group_name = azurerm_resource_group.main.name
    id                  = module.vnet_prod.vnet_id
  }

  a_to_b = { allow_forwarded_traffic = true }
  b_to_a = { allow_forwarded_traffic = true }
}

# Private DNS zones
module "dns_keyvault" {
  source              = "../../modules/private_dns"
  zone_name           = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.hub.name
  vnet_links = {
    hub  = { vnet_id = module.vnet_hub.vnet_id }
    prod = { vnet_id = module.vnet_prod.vnet_id }
  }
  tags = merge(module.core.tags, { Environment = "shared" })
}

module "dns_acr" {
  source              = "../../modules/private_dns"
  zone_name           = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.hub.name
  vnet_links = {
    hub  = { vnet_id = module.vnet_hub.vnet_id }
    prod = { vnet_id = module.vnet_prod.vnet_id }
  }
  tags = merge(module.core.tags, { Environment = "shared" })
}

module "dns_openai" {
  source              = "../../modules/private_dns"
  zone_name           = "privatelink.openai.azure.com"
  resource_group_name = azurerm_resource_group.hub.name
  vnet_links = {
    hub  = { vnet_id = module.vnet_hub.vnet_id }
    prod = { vnet_id = module.vnet_prod.vnet_id }
  }
  tags = merge(module.core.tags, { Environment = "shared" })
}

module "dns_cognitiveservices" {
  source              = "../../modules/private_dns"
  zone_name           = "privatelink.cognitiveservices.azure.com"
  resource_group_name = azurerm_resource_group.hub.name
  vnet_links = {
    hub  = { vnet_id = module.vnet_hub.vnet_id }
    prod = { vnet_id = module.vnet_prod.vnet_id }
  }
  tags = merge(module.core.tags, { Environment = "shared" })
}

module "dns_search" {
  source              = "../../modules/private_dns"
  zone_name           = "privatelink.search.windows.net"
  resource_group_name = azurerm_resource_group.hub.name
  vnet_links = {
    hub  = { vnet_id = module.vnet_hub.vnet_id }
    prod = { vnet_id = module.vnet_prod.vnet_id }
  }
  tags = merge(module.core.tags, { Environment = "shared" })
}

module "dns_databricks" {
  source              = "../../modules/private_dns"
  zone_name           = "privatelink.azuredatabricks.net"
  resource_group_name = azurerm_resource_group.hub.name
  vnet_links = {
    hub  = { vnet_id = module.vnet_hub.vnet_id }
    prod = { vnet_id = module.vnet_prod.vnet_id }
  }
  tags = merge(module.core.tags, { Environment = "shared" })
}

# Identity
module "id_claims_api" {
  source              = "../../modules/managed_identity"
  name                = "claims-api-prod"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = module.core.tags
}

# Key Vault — PROD: purge protection ON, 90-day retention
module "kv_prod" {
  source = "../../modules/key_vault"

  name                          = "clmprod"
  name_suffix                   = var.name_suffix
  resource_group_name           = azurerm_resource_group.main.name
  location                      = var.location
  soft_delete_retention_days    = 90
  purge_protection_enabled      = true
  public_network_access_enabled = false
  log_analytics_workspace_id    = azurerm_log_analytics_workspace.main.id
  tags                          = module.core.tags
}

module "pe_kv_prod" {
  source              = "../../modules/private_endpoint"
  name                = "kv-${module.core.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  subnet_id           = module.vnet_prod.subnet_ids["pe"]
  target_resource_id  = module.kv_prod.id
  subresource_names   = ["vault"]
  private_dns_zone_ids = [module.dns_keyvault.zone_id]
  tags                = module.core.tags
}

resource "azurerm_role_assignment" "claims_api_kv_secrets_user" {
  scope                = module.kv_prod.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.id_claims_api.principal_id
}

resource "azurerm_role_assignment" "tenant_admin_kv_admin" {
  scope                = module.kv_prod.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.tenant_admin_object_id
}

# ACR
module "acr_prod" {
  source                     = "../../modules/acr"
  name_prefix_compact        = module.core.name_prefix_compact
  name_suffix                = var.name_suffix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = module.core.tags
}

module "pe_acr_prod" {
  source               = "../../modules/private_endpoint"
  name                 = "acr-${module.core.name_prefix}"
  resource_group_name  = azurerm_resource_group.main.name
  location             = var.location
  subnet_id            = module.vnet_prod.subnet_ids["pe"]
  target_resource_id   = module.acr_prod.id
  subresource_names    = ["registry"]
  private_dns_zone_ids = [module.dns_acr.zone_id]
  tags                 = module.core.tags
}

# AKS — PROD: same restricted IP as dev
module "aks_prod" {
  source                     = "../../modules/aks"
  name                       = module.core.name_prefix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  aks_subnet_id              = module.vnet_prod.subnet_ids["aks"]
  acr_id                     = module.acr_prod.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  authorized_ip_ranges       = [var.my_public_ip]
  tags                       = module.core.tags
}

resource "azurerm_federated_identity_credential" "claims_api" {
  name                = "claims-api-aks-prod"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = module.id_claims_api.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks_prod.oidc_issuer_url
  subject             = "system:serviceaccount:claims:claims-api"
}

# Azure OpenAI
module "openai_prod" {
  source                        = "../../modules/ai_services"
  name                          = "claims-prod"
  name_suffix                   = var.name_suffix
  resource_group_name           = azurerm_resource_group.main.name
  location                      = var.location
  kind                          = "OpenAI"
  sku                           = "S0"
  public_network_access_enabled = false
  log_analytics_workspace_id    = azurerm_log_analytics_workspace.main.id
  tags                          = module.core.tags
}

module "pe_openai_prod" {
  source               = "../../modules/private_endpoint"
  name                 = "openai-${module.core.name_prefix}"
  resource_group_name  = azurerm_resource_group.main.name
  location             = var.location
  subnet_id            = module.vnet_prod.subnet_ids["pe"]
  target_resource_id   = module.openai_prod.id
  subresource_names    = ["account"]
  private_dns_zone_ids = [module.dns_openai.zone_id, module.dns_cognitiveservices.zone_id]
  tags                 = module.core.tags
}

# Document Intelligence
module "docintel_prod" {
  source                        = "../../modules/ai_services"
  name                          = "docintel-prod"
  name_suffix                   = var.name_suffix
  resource_group_name           = azurerm_resource_group.main.name
  location                      = var.location
  kind                          = "FormRecognizer"
  sku                           = "S0"
  public_network_access_enabled = false
  log_analytics_workspace_id    = azurerm_log_analytics_workspace.main.id
  tags                          = module.core.tags
}

module "pe_docintel_prod" {
  source               = "../../modules/private_endpoint"
  name                 = "docintel-${module.core.name_prefix}"
  resource_group_name  = azurerm_resource_group.main.name
  location             = var.location
  subnet_id            = module.vnet_prod.subnet_ids["pe"]
  target_resource_id   = module.docintel_prod.id
  subresource_names    = ["account"]
  private_dns_zone_ids = [module.dns_cognitiveservices.zone_id]
  tags                 = module.core.tags
}

# AI Search
module "search_prod" {
  source                        = "../../modules/ai_search"
  name                          = "claims-prod"
  name_suffix                   = var.name_suffix
  resource_group_name           = azurerm_resource_group.main.name
  location                      = var.location
  sku                           = "basic"
  public_network_access_enabled = false
  log_analytics_workspace_id    = azurerm_log_analytics_workspace.main.id
  tags                          = module.core.tags
}

module "pe_search_prod" {
  source               = "../../modules/private_endpoint"
  name                 = "search-${module.core.name_prefix}"
  resource_group_name  = azurerm_resource_group.main.name
  location             = var.location
  subnet_id            = module.vnet_prod.subnet_ids["pe"]
  target_resource_id   = module.search_prod.id
  subresource_names    = ["searchService"]
  private_dns_zone_ids = [module.dns_search.zone_id]
  tags                 = module.core.tags
}

resource "azurerm_role_assignment" "claims_api_openai" {
  scope                = module.openai_prod.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = module.id_claims_api.principal_id
}

resource "azurerm_role_assignment" "claims_api_search_reader" {
  scope                = module.search_prod.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = module.id_claims_api.principal_id
}

# Data Lake
module "datalake_prod" {
  source                     = "../../modules/data_lake"
  name_prefix_compact        = module.core.name_prefix_compact
  name_suffix                = var.name_suffix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  containers                 = ["bronze", "silver", "gold"]
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = module.core.tags
}

resource "azurerm_role_assignment" "claims_api_datalake" {
  scope                = module.datalake_prod.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.id_claims_api.principal_id
}

# Databricks
module "databricks_prod" {
  source                     = "../../modules/databricks"
  name                       = module.core.name_prefix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  sku                        = "premium"
  virtual_network_id         = module.vnet_prod.vnet_id
  public_subnet_name         = "snet-${module.core.name_prefix}-dbw-public"
  private_subnet_name        = "snet-${module.core.name_prefix}-dbw-private"
  public_subnet_nsg_id       = module.vnet_prod.nsg_ids["dbw-public"]
  private_subnet_nsg_id      = module.vnet_prod.nsg_ids["dbw-private"]
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = module.core.tags
}

# ============================================================
# Hub special subnets — exact names required by Azure
# ============================================================

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = module.vnet_hub.vnet_name
  address_prefixes     = ["10.1.0.0/26"]
}

resource "azurerm_subnet" "firewall_mgmt" {
  name                 = "AzureFirewallManagementSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = module.vnet_hub.vnet_name
  address_prefixes     = ["10.1.0.64/26"]
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = module.vnet_hub.vnet_name
  address_prefixes     = ["10.1.2.0/26"]
}

# ============================================================
# DDoS + Firewall + Bastion
# ============================================================

# DDoS Protection Plan is shared across environments (1 per subscription per region)
# Reference the plan created in dev environment
data "azurerm_network_ddos_protection_plan" "hub" {
  name                = "ddos-claims-dev-uks-hub"
  resource_group_name = "rg-claims-hub-uks-001"
}

module "firewall_hub" {
  source = "../../modules/firewall"

  name                       = "claims-hub-prod-${module.core.region_short}"
  resource_group_name        = azurerm_resource_group.hub.name
  location                   = var.location
  firewall_subnet_id         = azurerm_subnet.firewall.id
  management_subnet_id       = azurerm_subnet.firewall_mgmt.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = merge(module.core.tags, { Environment = "shared" })
}

module "bastion_hub" {
  source = "../../modules/bastion"

  name                       = "claims-hub-prod-${module.core.region_short}"
  resource_group_name        = azurerm_resource_group.hub.name
  location                   = var.location
  bastion_subnet_id          = azurerm_subnet.bastion.id
  sku                        = "Standard"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = merge(module.core.tags, { Environment = "shared" })
}

resource "azurerm_route_table" "prod_to_firewall" {
  name                          = "rt-claims-prod-uks-to-fw"
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

resource "azurerm_subnet_route_table_association" "aks_to_fw" {
  subnet_id      = module.vnet_prod.subnet_ids["aks"]
  route_table_id = azurerm_route_table.prod_to_firewall.id
}

resource "azurerm_subnet_route_table_association" "apps_to_fw" {
  subnet_id      = module.vnet_prod.subnet_ids["apps"]
  route_table_id = azurerm_route_table.prod_to_firewall.id
}

# ============================================================
# App Gateway + APIM
# ============================================================

module "appgw_prod" {
  source = "../../modules/app_gateway"

  name                       = module.core.name_prefix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  subnet_id                  = module.vnet_prod.subnet_ids["appgw"]
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = module.core.tags
  backend_fqdn               = "10.30.5.4"
}

module "apim_prod" {
  source = "../../modules/apim"

  name                       = module.core.name_prefix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  publisher_email            = var.owner_email
  subnet_id                  = module.vnet_prod.subnet_ids["apim"]
  sku_name                   = "Developer_1"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = module.core.tags
}

module "dns_apim" {
  source = "../../modules/private_dns"

  zone_name           = "azure-api.net"
  resource_group_name = azurerm_resource_group.hub.name

  vnet_links = {
    hub  = { vnet_id = module.vnet_hub.vnet_id }
    prod = { vnet_id = module.vnet_prod.vnet_id }
  }

  tags = merge(module.core.tags, { Environment = "shared" })
}

# ============================================================
# Microsoft Sentinel
# ============================================================
module "sentinel_prod" {
  source = "../../modules/sentinel"

  log_analytics_workspace_id   = azurerm_log_analytics_workspace.main.id
  log_analytics_workspace_name = azurerm_log_analytics_workspace.main.name
  resource_group_name          = azurerm_resource_group.main.name
  tags                         = module.core.tags
}
