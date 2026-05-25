resource "azurerm_sentinel_log_analytics_workspace_onboarding" "this" {
  workspace_id = var.log_analytics_workspace_id
}

resource "azurerm_sentinel_alert_rule_ms_security_incident" "asc" {
  name                       = "sentinel-rule-asc-incidents"
  log_analytics_workspace_id = var.log_analytics_workspace_id
  product_filter             = "Azure Security Center"
  display_name               = "Azure Security Center Incidents"
  severity_filter            = ["High", "Medium"]
  depends_on                 = [azurerm_sentinel_log_analytics_workspace_onboarding.this]
}

resource "azurerm_sentinel_alert_rule_ms_security_incident" "aad" {
  name                       = "sentinel-rule-aad-incidents"
  log_analytics_workspace_id = var.log_analytics_workspace_id
  product_filter             = "Azure Active Directory Identity Protection"
  display_name               = "AAD Identity Protection Incidents"
  severity_filter            = ["High", "Medium", "Low"]
  depends_on                 = [azurerm_sentinel_log_analytics_workspace_onboarding.this]
}

resource "azurerm_sentinel_alert_rule_ms_security_incident" "mdatp" {
  name                       = "sentinel-rule-mdatp-incidents"
  log_analytics_workspace_id = var.log_analytics_workspace_id
  product_filter             = "Microsoft Defender Advanced Threat Protection"
  display_name               = "Microsoft Defender ATP Incidents"
  severity_filter            = ["High", "Medium"]
  depends_on                 = [azurerm_sentinel_log_analytics_workspace_onboarding.this]
}
