# ============================================================
# core module
# ============================================================
# Encapsulates project-wide naming conventions and tags.
# Every other module depends on this for consistent metadata.
#
# Outputs:
#   - tags        : map(string) - common tags for all resources
#   - name_prefix : string - prefix for hyphen-allowed resources
#   - name_suffix : string - suffix for global-uniqueness resources
# ============================================================

locals {
  # Region short codes for resource names
  # Centralizing this prevents "uks" vs "uksouth" inconsistency
  region_short_map = {
    uksouth     = "uks"
    ukwest      = "ukw"
    westeurope  = "weu"
    northeurope = "neu"
    eastus      = "eus"
    westus2     = "wus2"
  }

  region_short = lookup(local.region_short_map, var.location, "unk")

  # Standard prefix for hyphen-allowed resources
  # e.g. "claims-dev-uks" -> {workload}-{env}-{region}
  name_prefix = "${var.workload}-${var.environment}-${local.region_short}"

  # Compact form for storage accounts, ACR, etc. (no hyphens allowed)
  # e.g. "claimsdev"
  name_prefix_compact = "${var.workload}${var.environment}"

  # Common tags applied universally
  tags = merge(
    {
      Environment        = var.environment
      Workload           = "${var.workload}-platform"
      Project            = "ContosoClaimsLearning"
      Owner              = var.owner_email
      Maintainer         = var.maintainer_email
      ManagedBy          = "Terraform"
      Repository         = var.github_repo
      CostCenter         = "learning"
      DataClassification = var.data_classification
      DeployedBy         = "Terraform"
    },
    var.additional_tags
  )
}
