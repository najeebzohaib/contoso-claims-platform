# Module 1 — Deep Dive Answers
## Your questions answered with examples from the Contoso platform

---

## Question 1 — Microservices, Serverless, VMs: How Would Networking Work?

### If this were a microservice architecture

In a microservice architecture, you typically have many small services (claims-ingestion, claims-processor, fraud-detector, notification-service, etc.) instead of one API. The question is: do they all get their own subnet?

**Short answer: No. Services inside AKS share the AKS subnet.**

Here is why. Kubernetes handles service-to-service communication internally. When `claims-processor` calls `fraud-detector`, that traffic stays inside the AKS cluster — it goes from one pod IP to another pod IP, both in the 192.168.x.x pod CIDR. The Azure network never sees this traffic. NSGs and subnets are irrelevant for pod-to-pod communication within AKS.

What Kubernetes uses instead is:
- **Services** — a stable internal DNS name and IP for each microservice (`fraud-detector.claims.svc.cluster.local`)
- **Network Policies** — Kubernetes-native rules saying "claims-processor can call fraud-detector but notification-service cannot"

So your networking question for microservices inside AKS is really a Kubernetes question, not an Azure networking question.

**Subnet per microservice only makes sense when services are OUTSIDE AKS.** For example:

```
AKS subnet (10.10.16.0/20)
  - claims-ingestion pod
  - claims-processor pod
  - fraud-detector pod
  - notification-service pod
  (all share this subnet, talk to each other via Kubernetes Services)

Functions subnet (10.10.6.0/24)
  - document-ocr-function (Azure Function, VNet integrated)
  - email-sender-function  (Azure Function, VNet integrated)

VM subnet (10.10.7.0/24)
  - legacy-db-vm (old system that cannot be containerised)
  - reporting-vm

Private endpoint subnet (10.10.3.0/24)
  - pe-openai
  - pe-keyvault
  - pe-storage
```

Each subnet gets its own NSG. The AKS subnet NSG does not restrict pod-to-pod traffic (Kubernetes handles that), but it does restrict what can reach AKS from outside (only APIM at 10.10.5.x).

### What about Azure Functions (serverless)?

Azure Functions can run in two modes:

**Consumption plan** — fully serverless, no VNet integration. Functions run on shared Microsoft infrastructure. You cannot put these in your VNet. They call your services over the internet (or via service endpoints, which is a weaker version of private endpoints). Not suitable for a regulated platform.

**Premium plan or App Service plan** — supports VNet Integration. The function gets an outbound IP inside your chosen subnet. You can now apply NSG rules and route traffic through the firewall.

For the Contoso platform, if you added a Function App for document processing:
```
Functions app (Premium plan)
  VNet integration → snet-claims-dev-uks-functions (10.10.6.0/24)
  UDR on that subnet → firewall
  NSG: allow inbound from AKS subnet only
```

The Function calls Document Intelligence → private endpoint → private IP. Same security model as AKS.

### What about VMs?

VMs go in their own subnet. Communication between the VM subnet and AKS subnet depends on what you want:

```
VM (10.10.7.10) needs to call claims-api (10.10.16.x via internal LB 10.10.16.6)
  -> Traffic stays in the VNet (same spoke)
  -> NSG on VM subnet: allow outbound to 10.10.16.0/20 port 80
  -> NSG on AKS subnet: allow inbound from 10.10.7.0/24 port 80
  -> No firewall needed for this (same VNet, no UDR forcing through firewall)
```

But if the VM is in a different spoke:
```
VM in prod spoke (10.30.7.10) needs to call dev claims-api (10.10.16.6)
  -> Traffic must go: prod spoke → hub → dev spoke
  -> Passes through firewall (if UDR is in place)
  -> Firewall network rule: allow TCP from 10.30.7.0/24 to 10.10.16.6 port 80
```

### Zone Redundancy and Regional Redundancy

**Availability Zones (within one region):** Azure regions have 2-3 physical data centres called zones. Zone-redundant resources survive a zone going down.

For your platform, zone redundancy looks like:

| Resource | Zone configuration |
|----------|-------------------|
| App Gateway v2 | Zone redundant by default (zones 1,2,3) |
| AKS nodes | Spread across zones using node pool zones |
| Azure Firewall | Zone redundant SKU |
| APIM | Developer SKU is single zone. Standard/Premium is zone redundant |

To make AKS zone redundant, you configure the node pool:
```hcl
resource "azurerm_kubernetes_cluster_node_pool" "this" {
  availability_zones = ["1", "2", "3"]
  # Kubernetes spreads pods across zones
}
```

Subnets span all zones — you do not need one subnet per zone. The zone is a property of the resource (VM, AKS node) not the subnet.

**Regional redundancy (active-active across two regions):**

This is significantly more complex. You would:
1. Deploy the entire hub-spoke in a second region (e.g. UK West)
2. Use Azure Traffic Manager or Azure Front Door to route users to the nearest/healthiest region
3. Replicate data between regions (ADLS Gen2 GRS, Cosmos DB multi-region writes)
4. Peer the two hub VNets together (global VNet peering)

The subnets in each region are identical in structure but use different IP ranges:
```
UK South hub: 10.0.0.0/16
UK West hub:  10.1.0.0/16
UK South dev: 10.10.0.0/16
UK West dev:  10.11.0.0/16
```

For the Contoso platform, regional redundancy was not implemented — the cost and complexity was not justified for a learning project. But the structure (separate CIDRs, modular Terraform) was designed to make it straightforward to add.

---

## Question 2 — Viewing VNets, Subnets, NSGs in the Portal and in Code

### In the Azure Portal

**To see VNets:**
1. Search "Virtual networks" in the top bar
2. Filter by subscription: UrgentCoverProductionSubscription
3. You will see `vnet-claims-hub-uks` and `vnet-claims-dev-uks`
4. Click `vnet-claims-dev-uks`
5. Click **Subnets** in the left menu — see all subnets with their CIDRs
6. Click **Peerings** — see the hub peering
7. Click **Connected devices** — see all resources (AKS nodes, private endpoints) with their IPs

**To see NSGs:**
1. Search "Network security groups"
2. Click `nsg-claims-dev-uks-apim`
3. Click **Inbound security rules** — see the 3443 and 6390 rules
4. Click **Outbound security rules** — see what APIM is allowed to call
5. Click **Network interfaces** or **Subnets** — see what the NSG is attached to
6. Click **NSG flow logs** — see if flow logging is enabled

**To see a private endpoint:**
1. Search "Private endpoints"
2. Click `pe-openai-claims-dev-uks`
3. Click **DNS configuration** — see the private DNS zone link and the A record (IP)
4. Click **Network interface** — see the private IP assigned

### In the Terraform code

Every Azure resource maps to a Terraform resource. Once you know the pattern, you can read any Terraform code.

**VNet in Terraform:**
```
Azure Portal: Virtual Network > vnet-claims-dev-uks > Address space: 10.10.0.0/16
Terraform:    resource "azurerm_virtual_network" in infra/modules/networking/main.tf
              variable address_space = "10.10.0.0/16" in infra/environments/dev/main.tf
```

**NSG rule in Terraform:**
```
Azure Portal: NSG > nsg-claims-dev-uks-apim > Inbound rules > port 3443
Terraform:    resource "azurerm_network_security_rule" in infra/modules/networking/main.tf
              Look for destination_port_range = "3443"
```

**Private endpoint in Terraform:**
```
Azure Portal: Private endpoints > pe-openai-claims-dev-uks > DNS configuration
Terraform:    resource "azurerm_private_endpoint" in infra/modules/private_endpoint/main.tf
              resource "azurerm_private_dns_zone_virtual_network_link" for the DNS link
```

The pattern is always: Portal shows you the deployed state, Terraform shows you the declared state. They should match. If they differ, something was changed manually outside Terraform (called "configuration drift").

---

## Question 3 — App Gateway and APIM NSG Rules Explained

### What are service tags?

A service tag is a named group of IP address ranges managed by Microsoft. Instead of maintaining a list of Microsoft's IP addresses (which change constantly), you use a service tag in your NSG rule and Microsoft keeps it updated.

Examples:
- `GatewayManager` — IP ranges used by Azure to manage Application Gateway instances
- `ApiManagement` — IP ranges used by Azure to manage APIM instances
- `AzureLoadBalancer` — IP ranges used by Azure's internal load balancer health probes
- `Internet` — any public IP (useful for "allow inbound from anywhere")
- `VirtualNetwork` — any IP within the same VNet or peered VNets

You do not know the actual IP addresses behind a service tag. You do not need to. Microsoft manages them.

### Why does App Gateway need ports 65200-65535 open?

Here is what happens when Azure provisions an Application Gateway:

1. You click "Create Application Gateway" (or Terraform runs)
2. Azure allocates VMs in its own infrastructure to run your App Gateway instances
3. Azure's **Gateway Manager** (running in Microsoft's infrastructure, not yours) needs to reach those VMs to configure them, check their health, and deploy updates
4. Gateway Manager contacts the App Gateway instances on ports 65200-65535

These are not your ports. They are Azure's internal management ports. The traffic flows like this:

```
Azure Gateway Manager (IP in GatewayManager service tag range)
  → port 65200-65535
  → App Gateway instances in your appgw subnet (10.10.4.x)
```

If your NSG blocks this:
- Azure cannot configure the App Gateway
- Health checks fail
- App Gateway stays in "Failed" provisioning state

You never see this traffic in normal operations. It is Azure's internal plumbing. But the NSG does not know the difference between Azure's internal traffic and anything else — it blocks everything matching the rule, so you must explicitly allow it.

### Why does APIM need port 3443?

APIM in Internal VNet mode has a management endpoint on port 3443. Azure uses this endpoint to:
- Deploy configuration changes
- Monitor APIM health
- Push policy updates

The `ApiManagement` service tag represents the IPs of Azure's APIM management infrastructure (not your APIM instance — Azure's control plane for managing APIM).

```
Azure APIM control plane (IP in ApiManagement service tag)
  → port 3443
  → your APIM instance in apim subnet (10.10.5.4)
```

Port 6390 is Azure Load Balancer's health probe. Azure's internal load balancer sends a TCP ping to port 6390 on your APIM instance. If APIM does not respond, the load balancer marks it unhealthy and stops sending traffic.

```
Azure Load Balancer (IP in AzureLoadBalancer service tag: 168.63.129.16)
  → port 6390
  → your APIM instance
  → APIM responds → Load Balancer marks it Healthy
```

### Visualisation: packet flow end-to-end

```
YOUR BROWSER (e.g. 82.x.x.x at home)
  │
  │ HTTPS request to 4.158.34.10/claims/v1/submit
  ▼
[DDoS Protection] — checks for volumetric attack patterns
  │
  ▼
[App Gateway WAF — public IP 4.158.34.10]
  │ WAF inspects HTTP request for OWASP attacks
  │ Is it SQL injection? XSS? → If yes: 403 Forbidden
  │ If no: forward to backend pool
  │
  │ Looks up backend pool: APIM at 10.10.5.4
  ▼
[APIM — private IP 10.10.5.4]
  │ Is there an API operation matching POST /claims/v1/submit? → Yes
  │ Apply inbound policies (CORS, rate limit)
  │ Forward to backend: http://10.10.16.6
  │
  ▼
[AKS Internal Load Balancer — 10.10.16.6]
  │ Round-robins to one of the 3 claims-api pods
  │
  ▼
[claims-api pod — 192.168.x.x]
  │ FastAPI receives POST /v1/submit
  │ Stores claim in memory
  │ Returns 200 with claim ID
  │
  └──→ (for /analyse only) calls Azure OpenAI
          │ DNS resolves cog-claims-dev-0bd2.openai.azure.com
          │ → private DNS returns 10.10.3.5
          │ → TCP connection to 10.10.3.5 (private endpoint NIC)
          │ → private endpoint forwards to OpenAI service
          │ → OpenAI returns JSON analysis
          └──→ pod returns analysis to caller

Response travels back up the same path.
```

---

## Question 4 — Firewall vs WAF: Which for HTTP Inspection?

**They are different tools for different threats. Using both is correct, not redundant.**

| Tool | What it inspects | What it catches |
|------|-----------------|-----------------|
| WAF (App Gateway) | HTTP request content | SQL injection, XSS, path traversal, OWASP Top 10 |
| Azure Firewall Premium | All TCP/UDP traffic | Port scans, C2 callbacks, known malware, lateral movement |

A concrete example of why you need both:

**Scenario:** An attacker sends a request with a SQL injection payload to your API: `POST /claims/v1/submit` with body `{"description": "'; DROP TABLE claims; --"}`.

- **WAF catches this** — it inspects the HTTP body and matches the OWASP SQL injection rule. Blocks the request. Firewall never sees it.

**Scenario:** A pod in AKS is compromised by a supply chain attack in a pip package. The malicious code tries to connect to a command-and-control server at `evil.ru` on port 443.

- **WAF cannot catch this** — WAF only sees inbound requests to your API. This is outbound traffic from a pod. WAF is entirely irrelevant here.
- **Firewall catches this** — the pod's outbound traffic hits the UDR and goes to the firewall. The IDPS engine checks the destination against 58,000 threat signatures. `evil.ru` is in the threat intelligence feed. Firewall blocks the connection and logs the attempt. Sentinel raises an alert.

So WAF protects inbound HTTP attacks. Firewall protects outbound threats and east-west lateral movement. They are complementary, not redundant.

### What is lateral movement?

Lateral movement is when an attacker has compromised one resource and moves to compromise others. Example:

1. Attacker exploits a vulnerability in the claims-api pod
2. From inside that pod, attacker scans the VNet for other open ports: `nmap 10.10.0.0/16`
3. Attacker finds the Key Vault private endpoint at 10.10.3.6
4. Attacker tries to authenticate to Key Vault directly
5. Attacker finds the Databricks cluster at 10.10.32.x and tries to connect

Firewall Premium IDPS detects step 2 — port scanning from an internal IP is a known attack signature. It alerts and blocks. Without IDPS, an attacker inside the VNet could probe freely.

### NSG Flow Logs vs Azure Monitor vs Log Analytics

These are not alternatives — they work together.

**NSG Flow Logs:** Raw log of every network connection (allowed or denied) through an NSG. Format: source IP, destination IP, port, protocol, bytes, allowed/denied. Stored in a storage account. Useful for: network forensics, compliance, understanding traffic patterns.

**Azure Monitor:** The platform-wide monitoring service. Collects metrics (numbers over time: CPU%, request count) and logs from Azure resources. The pipeline is:
```
Resource (NSG, Firewall, AKS, etc.)
  → Diagnostic Settings
  → Log Analytics Workspace
  → Azure Monitor queries (KQL)
  → Sentinel alerts
  → Dashboards
```

**Log Analytics:** The storage and query engine for logs. You write KQL (Kusto Query Language) queries to analyse logs. For example:
```kql
AzureDiagnostics
| where ResourceType == "AZUREFIREWALLS"
| where msg_s contains "Deny"
| summarize count() by bin(TimeGenerated, 1h)
```
This shows denied firewall connections per hour.

**The relationship:**
```
NSG Flow Logs → stored in Storage Account (raw, cheap, bulk)
Firewall Logs → Log Analytics (queryable, fast, 30-day retention)
AKS Logs     → Log Analytics
APIM Logs    → Log Analytics
All of above → Sentinel (correlation, alerting, incidents)
```

For the Contoso platform, all Diagnostic Settings stream to `log-claims-dev-uks-001`. Sentinel reads from that workspace. This is the correct enterprise pattern.

### What about inbound traffic control?

You are right to question this. The table I showed was incomplete. Inbound is controlled by:

1. **App Gateway WAF** — the only public-facing component. All HTTP/HTTPS traffic enters here. WAF applies OWASP rules. This is your primary inbound control.

2. **NSG on the appgw subnet** — allows only ports 80, 443 from the internet (plus the 65200-65535 management range). Everything else is blocked.

3. **NSG on the apim subnet** — allows inbound only from the appgw subnet (10.10.4.0/24). APIM cannot be reached from the internet or from AKS directly — only from App Gateway.

4. **NSG on the aks subnet** — allows inbound only from the apim subnet (10.10.5.0/24). The claims-api cannot be reached from the internet or from other Azure services except APIM.

So the inbound security is enforced by the architecture: public → App Gateway only → APIM only → AKS only. This is defence in depth. Each layer only accepts traffic from the layer above it.

### If we are paying for Firewall, should we use it for everything?

Not necessarily. The Firewall is excellent at what it does, but using it for everything creates unnecessary latency and complexity.

**Use Firewall for:**
- All egress (outbound) inspection — Firewall is designed for this
- North-south traffic (VNet to internet)
- East-west traffic between spokes (dev to prod) — forced through hub Firewall

**Keep using NSGs for:**
- Subnet-to-subnet rules within the same VNet
- Blocking specific ports at the subnet level
- Azure service-specific rules (APIM port 3443, App Gateway 65200-65535)

The Firewall operates on all traffic flowing through the hub. NSGs add an additional layer at the subnet level. Having both means an attacker must bypass two controls, not one.

---

## Question 5 — UDRs: How They Work

A UDR is a route table attached to a subnet. It overrides Azure's default routing decisions.

**Azure's default routing (without UDR):**
```
Destination: 10.10.5.0/24 (APIM subnet) → route directly, it's in the same VNet
Destination: 10.0.0.0/16 (hub VNet) → route via VNet peering
Destination: 0.0.0.0/0 (everything else) → route to internet via Azure's default gateway
```

**With your UDR on the AKS subnet:**
```
Destination: 0.0.0.0/0 (everything else) → send to 10.0.0.4 (Firewall) as VirtualAppliance
```

The `VirtualAppliance` next hop type tells Azure: instead of using default routing, send this packet to the specified IP. Azure Firewall acts as a router — it receives the packet, inspects it, and either drops it or forwards it to the correct destination.

**UDRs are NOT configured inside the Firewall.** They are a separate Azure resource (route table) attached to a subnet. The Firewall does not know about the UDR. The UDR just redirects traffic to the Firewall's private IP. The Firewall then handles the packet independently.

```
Pod sends packet → Azure networking checks AKS subnet route table
→ UDR says: next hop is 10.0.0.4 (VirtualAppliance)
→ Azure delivers packet to Firewall NIC at 10.0.0.4
→ Firewall checks its application/network rules
→ If allowed: Firewall forwards packet to real destination (SNAT)
→ If denied: Firewall drops packet and logs
```

**SNAT (Source Network Address Translation):** When the Firewall forwards a packet, it changes the source IP from the pod's IP (192.168.x.x) to the Firewall's public IP. This is important — the destination server sees the Firewall's IP, not the pod's IP. This means all your AKS egress traffic appears to come from one IP (the Firewall public IP), which makes it easy to allowlist in third-party services.

---

## Question 6 — Private DNS Zones and Private Endpoints Fully Explained

This is one of the most important concepts to understand deeply. Let me build it from first principles.

### How DNS works normally (public)

When you type `cog-claims-dev-0bd2.openai.azure.com` in a browser:

1. Your computer asks its DNS resolver (usually your router): "what is the IP for this name?"
2. The resolver asks Azure's public DNS servers
3. Azure's public DNS returns: `20.50.x.x` (a public Azure IP)
4. Your browser connects to `20.50.x.x` on the internet
5. Azure routes this to the OpenAI service

This is fine for a browser. But for a pod inside your VNet calling OpenAI, you want the traffic to stay inside Azure's network — never touch the internet.

### What a Private Endpoint is

A private endpoint is a network interface card (NIC) inside your VNet with a private IP. Azure connects this NIC directly to the backing service (OpenAI) through Azure's internal network.

```
Your VNet (10.10.x.x)
  └── Private endpoint NIC (IP: 10.10.3.5)
        └── [Azure internal network]
              └── Azure OpenAI service
```

When a pod sends TCP traffic to `10.10.3.5`, it reaches OpenAI directly through Azure's backbone. No internet. No public IP involved.

**But there is a problem:** if the pod calls `cog-claims-dev-0bd2.openai.azure.com`, DNS still resolves this to the public IP `20.50.x.x`. The private endpoint exists but the pod does not know to use it.

This is where Private DNS Zones come in.

### What a Private DNS Zone does

A Private DNS Zone is a custom DNS database that only exists inside your VNet. It overrides public DNS resolution for specific names.

You create a zone called `privatelink.openai.azure.com`. Inside it, you create an A record:
```
cog-claims-dev-0bd2.privatelink.openai.azure.com → 10.10.3.5
```

### How the name resolution actually works

Here is the confusing part that trips everyone up. The hostname `cog-claims-dev-0bd2.openai.azure.com` is the name you use. The Private DNS zone is named `privatelink.openai.azure.com`. How does a query for one resolve using the other?

Azure does something clever. When you create a private endpoint for OpenAI, Azure automatically creates a DNS alias (CNAME) in its public DNS:

```
Public DNS:
cog-claims-dev-0bd2.openai.azure.com
  → CNAME → cog-claims-dev-0bd2.privatelink.openai.azure.com
```

So when a pod queries `cog-claims-dev-0bd2.openai.azure.com`:

**From inside the VNet (with Private DNS Zone linked):**
```
1. Pod asks Azure internal DNS: "what is cog-claims-dev-0bd2.openai.azure.com?"
2. Azure internal DNS checks the Private DNS Zone: privatelink.openai.azure.com
3. Zone has A record: cog-claims-dev-0bd2.privatelink.openai.azure.com = 10.10.3.5
4. Returns: 10.10.3.5 (private IP)
5. Pod connects to 10.10.3.5 → private endpoint → OpenAI via Azure backbone
```

**From outside the VNet (e.g. your laptop):**
```
1. Browser asks public DNS: "what is cog-claims-dev-0bd2.openai.azure.com?"
2. Public DNS returns CNAME: cog-claims-dev-0bd2.privatelink.openai.azure.com
3. Public DNS tries to resolve that CNAME: returns nothing (no public A record for privatelink)
4. Connection fails — intentional, because public_network_access_enabled = false
```

**To answer your specific question:**
- `https://cog-claims-dev-0bd2.openai.azure.com` — this is the **service hostname**, the name you call in your code
- `privatelink.openai.azure.com` — this is the **Private DNS Zone name**, a container for A records
- The actual private endpoint IP (`10.10.3.5`) is what traffic actually goes to
- `168.63.129.16` is Azure's internal DNS resolver — every Azure resource uses this as its DNS server automatically

**The DNS resolution chain:**
```
Pod calls: cog-claims-dev-0bd2.openai.azure.com
           ↓
Azure DNS (168.63.129.16) checks Private DNS Zone: privatelink.openai.azure.com
           ↓
Finds A record: cog-claims-dev-0bd2 = 10.10.3.5
           ↓
Returns: 10.10.3.5
           ↓
Pod TCP-connects to: 10.10.3.5
           ↓
Azure internal routing delivers to: Azure OpenAI
           ↓
Traffic never leaves Azure's network
```

### Why the zone must be linked to the VNet

The Private DNS Zone is not automatically visible to all VNets. You must create a **VNet link** from the zone to each VNet that needs to use it.

```hcl
resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  name                  = "link-${var.vnet_name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = var.vnet_id
}
```

Your platform creates links for both the hub VNet and the dev spoke VNet. If you forgot the spoke link, pods in AKS would still get the public IP — the private endpoint would exist but be unused.

---

## Summary of Key Mental Models

**NSG** = a bouncer at the subnet door. Checks source IP, destination IP, and port. Does not read the packet contents.

**WAF** = an x-ray machine at the building entrance. Reads every HTTP request looking for attack patterns.

**Firewall** = a customs checkpoint at the border. Inspects all traffic leaving the country (VNet), checks manifests (application rules), and knows which countries are dangerous (threat intelligence).

**Private Endpoint** = a private tunnel from your VNet directly to an Azure service. No internet involved.

**Private DNS Zone** = a phone book that lives inside your VNet. Overrides public phone books (public DNS) for specific names. Makes your code call the private tunnel instead of the public address.

**UDR** = a road sign redirecting all traffic through the checkpoint (Firewall). Without it, traffic finds its own way out without being inspected.

---

*Continue to Module 2 when you feel solid on these concepts.*
