# ============================================================
# managed_identity module
# ============================================================
# Creates a User-Assigned Managed Identity (UAMI).
#
# UAMIs are independent resources that survive parent compute
# recreation — essential for AKS Workload Identity, App Service
# slots, and any pattern requiring identity continuity.
# ============================================================

resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}
