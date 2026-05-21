# ADR-004: Azure Firewall Premium and Zero Trust Network Design

**Date:** 2025-05-21
**Status:** Accepted

## Context

The platform handles insurance claims data classified as confidential in production. Financial services regulators (PRA, FCA) and frameworks (NCSC CAF, CIS Azure Benchmark) require defence-in-depth network controls beyond NSGs alone.

Requirements:
- Inspect all outbound traffic from AKS nodes (supply chain attack prevention)
- East-West traffic control between spokes
- Intrusion detection and prevention
- Centralised network logging for audit/SIEM

## Decision

Deploy **Azure Firewall Premium** in the hub VNet with:
- IDPS in Alert mode (production: Deny)
- DNS proxy enabled (centralises DNS resolution)
- Threat intelligence feeds in Alert mode
- User Defined Routes forcing all spoke traffic through firewall
- Zone redundancy (zones 1, 2, 3)

Hub-spoke topology ensures single chokepoint for all North-South and East-West traffic.

## Zero Trust Principles Applied

| Principle | Implementation |
|-----------|---------------|
| Verify explicitly | All traffic authenticated via APIM JWT + Workload Identity |
| Least privilege | UDR forces traffic through FW; NSGs restrict lateral movement |
| Assume breach | IDPS detects anomalous traffic; Log Analytics captures all flows |

## Consequences

**Positive:**
- All AKS egress inspected — prevents C2 callbacks from compromised pods
- IDPS provides Layer 7 threat detection (Premium SKU only)
- Centralised logging of all network flows to Log Analytics → Sentinel
- Zone redundancy ensures no single availability zone failure affects connectivity
- Firewall policy is a separate resource — can be shared across dev/prod firewalls

**Negative:**
- Azure Firewall Premium ~£60-80/day (significant cost)
- ~7 minute provisioning time
- UDR forces all traffic through firewall — misconfigured rules can break connectivity
- AzureFirewallSubnet requires exact name (no prefix) — Terraform module limitation worked around with standalone subnet resources

**Trade-off considered:**
NSG-only approach (free) vs Firewall Premium. NSGs provide no Layer 7 inspection, no IDPS, no centralised logging beyond NSG flow logs. For a Bank of England target architecture, Firewall Premium is the correct choice.

## AzureFirewallSubnet Naming Note

Azure requires the firewall subnet to be named exactly `AzureFirewallSubnet` (not prefixed). Our networking module applies a prefix to all subnet names. This was resolved by creating the firewall, management, and bastion subnets as standalone `azurerm_subnet` resources outside the networking module, documented in the Terraform code.
