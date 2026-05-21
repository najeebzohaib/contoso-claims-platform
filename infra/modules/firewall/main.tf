resource "azurerm_public_ip" "firewall" {
  name                = "pip-${var.name}-fw"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

resource "azurerm_firewall_policy" "this" {
  name                     = "fwpol-${var.name}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  sku                      = "Premium"
  threat_intelligence_mode = "Alert"

  intrusion_detection {
    mode = "Alert"
  }

  dns {
    proxy_enabled = true
  }

  tags = var.tags
}

resource "azurerm_firewall" "this" {
  name                = "fw-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "AZFW_VNet"
  sku_tier            = "Premium"
  firewall_policy_id  = azurerm_firewall_policy.this.id
  zones               = ["1", "2", "3"]

  ip_configuration {
    name                 = "fw-ipconfig"
    subnet_id            = var.firewall_subnet_id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  tags = var.tags
}

resource "azurerm_firewall_policy_rule_collection_group" "default" {
  name               = "rcg-default"
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 100

  application_rule_collection {
    name     = "arc-azure-services"
    priority = 100
    action   = "Allow"

    rule {
      name             = "allow-azure-monitor"
      source_addresses = ["10.0.0.0/8"]
      destination_fqdns = [
        "*.ods.opinsights.azure.com",
        "*.oms.opinsights.azure.com",
        "*.monitoring.azure.com",
        "dc.services.visualstudio.com",
      ]
      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name             = "allow-aks-required"
      source_addresses = ["10.0.0.0/8"]
      destination_fqdns = [
        "mcr.microsoft.com",
        "*.data.mcr.microsoft.com",
        "management.azure.com",
        "login.microsoftonline.com",
        "packages.microsoft.com",
        "acs-mirror.azureedge.net",
      ]
      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name                  = "allow-acr"
      source_addresses      = ["10.0.0.0/8"]
      destination_fqdn_tags = ["AzureContainerRegistry"]
      protocols {
        type = "Https"
        port = 443
      }
    }
  }

  network_rule_collection {
    name     = "nrc-azure-infrastructure"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "allow-azure-dns"
      protocols             = ["UDP"]
      source_addresses      = ["10.0.0.0/8"]
      destination_addresses = ["168.63.129.16"]
      destination_ports     = ["53"]
    }

    rule {
      name                  = "allow-ntp"
      protocols             = ["UDP"]
      source_addresses      = ["10.0.0.0/8"]
      destination_addresses = ["*"]
      destination_ports     = ["123"]
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "firewall" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "diag-fw-${var.name}"
  target_resource_id         = azurerm_firewall.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "AzureFirewallApplicationRule" }
  enabled_log { category = "AzureFirewallNetworkRule" }
  enabled_metric { category = "AllMetrics" }
}
