# Bootstrap

This Terraform configuration creates the foundational resources required for
remote state management of the rest of the project.

## What this creates

- **Resource Group**: dedicated to Terraform state and bootstrap artifacts
- **Storage Account**: hardened, geo-redundant, versioned blob storage
- **Storage Container**: private container `tfstate` for state files

## When to run

- **Once at project initialization** — creates the backend
- **Never again** — unless rebuilding from scratch (rare)

## State location

Bootstrap uses **local state** by design (chicken-and-egg: it creates its
own backend, so it cannot use one). The state file `terraform.tfstate`
lives in this directory and is gitignored.

If this state file is lost, the bootstrap resources still exist in Azure
but Terraform can't manage them. Recovery: `terraform import` to re-link.

## How to run

```bash
cd infra/bootstrap

# One-time init (downloads providers)
terraform init

# Review what will be created
terraform plan -var "owner_email=YOUR_EMAIL" -var "github_org=YOUR_GITHUB_USERNAME"

# Apply
terraform apply -var "owner_email=YOUR_EMAIL" -var "github_org=YOUR_GITHUB_USERNAME"
```

## After applying

Note the outputs — particularly `backend_config_snippet`. This block is what
each environment configuration will use to connect to remote state.

## Destroying

This config is intentionally hard to destroy. If you genuinely need to:

1. Migrate all environment state files away (or accept their loss)
2. Comment out every `lifecycle { prevent_destroy = true }` block
3. `terraform destroy`

Don't do this casually.
