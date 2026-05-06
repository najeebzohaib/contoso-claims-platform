# private_endpoint module

Generic module that creates a Private Endpoint for any Azure service
and (optionally) registers it with one or more Private DNS zones.

## Why generic

Almost every service that supports private link uses the same Terraform
resource (`azurerm_private_endpoint`) — only `subresource_names` and
DNS zone names change. A single generic module keeps the call sites
clean and the security pattern consistent.

## Usage

```hcl
module "pe_kv_dev" {
  source = "../../modules/private_endpoint"

  name                = "kv-claims-dev"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location

  subnet_id          = module.vnet_dev.subnet_ids["pe"]
  target_resource_id = module.kv_dev.id
  subresource_names  = ["vault"]

  private_dns_zone_ids = [module.dns_keyvault.zone_id]

  tags = module.core.tags
}
```
