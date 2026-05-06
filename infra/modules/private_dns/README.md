# private_dns module

Creates an Azure Private DNS zone and links it to one or more VNets.

## Why this exists

Private endpoints don't auto-create DNS records visible from your VNets.
You need a Private DNS zone with a specific name (per service) plus
explicit VNet links. This module standardizes that pattern.

## Usage

```hcl
module "dns_keyvault" {
  source = "../../modules/private_dns"

  zone_name           = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.hub.name

  vnet_links = {
    hub = { vnet_id = module.vnet_hub.vnet_id }
    dev = { vnet_id = module.vnet_dev.vnet_id }
  }

  tags = module.core.tags
}
```

## Why zones live in the hub

Private DNS zones are global resources but linking to a VNet is a
1:N relationship. Putting zones in the hub means:
- Single source of truth per service
- Spokes get DNS resolution by linking once
- Platform team manages DNS centrally; app teams don't touch it
