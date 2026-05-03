# core module

Provides project-wide naming conventions and standard tags.

## Why this module exists

Naming and tagging are non-negotiable in enterprise Azure environments.
Centralizing them in a single module:

- Prevents drift between environments
- Makes governance enforcement (Azure Policy) trivial
- Provides a single place to update conventions globally

## Usage

```hcl
module "core" {
  source = "../../modules/core"

  environment       = "dev"
  workload          = "claims"
  location          = "uksouth"
  owner_email       = "owner@example.com"
  maintainer_email  = "maintainer@example.com"
  github_repo       = "org/repo"
  data_classification = "internal"
}

# Then in other modules
module "something" {
  source = "../../modules/something"

  tags         = module.core.tags
  name_prefix  = module.core.name_prefix
  ...
}
```

## Naming convention

`{resource-type-prefix}-{workload}-{environment}-{region-short}-{instance}`

For resources that don't allow hyphens (storage accounts, ACR), the
compact form joins parts: `stclaimsdev001`.

## Tags applied

| Tag | Source |
|-----|--------|
| Environment | input `environment` |
| Workload | "{workload}-platform" |
| Project | "ContosoClaimsLearning" |
| Owner | input `owner_email` |
| Maintainer | input `maintainer_email` |
| ManagedBy | "Terraform" |
| Repository | input `github_repo` |
| CostCenter | "learning" |
| DataClassification | input `data_classification` |
| DeployedBy | "Terraform" |

Plus any additional_tags merged in.
