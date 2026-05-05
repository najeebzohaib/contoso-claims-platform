# vnet_peering module

Creates a bidirectional peering between two VNets. Both directions
are configured independently because they often need different settings.

## Usage

```hcl
module "peer_dev_to_hub" {
  source = "../../modules/vnet_peering"

  name = "dev-to-hub"

  vnet_a = {
    name                = module.vnet_dev.vnet_name
    resource_group_name = "rg-claims-dev-uks-001"
    id                  = module.vnet_dev.vnet_id
  }

  vnet_b = {
    name                = module.vnet_hub.vnet_name
    resource_group_name = "rg-claims-hub-uks-001"
    id                  = module.vnet_hub.vnet_id
  }

  # Spoke → Hub: allow forwarded traffic, don't transit through gateway
  a_to_b = {
    allow_forwarded_traffic = true
  }

  # Hub → Spoke: typically allow gateway transit (if hub has gateway)
  b_to_a = {
    allow_forwarded_traffic = true
    allow_gateway_transit   = false  # set true once VPN/ER gateway exists in hub
  }
}
```
