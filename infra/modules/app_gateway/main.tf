resource "azurerm_public_ip" "appgw" {
  name                = "pip-${var.name}-appgw"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

locals {
  frontend_ip_name   = "feip-public"
  frontend_port_http = "feport-80"
  backend_pool_name  = "bepool-apim"
  backend_settings   = "beset-apim"
  http_listener      = "lsnr-http"
  routing_rule       = "rrule-http"
}

resource "azurerm_application_gateway" "this" {
  name                = "agw-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  zones               = ["1", "2", "3"]
  tags                = var.tags

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = 0
    max_capacity = 10
  }

  gateway_ip_configuration {
    name      = "gwip-config"
    subnet_id = var.subnet_id
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_name
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  frontend_port {
    name = local.frontend_port_http
    port = 80
  }

  backend_address_pool {
    name  = local.backend_pool_name
    fqdns = [var.backend_fqdn]
  }

  backend_http_settings {
    name                  = local.backend_settings
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = local.http_listener
    frontend_ip_configuration_name = local.frontend_ip_name
    frontend_port_name             = local.frontend_port_http
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.routing_rule
    rule_type                  = "Basic"
    http_listener_name         = local.http_listener
    backend_address_pool_name  = local.backend_pool_name
    backend_http_settings_name = local.backend_settings
    priority                   = 100
  }

  waf_configuration {
    enabled          = true
    firewall_mode    = "Prevention"
    rule_set_type    = "OWASP"
    rule_set_version = "3.2"
  }
}

resource "azurerm_monitor_diagnostic_setting" "appgw" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "diag-agw-${var.name}"
  target_resource_id         = azurerm_application_gateway.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "ApplicationGatewayAccessLog" }
  enabled_log { category = "ApplicationGatewayPerformanceLog" }
  enabled_log { category = "ApplicationGatewayFirewallLog" }
  enabled_metric { category = "AllMetrics" }
}
