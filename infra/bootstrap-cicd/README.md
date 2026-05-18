# CI/CD Bootstrap

Provisions Service Principals with federated credentials so GitHub Actions
can authenticate to Azure without storing any secrets.

## What this creates

- `sp-claims-ci-dev`: plan-only SP (Reader on subscription)
- `sp-claims-cd-dev`: apply SP (Contributor + User Access Administrator)
- Federated credentials trusting specific GitHub Actions contexts:
  - PRs (CI plan)
  - main branch pushes (CD)
  - dev-apply environment (CD with approval gate)

## When to run

Once. After this, all Terraform applies happen via GitHub Actions.

## Run

```bash
cd infra/bootstrap-cicd
terraform init
terraform apply
```

Note the `github_secrets_summary` output — paste those values into GitHub.
