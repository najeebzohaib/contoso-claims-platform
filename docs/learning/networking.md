# Module 1 — Azure Networking
## Based on the Contoso Claims Platform

**Time to complete:** 2-3 hours (read + exercises)
**Prerequisites:** Access to the Azure Portal and terminal with az CLI

---

## What You Will Understand After This Module

- Why we used hub-spoke instead of a flat network
- What VNets, subnets, peering, NSGs, and UDRs actually do
- How your specific IP ranges were chosen and why they cannot overlap
- What happens to a network packet from your laptop to the claims-api pod
- How to read your own Terraform networking code and understand every line

---

## Part 1 — The Problem Networking Solves

Before cloud, networks were physical. Routers and switches were in data centres. Security was enforced by physically separating machines.

In Azure, networking is software-defined. You create virtual networks that behave like physical ones but exist entirely as configuration. The key insight is: **Azure resources are not isolated from each other by default.** If you put two VMs in the same subscription with no network configuration, they can reach each other and the internet freely.

The Contoso platform uses networking to enforce three properties:

1. **Isolation** — the claims-api can only be reached from APIM, not directly from the internet
2. **Inspection** — all traffic leaving AKS passes through the firewall
3. **Private connectivity** — Azure OpenAI is reachable only from inside the VNet, not from the internet

Everything in the platform's network design serves one of these three goals.

---

## Part 2 — Virtual Networks (VNets)

A VNet is a private network in Azure. Think of it like buying a range of IP addresses and saying "these addresses exist inside Azure and belong to me."

**Your platform has three VNets:**

| VNet | CIDR | Purpose |
|------|------|---------|
| `vnet-claims-hub-uks` | 10.0.0.0/16 | Hub — shared security services |
| `vnet-claims-dev-uks` | 10.10.0.0/16 | Dev spoke — workloads |
| `vnet-claims-prod-uks` | 10.30.0.0/16 | Prod spoke — workloads |

### What does /16 mean?

CIDR notation `/16` means the first 16 bits of the address are fixed, and the remaining 16 bits are available for hosts. 

10.0.0.0/16 means: addresses from 10.0.0.0 to 10.0.255.255 = 65,536 addresses.

The three VNets use 10.0, 10.10, and 10.30 as their first two octets. They do not overlap. This is critical — VNet peering requires non-overlapping ranges. If hub used 10.0.0.0/16 and dev also used 10.0.0.0/16, they could never be peered.

### Why 10.x.x.x?

The IP ranges 10.0.0.0/8, 172.16.0.0/12, and 192.168.0.0/16 are defined by RFC1918 as private address space. They are never routed on the public internet. Using private ranges means there is no risk of your internal addresses conflicting with real internet addresses.

### What a VNet is NOT

A VNet is not a firewall. It does not block traffic by default (within the VNet). It is a container for IP addresses and a boundary for network policies. Isolation comes from NSGs, Firewall, and other controls applied within and around the VNet.

---

## Part 3 — Subnets

A subnet divides a VNet into smaller segments. Each subnet is a range of IPs within the VNet's range.

**Your dev spoke subnets:**

| Subnet | CIDR | Hosts | Purpose |
|--------|------|-------|---------|
| snet-claims-dev-uks-appgw | 10.10.4.0/24 | 251 | App Gateway WAF |
| snet-claims-dev-uks-apim | 10.10.5.0/24 | 251 | API Management |
| snet-claims-dev-uks-aks | 10.10.16.0/20 | 4,091 | AKS nodes and pods |
| snet-claims-dev-uks-pe | 10.10.3.0/24 | 251 | Private endpoints |
| snet-claims-dev-uks-dbw-pub | 10.10.32.0/24 | 251 | Databricks public |
| snet-claims-dev-uks-dbw-priv | 10.10.33.0/24 | 251 | Databricks private |

**Why give AKS a /20?**

AKS needs many more IP addresses than other subnets. Each AKS node gets an IP, and each pod gets an IP (with Azure CNI). 2 nodes × up to ~30 pods each = 60+ IPs just for pods. The /20 gives 4,091 usable addresses — plenty of room for the cluster to grow.

**Why separate subnets for each service?**

Subnets are the scope at which NSG rules are applied. By putting App Gateway in its own subnet, you can write a rule "allow internet traffic into the appgw subnet" without that rule affecting the apim subnet. If everything were in one subnet, you couldn't make that distinction.

**Why are Databricks subnets needed?**

Databricks VNet injection requires two subnets — a public subnet (for control plane communication) and a private subnet (for cluster workers). Databricks manages these subnets once they are created; you just provide the ranges.

---

## Part 4 — VNet Peering

VNet peering connects two VNets so resources in each can communicate using private IPs, as if they were in the same network.

**Your peerings:**

```
vnet-claims-hub-uks  <-->  vnet-claims-dev-uks
vnet-claims-hub-uks  <-->  vnet-claims-prod-uks
```

Dev and prod are NOT peered to each other. They only connect through the hub. This is intentional — if dev and prod were peered directly, a compromise of the dev environment could reach prod workloads.

**Two properties of peering:**

`allow_forwarded_traffic = true` — allows traffic that originated outside the VNet to be forwarded through the peering. This is required for the hub-spoke pattern because traffic from dev that is forwarded through the hub firewall counts as "forwarded traffic."

`allow_gateway_transit` / `use_remote_gateways` — allows a VPN or ExpressRoute gateway in the hub to be used by the spokes. You reserved the GatewaySubnet for this even though you haven't deployed the gateway yet.

**Peering is not transitive.** Dev and prod cannot talk to each other via the hub unless the hub explicitly routes traffic between them. This is a security property — the hub is a chokepoint, not a pass-through.

---

## Part 5 — Network Security Groups (NSGs)

An NSG is a list of rules that allow or deny network traffic. It operates at Layer 4 — IP addresses and ports. NSGs are attached to subnets and/or individual network interfaces.

**How NSG rules work:**

Each rule has: priority (100-4096), direction (inbound/outbound), protocol (TCP/UDP/Any), source, destination, port, and action (Allow/Deny).

Rules are evaluated in priority order. The first matching rule wins. At the end of every NSG is an implicit `DenyAll` rule at priority 65500.

**Critical NSG rules your platform required:**

For the **App Gateway subnet**, Azure requires:
```
Priority 100: Allow TCP 65200-65535 from GatewayManager (Azure health probes)
Priority 110: Allow Any from AzureLoadBalancer
```
Without the first rule, App Gateway cannot receive its health signals from Azure's infrastructure and stays in a failed state. This is one of those things you only learn by hitting the error.

For the **APIM subnet**, Azure requires:
```
Priority 100: Allow TCP 3443 from ApiManagement (management endpoint)
Priority 110: Allow TCP 6390 from AzureLoadBalancer (health probes)
```
APIM in Internal VNet mode requires the management endpoint (port 3443) to be reachable from the `ApiManagement` service tag. Without this, APIM provisioning fails with a cryptic 422 error. This is documented in your ADR-003.

**NSG vs Firewall — when to use which:**

| Requirement | Use |
|-------------|-----|
| Block specific ports between subnets | NSG |
| Block all traffic except explicitly allowed | NSG default deny |
| Inspect HTTP payloads for attacks | Azure Firewall or WAF |
| Detect port scans and lateral movement | Azure Firewall Premium IDPS |
| Log all network flows | NSG Flow Logs |
| Centralised egress control | Azure Firewall |

NSGs are free and fast. Azure Firewall costs ~£1,000/month. Use NSGs for basic subnet isolation and Firewall for centralised inspection of regulated workloads.

---

## Part 6 — User Defined Routes (UDRs)

By default, Azure routes traffic between subnets directly. A packet from the AKS subnet to the internet goes directly out — it does not pass through your firewall.

A UDR overrides this default routing. You create a route table and attach it to a subnet.

**Your route table (before it was deleted to save costs):**

```
Route: 0.0.0.0/0 (all traffic)
Next hop: VirtualAppliance
Next hop IP: 10.0.0.4 (Azure Firewall private IP)
```

This tells Azure: for any packet leaving the AKS subnet destined for any address, send it to 10.0.0.4 (the firewall) instead of routing it directly.

The result: every `apt-get install`, every `pip install`, every Azure API call from an AKS pod passes through the firewall before reaching the internet or Azure services. The firewall inspects it, applies rules, and either allows or denies it.

**Why you deleted the route table:** The UDR depends on the firewall existing. When you deleted the firewall to save costs, the route table still pointed to 10.0.0.4, which no longer existed. Traffic would black-hole. The route table had to go with the firewall.

**The relationship:**

```
AKS pod makes API call
  -> Packet leaves pod with destination: 52.x.x.x
  -> Azure looks up routing table for AKS subnet
  -> UDR says: send to 10.0.0.4 (firewall)
  -> Firewall checks application rules: is this FQDN allowed?
  -> If yes: firewall forwards to actual destination
  -> If no: firewall drops packet and logs the attempt
```

---

## Part 7 — Private DNS

When a pod calls `https://cog-claims-dev-0bd2.openai.azure.com`, it needs to resolve that hostname to an IP address. Normally this resolves to a public Azure IP. With private endpoints and Private DNS, it resolves to a private IP inside your VNet.

**Your Private DNS zones:**

| Zone | Service |
|------|---------|
| privatelink.openai.azure.com | Azure OpenAI |
| privatelink.vaultcore.azure.net | Key Vault |
| privatelink.azurecr.io | Container Registry |
| privatelink.search.windows.net | AI Search |
| privatelink.cognitiveservices.azure.com | Document Intelligence |

Each zone is linked to your hub and spoke VNets. When a resource inside the VNet resolves `cog-claims-dev-0bd2.openai.azure.com`, the DNS query goes to Azure's internal DNS (168.63.129.16), which checks the private DNS zone and returns the private endpoint IP (e.g. 10.10.3.5) instead of the public IP.

The result: traffic to Azure OpenAI from your AKS pods travels entirely within the Azure network. It never appears on the internet.

**Why DNS matters for security:** If the DNS zone were not configured correctly, pods would resolve OpenAI to its public IP and traffic would leave Azure's network — even though a private endpoint exists. The private endpoint only works if DNS resolves to the private IP. Both pieces are required.

---

## Part 8 — Reading Your Terraform Networking Code

Open the file `infra/modules/networking/main.tf` in your repository. You will see:

**The VNet resource:**
```hcl
resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name}"
  address_space       = [var.address_space]
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_servers         = var.dns_servers
  tags                = var.tags
}
```

`var.address_space` is set to `"10.10.0.0/16"` in the dev environment's `terraform.tfvars`. The module does not hardcode the range — it accepts it as a variable so the same module creates both dev (10.10) and prod (10.30) with different inputs.

**The subnet block:**
```hcl
resource "azurerm_subnet" "this" {
  for_each             = var.subnets
  name                 = "snet-${var.name}-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.cidr]
}
```

`for_each = var.subnets` iterates over a map. The dev environment passes a map like:
```hcl
subnets = {
  appgw = { cidr = "10.10.4.0/24" }
  apim  = { cidr = "10.10.5.0/24" }
  aks   = { cidr = "10.10.16.0/20" }
  pe    = { cidr = "10.10.3.0/24" }
}
```

Terraform creates one subnet resource for each map entry. `each.key` is "appgw", "apim" etc. `each.value.cidr` is the address range.

**The VNet peering:**
```hcl
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-spoke-to-hub"
  resource_group_name       = var.spoke_resource_group
  virtual_network_name      = var.spoke_vnet_name
  remote_virtual_network_id = var.hub_vnet_id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
  use_remote_gateways       = false
}
```

Peering must be created in both directions. Your `vnet_peering` module creates both the hub-to-spoke and spoke-to-hub peerings in a single module call so they cannot get out of sync.

---

## Exercises

Work through these in your terminal and Azure Portal. Do not skip them — reading without doing does not produce understanding.

**Exercise 1 — List your VNets and subnets**
```bash
az network vnet list \
  --resource-group rg-claims-dev-uks-001 \
  --query "[].{name:name, cidr:addressSpace.addressPrefixes[0]}" \
  -o table
```
Question: What CIDR does your dev VNet use? How many total IP addresses is that?

**Exercise 2 — List subnets and their ranges**
```bash
az network vnet subnet list \
  --resource-group rg-claims-dev-uks-001 \
  --vnet-name vnet-claims-dev-uks \
  --query "[].{name:name, cidr:addressPrefix}" \
  -o table
```
Question: Which subnet has the largest address range? Why does it need more addresses than the others?

**Exercise 3 — Check VNet peering status**
```bash
az network vnet peering list \
  --resource-group rg-claims-hub-uks-001 \
  --vnet-name vnet-claims-hub-uks \
  --query "[].{name:name, state:peeringState, remote:remoteVirtualNetwork.id}" \
  -o table
```
Question: What is the peering state? What does "Connected" mean vs "Initiated"?

**Exercise 4 — Inspect an NSG**
```bash
az network nsg show \
  --resource-group rg-claims-dev-uks-001 \
  --name nsg-claims-dev-uks-apim \
  --query "securityRules[].{name:name, priority:priority, direction:direction, access:access, port:destinationPortRange, source:sourceAddressPrefix}" \
  -o table
```
Question: Find the rule for port 3443. What source service tag does it use? What happens if this rule is missing?

**Exercise 5 — Trace a DNS resolution**
With AKS running and kubectl configured, exec into the claims-api pod:
```bash
kubectl exec -n claims \
  $(kubectl get pod -n claims -l app=claims-api -o jsonpath='{.items[0].metadata.name}') \
  -- nslookup cog-claims-dev-0bd2.openai.azure.com
```
Question: Does the IP address returned start with 10.x.x.x (private) or with a public IP? What does this tell you about whether the private endpoint DNS is working?

**Exercise 6 — Draw the network diagram**
On paper (or any tool), draw:
- The three VNets with their CIDR ranges
- The subnets inside the dev spoke with their CIDRs
- Arrows showing the peering connections
- Where the firewall sits (hub)
- The path a request takes from your browser to the claims-api pod

This exercise is the most important one. If you can draw it from memory, you understand it.

---

## Exam-Style Questions

These are the kinds of questions you will see on AZ-104 and AZ-305.

**Q1.** You need to peer two VNets. One uses address space 10.0.0.0/16 and the other uses 10.0.128.0/17. Can you peer them?

*Answer: No. The ranges overlap. 10.0.0.0/16 includes 10.0.128.0 through 10.0.255.255, which is the entire range of the second VNet. VNet peering requires completely non-overlapping address spaces.*

**Q2.** An AKS cluster is deployed in a subnet with a route table pointing all traffic to an Azure Firewall. A developer deploys a pod that calls an external API. The call fails. The firewall logs show the connection was attempted and denied. What is the most likely fix?

*Answer: Add an application rule to the firewall policy allowing the FQDN of the external API. The firewall default action is deny-all. Everything must be explicitly permitted.*

**Q3.** You have APIM in Internal VNet mode. A developer can reach the gateway URL from outside Azure but gets a 502. Inside the VNet the request succeeds. What is the likely cause?

*Answer: The App Gateway is not correctly configured to forward to the APIM backend. The App Gateway is the only external entry point for Internal APIM. Common causes: wrong backend pool IP, health probe misconfiguration, or missing backend HTTP settings.*

**Q4.** A company wants all internet-bound traffic from their Azure workloads to be inspected for threats. Which resource enforces this requirement?

*Answer: Azure Firewall with a route table (UDR) on workload subnets directing 0.0.0.0/0 to the firewall as a Virtual Appliance. NSGs alone cannot inspect traffic content — they only operate on IP/port.*

**Q5.** A private endpoint is created for Azure Key Vault but pods in AKS still connect to the public Key Vault IP. What is missing?

*Answer: The Private DNS Zone for `privatelink.vaultcore.azure.net` is either not created, not linked to the spoke VNet, or does not have an A record for the Key Vault. Without correct DNS resolution, the private endpoint exists but is never used.*

---

## Summary — What to Remember

| Concept | Your Platform | Key Point |
|---------|--------------|-----------|
| VNet | hub 10.0/16, dev 10.10/16 | Private address space, must not overlap for peering |
| Subnet | appgw, apim, aks, pe, dbw | NSGs are applied per subnet — reason for separation |
| Peering | hub↔dev, hub↔prod | Not transitive — dev and prod cannot talk directly |
| NSG | One per subnet | Layer 4 only — IP and port, not content |
| UDR | AKS subnet → firewall | Forces all egress through inspection |
| Private DNS | One zone per service | Makes private endpoints actually work |

---

*Next: Module 2 — The Security Stack (Firewall, WAF, APIM, Workload Identity, Private Endpoints)*
