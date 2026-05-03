output "tags" {
  description = "Common tags to apply to all resources"
  value       = local.tags
}

output "name_prefix" {
  description = "Standard name prefix for hyphen-allowed resources"
  value       = local.name_prefix
}

output "name_prefix_compact" {
  description = "Compact name prefix for resources that don't allow hyphens"
  value       = local.name_prefix_compact
}

output "region_short" {
  description = "Short region code for the configured location"
  value       = local.region_short
}

output "environment" {
  description = "Environment name (passed through for downstream modules)"
  value       = var.environment
}

output "location" {
  description = "Azure region (passed through for downstream modules)"
  value       = var.location
}
