# ADR-005: Frontend Hosting — Azure Static Web App

**Date:** 2025-05-21
**Status:** Accepted

## Context

The React claims UI needs a hosting platform. Options considered:
- Azure Static Web Apps
- Azure App Service
- Azure Blob static website + CDN
- Azure Front Door + Blob

## Decision

Azure Static Web Apps (Standard tier) for the following reasons:

- Built-in GitHub Actions CI/CD — push to main deploys automatically
- Global CDN included at no extra cost
- Built-in staging environments per PR
- Custom domain + managed TLS certificate included
- Standard tier supports private endpoints for API backend linkage
- Native Azure AD authentication integration (no code changes)

## Consequences

**Positive:**
- Zero infrastructure to manage for the frontend
- Automatic HTTPS with managed certificates
- PR preview environments — each PR gets a unique URL
- Integrated with GitHub — deployment token is the only secret needed
- Global CDN reduces latency for distributed users

**Negative:**
- Limited region availability (not UK South) — eastus2 used
- No support for server-side rendering (SSR) — React SPA only
- 100GB/month bandwidth limit on Standard tier

## Note on APIM Integration

The React app calls the APIM gateway URL directly. APIM is in Internal VNet mode, so for the frontend to reach it, either:
1. App Gateway exposes APIM publicly (current setup — AppGW public IP → APIM)
2. Or a custom domain on AppGW is used with proper SSL

For the portfolio demo, option 1 is used with the AppGW public IP.
