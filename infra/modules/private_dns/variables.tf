# ============================================================
# private_dns module
# ============================================================
# Creates a Private DNS zone and links it to one or more VNets.
# DNS zones are typically deployed in the hub and shared by spokes.
#
# Common zone names by service (memorize these for interviews):
#   privatelink.vaultcore.azure.net          - Key Vault
#   privatelink.blob.core.windows.net        - Storage Blob
#   privatelink.dfs.core.windows.net         - Storage Data Lake Gen2
#   privatelink.file.core.windows.net        - Storage Files
#   privatelink.queue.core.windows.net       - Storage Queue
#   privatelink.table.core.windows.net       - Storage Table
#   privatelink.azurecr.io                   - Container Registry
#   privatelink.{region}.azmk8s.io           - AKS API server
#   privatelink.cognitiveservices.azure.com  - Cognitive Services / OpenAI
#   privatelink.openai.azure.com             - Azure OpenAI (alternative)
#   privatelink.search.windows.net           - AI Search
#   privatelink.documents.azure.com          - Cosmos DB
#   privatelink.servicebus.windows.net       - Service Bus / Event Hub
#   privatelink.azuredatabricks.net          - Databricks workspace
#   privatelink.{region}.batch.azure.com     - Azure Batch
# ============================================================

variable "zone_name" {
  description = "Private DNS zone name (e.g. privatelink.vaultcore.azure.net)"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the DNS zone (typically hub RG)"
  type        = string
}

variable "vnet_links" {
  description = <<-DOC
    Map of VNet links. Key is the link's logical name (used for resource naming).
    Each entry must include the VNet's full resource ID.

    Example:
      vnet_links = {
        hub = { vnet_id = module.vnet_hub.vnet_id, registration_enabled = false }
        dev = { vnet_id = module.vnet_dev.vnet_id, registration_enabled = false }
      }
  DOC
  type = map(object({
    vnet_id              = string
    registration_enabled = optional(bool, false)
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
  default     = {}
}
