# ADR-002: AKS API Server Access Mode

- **Status**: Accepted
- **Date**: 2026-05-20
- **Deciders**: Zohaib Najeeb

## Context

AKS API server access can be:
- **Public** (default): accessible from internet
- **Public with authorized IP ranges**: filtered to known IPs
- **Private**: API server only reachable from within the VNet

## Decision

We use **public with authorized IP ranges** (developer's current IP).

Full private cluster would require a Bastion host or VPN gateway to
reach `kubectl` — adding ~£30-50/day in infra cost for this learning
project and significant setup complexity.

## Consequences

- Developer can use `kubectl` directly from their laptop
- IP allowlist must be updated if developer's public IP changes
- Production deployments MUST use private cluster or at minimum
  restrict to CI/CD agent IPs only

## Revisit

Switch to private cluster when deploying any production workload or
sharing the cluster with a team.
