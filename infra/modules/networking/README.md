# networking module

Creates a VNet with subnets, NSGs, and diagnostic settings.

## Usage

```hcl
module "vnet_dev" {
  source = "../../modules/networking"

  name                = "claims-dev-uks"
  resource_group_name = azurerm_resource_group.network.name
  location            = "uksouth"
  address_space       = ["10.10.0.0/16"]

  subnets = {
    apps = {
      cidr              = "10.10.1.0/24"
      service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage"]
    }
    data = {
      cidr = "10.10.2.0/24"
    }
    pe = {
      cidr                              = "10.10.3.0/24"
      private_endpoint_network_policies = "Disabled"
    }
  }

  log_analytics_workspace_id = module.observability.log_analytics_workspace_id

  tags = module.core.tags
}
```

## Design notes

- One module invocation per VNet
- Subnets defined as a map (uses `for_each`)
- Every subnet gets a dedicated NSG (best practice, satisfies most policies)
- Diagnostic settings only created if `log_analytics_workspace_id` is provided
- Peering is handled by a separate module (`vnet_peering`)

## What this module does NOT do

- Does not create peerings (use `vnet_peering` module)
- Does not manage NSG rules (separate module per workload)
- Does not deploy Azure Firewall, Bastion, or VPN gateway (separate modules)
- Does not create DDoS protection plan (cost-prohibitive for non-prod)
