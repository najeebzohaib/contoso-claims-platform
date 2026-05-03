# ADR-001: Bootstrap Storage Account Security Trade-offs

- **Status**: Accepted
- **Date**: 2026-05-03
- **Deciders**: Project author (Zohaib Najeeb)

## Context

The Terraform state backend (storage account in `infra/bootstrap`) faces a
chicken-and-egg constraint: it must exist *before* the rest of the platform
(VNets, Key Vault, private endpoints, Log Analytics) can be deployed.

Trivy security scanning identifies four findings on this storage account:

- **AZU-0012 (CRITICAL)**: Public network access enabled
- **AZU-0057 (MEDIUM)**: Storage Analytics logging not enabled
- **AZU-0060 (MEDIUM)**: Not using customer-managed keys (CMK) for encryption
- **AZU-0061 (MEDIUM)**: Infrastructure encryption not enabled

A naive "fix everything" approach would resolve these but require:

- A pre-existing hub VNet to host private endpoints (does not exist at
  bootstrap time)
- A Log Analytics workspace for diagnostic settings (created by
  `environments/*` configs that consume bootstrap)
- A Key Vault for CMK (which itself requires this state backend to exist)

This is a circular dependency that no single Terraform run can resolve.

## Decision

We accept the following posture for bootstrap state storage:

| Finding | Decision | Rationale |
|---------|----------|-----------|
| AZU-0061 (Infrastructure encryption) | **Fix** | Free, no operational impact |
| AZU-0012 (Public network access) | **Accept with mitigations** | Required for laptop-driven Terraform runs prior to VNet establishment; mitigated by TLS 1.2 minimum, no anonymous access, soft delete, and versioning |
| AZU-0057 (Storage Analytics logging) | **Accept temporarily** | Diagnostic settings will be retrofitted in `environments/shared` config once Log Analytics workspace is created (Week 5) |
| AZU-0060 (Customer-managed keys) | **Accept** | Bootstrap state container uses Microsoft-managed keys; consumer resources requiring stricter controls will use CMK from Key Vault. Risk acceptable given bootstrap state contains only resource IDs and attribute references, not application secrets |

Findings AZU-0012, AZU-0057, AZU-0060 are suppressed in the source via
`# trivy:ignore` directives with cross-references to this ADR.

## Consequences

### Positive

- Bootstrap remains a single, idempotent, atomic Terraform run
- No external dependencies on VNet, Log Analytics, or Key Vault
- Junior engineers can reproduce the bootstrap without complex prerequisites

### Negative

- The state storage account is technically accessible from any IP that
  presents valid Entra ID credentials. This is the standard Microsoft
  Storage data plane behavior.
- Storage operations are not logged to Log Analytics until Week 5 retrofit

### Mitigations

- TLS 1.2 minimum enforced
- Anonymous public access disabled
- Soft-delete (30 days) on blobs and containers
- Versioning enabled for state recovery
- Delete locks (`prevent_destroy`) on all bootstrap resources
- Access requires Entra ID authentication; no anonymous reads

## Revisit triggers

This ADR should be revisited if any of the following occur:

- A regulatory requirement (e.g. PCI DSS, ISO 27001) is added to the
  project mandating private connectivity to all storage accounts
- The repository becomes shared with multiple teams whose threat model
  requires CMK
- Microsoft Defender for Storage flags this account in production scoring

## References

- [Microsoft: Securing Terraform state on Azure](https://learn.microsoft.com/azure/developer/terraform/store-state-in-azure-storage)
- [Aqua Security AVD AZU-0012](https://avd.aquasec.com/misconfig/azu-0012)
