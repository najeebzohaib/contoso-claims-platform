resource "azurerm_api_management" "this" {
  name                = "apim-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = var.sku_name

  virtual_network_type = "Internal"

  virtual_network_configuration {
    subnet_id = var.subnet_id
  }

  identity {
    type = "SystemAssigned"
  }

  protocols {
    enable_http2 = true
  }

  security {
    enable_backend_tls10                                = false
    enable_backend_ssl30                                = false
    enable_frontend_tls10                               = false
    enable_frontend_ssl30                               = false
    tls_ecdhe_ecdsa_with_aes128_cbc_sha_ciphers_enabled = false
    tls_ecdhe_ecdsa_with_aes256_cbc_sha_ciphers_enabled = false
    tls_ecdhe_rsa_with_aes128_cbc_sha_ciphers_enabled   = false
    tls_ecdhe_rsa_with_aes256_cbc_sha_ciphers_enabled   = false
    tls_rsa_with_aes128_cbc_sha256_ciphers_enabled      = false
    tls_rsa_with_aes128_cbc_sha_ciphers_enabled         = false
    tls_rsa_with_aes256_cbc_sha256_ciphers_enabled      = false
    tls_rsa_with_aes256_cbc_sha_ciphers_enabled         = false
  }

  tags = var.tags

  timeouts {
    create = "90m"
    update = "90m"
    delete = "90m"
  }
}

resource "azurerm_monitor_diagnostic_setting" "apim" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "diag-apim-${var.name}"
  target_resource_id         = azurerm_api_management.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "GatewayLogs" }
  enabled_log { category = "WebSocketConnectionLogs" }
  enabled_metric { category = "AllMetrics" }
}
