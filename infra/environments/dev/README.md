# Dev Environment

The development environment for the Claims Platform.

## What's deployed

- Resource group `rg-claims-dev-uks-001`
- Log Analytics workspace (centralized observability sink)
- (More to come as the project progresses)

## How to deploy

### First-time init

```bash
# Copy and edit
cp backend.example.config backend.config
cp terraform.example.tfvars terraform.tfvars
# Edit both with your values

# Initialize with backend configuration
terraform init -backend-config=backend.config

# Review and apply
terraform plan -out=dev.tfplan
terraform apply dev.tfplan
```

### Subsequent runs

```bash
terraform plan -out=dev.tfplan
terraform apply dev.tfplan
```

## How to destroy

```bash
terraform destroy
```

State is preserved in the remote backend, so you can rebuild later.

## Cost expectations

- Resource group: free
- Log Analytics: free for first 5 GB/month, then £2.30/GB
- Daily quota cap set to 1 GB/day so cost can't spike unexpectedly
