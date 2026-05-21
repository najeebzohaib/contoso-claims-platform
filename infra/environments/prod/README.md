# Production Environment

Identical service topology to dev with stricter security settings:

| Setting | Dev | Prod |
|---------|-----|------|
| KV purge protection | false | **true** |
| KV retention | 7 days | **90 days** |
| Log Analytics retention | 30 days | **90 days** |
| Data classification | internal | **confidential** |
| AKS API server | developer IP | developer IP |

## Deploy

```bash
cp backend.example.config backend.config
cp terraform.example.tfvars terraform.tfvars
# Edit both with prod values

terraform init -backend-config=backend.config
terraform plan -out=prod.tfplan
terraform apply prod.tfplan

