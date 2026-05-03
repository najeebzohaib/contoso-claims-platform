# ============================================================
# tflint configuration
# ============================================================
# tflint catches HCL issues that `terraform validate` doesn't:
#   - Deprecated provider syntax
#   - Naming convention violations
#   - Unused variables / outputs
#   - Provider-specific best practices (e.g. azurerm)
# ============================================================

config {
  # Force the rules to actually run (off by default)
  # Force-applying every rule also catches "didn't import this plugin" gotchas
  format = "compact"
  call_module_type = "all"
}

# Core Terraform rules
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Azure-specific rules
plugin "azurerm" {
  enabled = true
  version = "0.27.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
