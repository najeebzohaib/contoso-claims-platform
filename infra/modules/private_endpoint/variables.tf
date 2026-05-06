variable "name" {
  description = "Logical name for the PE (becomes 'pe-{name}')"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the PE (typically same RG as the target service or the consuming spoke)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID where the PE's NIC will be created (must be a 'pe' subnet with private_endpoint_network_policies = Disabled)"
  type        = string
}

variable "target_resource_id" {
  description = "Full resource ID of the target service (e.g. Key Vault, Storage Account)"
  type        = string
}

variable "subresource_names" {
  description = <<-DOC
    Subresource names for the PE. These are service-specific:
      Key Vault         -> ["vault"]
      Storage (blob)    -> ["blob"]
      Storage (dfs)     -> ["dfs"]
      Container Registry -> ["registry"]
      AKS API           -> ["management"]
      AI Search         -> ["searchService"]
      Azure OpenAI      -> ["account"]
      Cosmos DB         -> ["Sql"]
      Service Bus       -> ["namespace"]
  DOC
  type        = list(string)
}

variable "private_dns_zone_ids" {
  description = "Private DNS zone IDs to register the PE's IP with (typically one per subresource)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
  default     = {}
}
