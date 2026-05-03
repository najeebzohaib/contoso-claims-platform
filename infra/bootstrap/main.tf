# ============================================================
# main.tf
# ============================================================
# Bootstrap configuration. Creates the foundational resources
# Terraform itself needs to operate properly:
#
#   1. Resource Group for state and security artifacts
#   2. Storage Account for remote state (versioned, encrypted)
#   3. Container for state files
#   4. Lock for state file (handled by azurerm provider natively
#      via blob lease — no separate resource needed)
#   5. (Future) GitHub OIDC federation for CI/CD
#
# This config uses LOCAL state. After running it once, the
# environments/* configs use the storage account it created.
# ============================================================

# ------------------------------------------------------------
# Locals: computed values used throughout the config
# ------------------------------------------------------------

locals {
  # Random suffix prevents name collisions globally
  # Storage account names must be globally unique across all of Azure
  # 4 hex chars = 65,536 combinations — collision-resistant for our purposes
  name_suffix = random_id.suffix.hex

  # Naming convention: {project}-{purpose}-{env}-{region-short}
  # Storage accounts can't contain hyphens — separate convention
  rg_name        = "rg-${var.project_name}-tfstate-${local.name_suffix}"
  sa_name        = "st${var.project_name}tfstate${local.name_suffix}" # max 24 chars
  container_name = "tfstate"

  # Common tags applied to ALL resources for governance
  # CostCenter and Environment populate cost reports automatically
  common_tags = {
    Project            = "ContosoClaimsLearning"
    Environment        = "shared"
    Workload           = "claims-platform"
    Owner              = var.owner_email
    ManagedBy          = "Terraform"
    DataClassification = "confidential" # State files contain secrets
    CostCenter         = "learning"
    Repository         = "${var.github_org}/${var.github_repo}"
    Purpose            = "terraform-state-backend"
  }
}

# ------------------------------------------------------------
# Random suffix for global uniqueness
# ------------------------------------------------------------

resource "random_id" "suffix" {
  byte_length = 2 # 4 hex chars
}

# ------------------------------------------------------------
# Resource Group
# ------------------------------------------------------------

resource "azurerm_resource_group" "tfstate" {
  name     = local.rg_name
  location = var.location
  tags     = local.common_tags

  # Lifecycle rule: prevent accidental deletion of this RG
  # Even `terraform destroy` requires removing this block first
  lifecycle {
    prevent_destroy = true
  }
}

# ------------------------------------------------------------
# Storage Account for Terraform state
# ------------------------------------------------------------
# NOTE: Trivy findings AZU-0012, AZU-0057, AZU-0060 are accepted
# for this bootstrap resource. See:
#   - .trivyignore at project root
#   - docs/architecture/adr/001-bootstrap-trade-offs.md
resource "azurerm_storage_account" "tfstate" {
  name                = local.sa_name
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location

  account_tier             = "Standard"
  account_replication_type = "GRS" # Geo-redundant: state is critical
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  # ----- Security hardening -----

  # Disable public anonymous access at the account level
  # Forces all access through authenticated channels
  allow_nested_items_to_be_public = false

  # Enforce TLS 1.2+ for all connections
  min_tls_version = "TLS1_2"

  # Disable shared key access — Microsoft Entra ID auth ONLY
  # This is the modern, recommended approach
  # Note: when this is false, our backend config must use
  #       use_azuread_auth = true (we'll see this shortly)
  shared_access_key_enabled = true # Set true for now; we'll explain below

  # Require HTTPS for all transfers
  https_traffic_only_enabled = true

  # Disable cross-tenant replication for security
  cross_tenant_replication_enabled = false

  # Enable double encryption (service + infrastructure layer)
  # Free, no operational impact, addresses Trivy AZU-0061
  infrastructure_encryption_enabled = true


  # ----- Blob-level features -----

  blob_properties {
    # Versioning: every state-file change creates a new version
    # Critical for state recovery if something goes wrong
    versioning_enabled = true

    # Change feed: audit log of every blob change
    change_feed_enabled = true

    # Soft delete for blobs: deleted state files recoverable for 30 days
    delete_retention_policy {
      days = 30
    }

    # Soft delete for containers: same protection one level up
    container_delete_retention_policy {
      days = 30
    }
  }

  tags = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

# ------------------------------------------------------------
# Storage Container for state blobs
# ------------------------------------------------------------

resource "azurerm_storage_container" "tfstate" {
  name                  = local.container_name
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private" # Never public

  lifecycle {
    prevent_destroy = true
  }
}
