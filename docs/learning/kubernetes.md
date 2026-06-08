# Module 3 — Kubernetes and AKS
## Based on the Contoso Claims Platform

**Time to complete:** 3-4 hours
**Builds on:** Module 1 (networking), Module 2b (Workload Identity)

---

## What You Will Understand After This Module

- What Kubernetes is and why it exists
- The core Kubernetes objects: pods, deployments, services, namespaces
- How AKS is Kubernetes managed by Azure
- How your claims-api is deployed and how traffic reaches it
- What the internal load balancer pattern means at the network level
- How Workload Identity integrates with Kubernetes at the pod level
- How to read your Kubernetes manifest files
- How to use kubectl to inspect and manage your cluster
- What happens when a pod crashes and how Kubernetes recovers
- AKS-specific features: node pools, Azure CNI, authorised IP ranges

---

## Part 1 — Why Kubernetes Exists

Before containers, applications were deployed directly onto VMs. Each VM ran one application (or a few). Problems:

- **Slow deployment:** provisioning a VM takes minutes. Deploying code to it takes more minutes.
- **Wasteful:** a VM with 8GB RAM running an app that uses 512MB wastes 7.5GB.
- **Hard to scale:** scaling means provisioning more VMs, configuring load balancers, updating DNS.
- **Inconsistent environments:** "works on my machine" — dev VM has different packages than prod VM.

Containers solved the consistency problem. A container packages the application and all its dependencies into a single image. The same image runs identically on any machine.

But containers introduced a new problem: how do you manage hundreds of containers across dozens of machines? How do you ensure a container is always running? How do you route traffic to the right container? How do you roll out a new version without downtime?

Kubernetes solves container orchestration. It answers:
- Which machine should this container run on? (scheduling)
- What happens if the container crashes? (self-healing)
- How do I expose this container to network traffic? (services)
- How do I roll out a new version safely? (deployments)
- How do I pass configuration to containers? (ConfigMaps and Secrets)

📖 [Kubernetes overview](https://kubernetes.io/docs/concepts/overview/)
📖 [Why Kubernetes](https://kubernetes.io/docs/concepts/overview/#why-you-need-kubernetes-and-what-can-it-do)

---

## Part 2 — The Kubernetes Architecture

A Kubernetes cluster has two types of components:

### Control Plane (the brain)

The control plane makes decisions about the cluster. In AKS, Microsoft manages the control plane — you never see these VMs.

**API Server** — the front door to Kubernetes. Every operation (kubectl command, Terraform resource, Helm chart) sends requests to the API server. It validates and processes them.

**etcd** — a distributed key-value store that holds the entire cluster state. Every resource you create (pod, deployment, service) is stored in etcd. If etcd is lost, the cluster state is lost.

**Scheduler** — watches for new pods with no assigned node and picks the best node to run them on. Considers: available CPU/memory, node affinity rules, taints and tolerations.

**Controller Manager** — runs background loops (controllers) that watch the cluster state and make it match the desired state. The Deployment controller watches deployments and creates/deletes pods to match the desired replica count.

### Worker Nodes (where your code runs)

Each node is a VM (in AKS, an Azure VM). Your platform uses Standard_D4s_v5 nodes (4 vCPU, 16GB RAM).

**kubelet** — the agent running on each node. Receives pod specifications from the API server and ensures the described containers are running.

**kube-proxy** — maintains network rules on each node. Implements the Service abstraction by creating iptables (or eBPF) rules that redirect traffic to pod IPs.

**Container runtime** — runs the actual containers. AKS uses containerd.

```
Control Plane (managed by Azure in AKS)
  ├── API Server        (kubectl talks to this)
  ├── etcd              (stores cluster state)
  ├── Scheduler         (decides which node runs a pod)
  └── Controller Manager (reconciles desired vs actual state)

Worker Nodes (your Azure VMs)
  ├── Node 1 (aks-system-38701737-vmss000012)
  │     ├── kubelet
  │     ├── kube-proxy
  │     └── Pods: coredns, konnectivity-agent, claims-api (replica 1)
  └── Node 2 (aks-system-38701737-vmss000013)
        ├── kubelet
        ├── kube-proxy
        └── Pods: metrics-server, ama-logs-rs, claims-api (replica 2)
```

📖 [Kubernetes components](https://kubernetes.io/docs/concepts/overview/components/)
📖 [AKS architecture](https://learn.microsoft.com/en-us/azure/aks/core-aks-concepts)

---

## Part 3 — Pods

A pod is the smallest deployable unit in Kubernetes. It contains one or more containers that share:
- Network namespace (same IP address, same ports)
- Storage volumes
- Lifecycle (they start and stop together)

Most pods contain one container. Multi-container pods are used for sidecar patterns (e.g. a log shipper container alongside the main application).

**Your claims-api pod:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: claims-api-7bc8dd8c56-79zxj
  namespace: claims
  labels:
    app: claims-api
    azure.workload.identity/use: "true"   # enables workload identity
spec:
  serviceAccountName: claims-api-sa       # the SA with workload identity annotation
  containers:
  - name: claims-api
    image: acrclaimsdev0bd2.azurecr.io/claims-api:v9
    ports:
    - containerPort: 8000
    env:
    - name: AZURE_CLIENT_ID
      value: "780d14ad-dc71-40e9-a7fe-72186d7c54d5"
    resources:
      requests:
        cpu: "250m"       # 0.25 vCPU guaranteed
        memory: "256Mi"   # 256MB RAM guaranteed
      limits:
        cpu: "500m"       # 0.5 vCPU maximum
        memory: "512Mi"   # 512MB RAM maximum
```

### Pods are ephemeral

This is the most important thing to understand about pods: **they are temporary.** A pod can be:
- Killed by Kubernetes when a node runs low on memory
- Rescheduled to a different node after a node failure
- Replaced when a new version is deployed
- Terminated when you scale down

Each time a pod is created it gets a new IP address. You cannot rely on a pod's IP being stable. This is why Services exist (Part 5).

### Pod IP addresses in your platform

Pods get IPs from the pod CIDR: `192.168.0.0/16`. Your pod's IP was `192.168.1.21`. After a restart it might be `192.168.2.45`. The pod IP is only valid for the lifetime of that pod.

📖 [Kubernetes pods](https://kubernetes.io/docs/concepts/workloads/pods/)
📖 [Pod lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)

---

## Part 4 — Deployments

You never create pods directly in production. You create a Deployment, which manages pods for you.

A Deployment says: "I want 3 replicas of this pod specification running at all times."

The Deployment controller continuously reconciles:
- **Desired state:** 3 replicas of claims-api:v9
- **Actual state:** what is currently running

If one pod crashes, the controller creates a new one. If you scale to 5 replicas, it creates 2 more. If you update the image to v10, it rolls out the new pods gradually.

**Your claims-api Deployment:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: claims-api
  namespace: claims
spec:
  replicas: 3                    # desired pod count
  selector:
    matchLabels:
      app: claims-api            # manages pods with this label
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1          # at most 1 pod unavailable during update
      maxSurge: 1                # at most 1 extra pod during update
  template:                      # pod specification for each replica
    metadata:
      labels:
        app: claims-api
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: claims-api-sa
      containers:
      - name: claims-api
        image: acrclaimsdev0bd2.azurecr.io/claims-api:v9
```

### Rolling Updates

When you change the image from v9 to v10 (`kubectl set image deployment/claims-api claims-api=...v10`):

```
Start: 3× v9 running

Step 1: Create 1× v10 pod (maxSurge=1 allows 4 total)
        Wait for v10 pod to become Ready
Step 2: Delete 1× v9 pod (now 3 total: 2×v9 + 1×v10)
Step 3: Create another v10 pod
        Wait for it to become Ready
Step 4: Delete another v9 pod
Step 5: Create final v10 pod
        Wait for Ready
Step 6: Delete final v9 pod

End: 3× v10 running, zero downtime
```

`maxUnavailable: 1` ensures at least 2 pods are always serving traffic during the update. `maxSurge: 1` limits the extra resource usage to 1 additional pod.

### What happened when you scaled to 0

When you ran `kubectl scale deployment claims-api -n claims --replicas=0`, the Deployment set desired replicas to 0. The controller terminated all pods. No pods running = no VM CPU/memory used for your workload (though AKS nodes themselves still run).

📖 [Kubernetes deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
📖 [Rolling update strategy](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-update-deployment)

---

## Part 5 — Services

A Service gives a stable network endpoint to a set of pods. It solves the pod IP instability problem.

Instead of calling a pod directly at `192.168.1.21:8000` (which changes every time the pod restarts), you call the Service at a stable ClusterIP or external IP.

### How Services find pods: label selectors

A Service does not reference pods by name. It uses label selectors:

```yaml
kind: Service
spec:
  selector:
    app: claims-api    # route traffic to pods with this label
```

Any pod with the label `app: claims-api` receives traffic. When pods are replaced (new IP, same label), the Service automatically routes to the new pods. The Service IP never changes.

### Service types

**ClusterIP (default)** — gives the service a stable IP inside the cluster. Only reachable from within the cluster. Used for service-to-service communication.

```
claims-api Service ClusterIP: 172.16.62.187
  → routes to pods: 192.168.1.21, 192.168.2.45, 192.168.3.12
  → reachable from: any pod in the cluster
  → not reachable from: outside the cluster
```

**LoadBalancer** — provisions an external load balancer. In AKS on Azure, this creates an Azure Load Balancer. Your claims-api uses this type with the internal annotation.

**NodePort** — exposes the service on a port on every node's IP. Less common in AKS.

### Your claims-api Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: claims-api
  namespace: claims
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  selector:
    app: claims-api
  ports:
  - port: 80           # port the service listens on
    targetPort: 8000   # port on the pod container
    protocol: TCP
```

The annotation `azure-load-balancer-internal: "true"` tells AKS to create an Azure Internal Load Balancer (ILB) instead of a public one. The ILB gets IP `10.10.16.6` — a private IP in the AKS subnet.

**The port mapping:**
```
APIM calls: http://10.10.16.6:80
  → Azure ILB receives on port 80
  → Forwards to one of the pod IPs on port 8000
  → FastAPI listens on port 8000 inside the container
```

Port 80 on the service, port 8000 on the container. They do not have to match.

### kube-proxy and how traffic actually flows

When APIM sends a packet to `10.10.16.6:80`, here is what actually happens:

1. Packet arrives at the Azure Internal Load Balancer
2. ILB selects one of the healthy AKS nodes
3. Packet arrives at that node's network interface
4. kube-proxy has set up iptables rules: traffic for `10.10.16.6:80` → forward to one of {`192.168.1.21:8000`, `192.168.2.45:8000`, `192.168.3.12:8000`}
5. iptables randomly selects one pod IP (this is the load balancing)
6. Packet arrives at the pod

📖 [Kubernetes services](https://kubernetes.io/docs/concepts/services-networking/service/)
📖 [AKS internal load balancer](https://learn.microsoft.com/en-us/azure/aks/internal-lb)
📖 [Azure load balancer with AKS](https://learn.microsoft.com/en-us/azure/aks/load-balancer-standard)

---

## Part 6 — Namespaces

Namespaces divide a single cluster into virtual sub-clusters. Resources in different namespaces are isolated from each other by default.

**Your cluster's namespaces:**

| Namespace | Purpose |
|-----------|---------|
| `default` | Default namespace — used if you do not specify one |
| `kube-system` | Kubernetes system components (coredns, konnectivity, metrics-server) |
| `kube-public` | Publicly readable resources (rarely used) |
| `kube-node-lease` | Node heartbeat objects |
| `claims` | Your application — claims-api |

**Why put claims-api in its own namespace?**

1. **Isolation:** RBAC can be scoped to a namespace. A developer with access to the `claims` namespace cannot accidentally modify `kube-system` components.

2. **Resource quotas:** you can limit total CPU/memory usage per namespace.

3. **Network policies:** Kubernetes NetworkPolicy rules can restrict traffic between namespaces.

4. **Workload Identity:** the Federated Identity Credential subject includes the namespace: `system:serviceaccount:claims:claims-api-sa`. A service account in a different namespace with the same name would not match this credential.

5. **Clarity:** `kubectl get pods -n claims` shows only your application pods, not all the system pods.

📖 [Kubernetes namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)
📖 [Namespaces walkthrough](https://kubernetes.io/docs/tasks/administer-cluster/namespaces-walkthrough/)

---

## Part 7 — AKS: Kubernetes Managed by Azure

AKS is Azure's managed Kubernetes service. "Managed" means:

**Azure manages:** the control plane (API server, etcd, scheduler, controller manager), control plane upgrades, control plane high availability, control plane monitoring.

**You manage:** worker nodes (VM size, count, OS patches), node pool upgrades, application deployments, networking configuration.

**You pay for:** worker nodes (the VMs), not the control plane (free in AKS).

### Your AKS configuration

```hcl
resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${var.name}"
  kubernetes_version  = "1.34.7"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "aks-${var.name}"

  default_node_pool {
    name       = "system"
    node_count = 2
    vm_size    = "Standard_D4s_v5"   # 4 vCPU, 16GB RAM
    os_disk_size_gb = 128

    vnet_subnet_id = var.aks_subnet_id   # 10.10.16.0/20

    zones = ["1", "2", "3"]              # zone redundant nodes
  }

  network_profile {
    network_plugin    = "azure"          # Azure CNI
    network_plugin_mode = "overlay"      # CNI Overlay mode
    service_cidr      = "172.16.0.0/16"
    dns_service_ip    = "172.16.0.10"
  }

  oidc_issuer_enabled       = true       # required for Workload Identity
  workload_identity_enabled = true       # enables the webhook

  api_server_access_profile {
    authorized_ip_ranges = var.authorized_ip_ranges   # IP allowlist
  }
}
```

### Azure CNI Overlay

AKS supports several networking modes. Your platform uses **Azure CNI Overlay**.

**Why CNI Overlay?**

The original Azure CNI assigns pod IPs directly from the VNet subnet. With 2 nodes × 30 pods = 60 pod IPs, you need a large enough subnet. This depletes VNet address space quickly.

CNI Overlay uses a separate overlay network for pods (192.168.0.0/16) that does not consume VNet address space. Pod-to-pod traffic within the cluster uses this overlay. Only traffic leaving the cluster (to Azure services, internet, other subnets) uses real VNet IPs.

**The tradeoff:** Pod IPs (192.168.x.x) are not directly routable from outside the cluster. You cannot connect from another VM in the VNet directly to a pod IP. You must go through a Service. For your architecture this is fine — all external access goes through the Internal Load Balancer Service.

📖 [AKS overview](https://learn.microsoft.com/en-us/azure/aks/intro-kubernetes)
📖 [AKS networking concepts](https://learn.microsoft.com/en-us/azure/aks/concepts-network)
📖 [Azure CNI Overlay](https://learn.microsoft.com/en-us/azure/aks/azure-cni-overlay)
📖 [AKS node pools](https://learn.microsoft.com/en-us/azure/aks/use-multiple-node-pools)

---

## Part 8 — Workload Identity at the Kubernetes Level

Module 2b explained Workload Identity conceptually. Here is the Kubernetes side in detail.

### ServiceAccount

A ServiceAccount is a Kubernetes identity for a pod. By default every pod uses the `default` ServiceAccount in its namespace — a minimal identity with no Azure permissions.

Your claims-api uses a dedicated ServiceAccount:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: claims-api-sa
  namespace: claims
  annotations:
    azure.workload.identity/client-id: "780d14ad-dc71-40e9-a7fe-72186d7c54d5"
```

The annotation tells the Workload Identity webhook which Azure Managed Identity to use when exchanging tokens.

### The Webhook

`azure-wi-webhook-controller-manager` — you saw this in your AKS workloads list (2/2 Ready in kube-system). This is the Workload Identity webhook.

When a pod is created with `azure.workload.identity/use: "true"`, the webhook mutates (modifies) the pod specification before it is stored in etcd:

```yaml
# What you specified:
spec:
  serviceAccountName: claims-api-sa
  containers:
  - name: claims-api
    image: ...

# What the webhook adds:
spec:
  serviceAccountName: claims-api-sa
  containers:
  - name: claims-api
    image: ...
    env:
    - name: AZURE_CLIENT_ID
      value: "780d14ad-dc71-40e9-a7fe-72186d7c54d5"
    - name: AZURE_TENANT_ID
      value: "your-tenant-id"
    - name: AZURE_FEDERATED_TOKEN_FILE
      value: "/var/run/secrets/azure/tokens/azure-identity-token"
    volumeMounts:
    - name: azure-identity-token
      mountPath: /var/run/secrets/azure/tokens
      readOnly: true
  volumes:
  - name: azure-identity-token
    projected:
      sources:
      - serviceAccountToken:
          audience: api://AzureADTokenExchange
          expirationSeconds: 86400    # token refreshed every 24 hours
          path: azure-identity-token
```

You did not write most of this YAML — the webhook injected it automatically. This is why Workload Identity is transparent to the application code — the SDK just reads environment variables and a file that Kubernetes populates.

📖 [AKS Workload Identity](https://learn.microsoft.com/en-us/azure/aks/workload-identity-deploy-cluster)
📖 [Kubernetes service accounts](https://kubernetes.io/docs/concepts/security/service-accounts/)
📖 [Kubernetes admission webhooks](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/)

---

## Part 9 — ConfigMaps and Secrets

Pods need configuration (API endpoints, feature flags, timeouts) and sensitive values (though Workload Identity eliminates most secrets). Kubernetes provides two resources for this.

### ConfigMap

Non-sensitive configuration stored as key-value pairs:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: claims-api-config
  namespace: claims
data:
  OPENAI_ENDPOINT: "https://cog-claims-dev-0bd2.openai.azure.com"
  OPENAI_DEPLOYMENT: "gpt-4o"
  LOG_LEVEL: "INFO"
```

Mounted into pods as environment variables or as files.

### Secret

Base64-encoded (not encrypted by default) sensitive values. In AKS you can enable encryption at rest for etcd, which does encrypt Secrets.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: claims-api-secret
  namespace: claims
type: Opaque
data:
  APIM_KEY: "c3VwZXJzZWNyZXQ="   # base64 encoded value
```

**Important:** base64 is encoding, not encryption. Anyone with access to the Secret can decode it with `echo "c3VwZXJzZWNyZXQ=" | base64 -d`. Kubernetes Secrets require RBAC to protect access.

**Your platform uses Workload Identity instead of Secrets for Azure service credentials.** The only time Secrets would be needed is for non-Azure credentials (third-party APIs, database passwords that cannot use managed identity).

📖 [Kubernetes ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
📖 [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
📖 [AKS Secret Store CSI driver](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver)

---

## Part 10 — Resource Requests and Limits

Every container in your platform specifies resource requests and limits:

```yaml
resources:
  requests:
    cpu: "250m"      # 0.25 vCPU
    memory: "256Mi"  # 256 MiB
  limits:
    cpu: "500m"      # 0.5 vCPU
    memory: "512Mi"  # 512 MiB
```

**Requests** — the amount of CPU/memory the scheduler guarantees. The scheduler only places a pod on a node that has at least this much available. With 3 replicas:
- Total CPU requested: 3 × 250m = 750m (0.75 vCPU)
- Total memory requested: 3 × 256Mi = 768Mi

Your nodes have 4 vCPU and 16GB RAM each — plenty of headroom.

**Limits** — the maximum the container can use. If a container tries to use more CPU than its limit, it is throttled (slowed down, not killed). If it tries to use more memory than its limit, it is killed (OOMKilled — Out Of Memory Killed) and restarted by the Deployment controller.

**Why both matter:**
- Without requests: scheduler cannot make good placement decisions, pods compete for resources
- Without limits: one runaway pod can consume all node resources, starving other pods
- Without either: Kubernetes defaults lead to unpredictable behaviour at scale

📖 [Resource requests and limits](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
📖 [AKS resource management best practices](https://learn.microsoft.com/en-us/azure/aks/developer-best-practices-resource-management)

---

## Part 11 — What Happens When a Pod Crashes

This demonstrates the self-healing property of Kubernetes.

```
Scenario: claims-api pod crashes (unhandled exception, OOM, etc.)

T=0:00  Pod status: Running
T=0:01  Container exits with code 1
T=0:01  kubelet detects container exited
T=0:01  kubelet reports pod status: CrashLoopBackOff (if repeated)
T=0:02  Deployment controller notices: actual replicas (2) < desired (3)
T=0:02  Controller creates new pod spec, submits to API server
T=0:03  Scheduler assigns new pod to a node
T=0:04  kubelet on that node pulls the container image (cached)
T=0:05  Container starts, FastAPI initialises
T=0:08  Readiness probe passes: pod marked Ready
T=0:08  Service adds new pod to its endpoint list
T=0:08  Traffic routes to new pod
```

Total recovery time: ~8 seconds. Zero manual intervention.

### Restart policies and CrashLoopBackOff

If a pod keeps crashing, Kubernetes applies exponential backoff to restarts:
- 1st restart: immediate
- 2nd restart: 10 seconds
- 3rd restart: 20 seconds
- 4th restart: 40 seconds
- ... up to 5 minutes between restarts

This is CrashLoopBackOff. It prevents a broken pod from hammering the system with rapid restart cycles. The pod status shows `CrashLoopBackOff` and `RESTARTS: 4` when this happens.

```bash
# Check pod restart count and status
kubectl get pods -n claims

# See why a pod crashed
kubectl describe pod -n claims {pod-name}
# Look for: Last State, Exit Code, Events section

# See the container logs from the crashed pod
kubectl logs -n claims {pod-name} --previous
```

📖 [Pod restart policies](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#restart-policy)
📖 [Debugging pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)

---

## Part 12 — Health Checks: Readiness and Liveness Probes

Kubernetes uses probes to determine if a pod is healthy and ready to receive traffic.

### Liveness probe

"Is this container still alive? Should Kubernetes restart it?"

If a liveness probe fails repeatedly, Kubernetes kills and restarts the container. Used to detect:
- Deadlocks (container is running but unresponsive)
- Memory leaks that cause the app to stop responding

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 10    # wait 10s before first probe (app startup time)
  periodSeconds: 30          # probe every 30 seconds
  failureThreshold: 3        # restart after 3 consecutive failures
```

### Readiness probe

"Is this container ready to receive traffic?"

If a readiness probe fails, Kubernetes removes the pod from the Service endpoint list — no more traffic is sent to it. Used to:
- Delay traffic until the app has fully initialised
- Temporarily stop traffic during a maintenance window or overload

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 5
  periodSeconds: 10
  failureThreshold: 3
```

### Your /health endpoint

Your FastAPI app has a `/health` endpoint:
```python
@app.get("/health")
def health():
    return {"status": "healthy", "version": "1.0.0"}
```

Both the Kubernetes readiness probe and the App Gateway health probe call this endpoint. If it returns 200, everything is healthy. If the app is crashing or overloaded, this endpoint fails first, removing the pod from load balancing before clients see errors.

📖 [Configure liveness and readiness probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
📖 [AKS health monitoring](https://learn.microsoft.com/en-us/azure/aks/monitor-aks)

---

## Part 13 — Node Pools and VM Scale Sets

In AKS, nodes are grouped into node pools. Each node pool is backed by an Azure Virtual Machine Scale Set (VMSS).

**Your platform has one node pool:**

```
Node pool: system
  VM size: Standard_D4s_v5
  Node count: 2
  OS: Ubuntu Linux
  Mode: System (runs kube-system components)
  Zones: 1, 2, 3 (zone redundant)
```

### System vs User node pools

**System node pool:** runs critical Kubernetes components (coredns, konnectivity-agent, metrics-server). Marked with a taint that prevents user workloads from running here unless they explicitly tolerate it.

**User node pool:** for your application workloads. In a production deployment you would add a separate user node pool so your application pods don't compete with system pods for resources.

Your platform runs claims-api on the system node pool — acceptable for a learning environment, not ideal for production.

### Stopping and starting AKS

```bash
# Stop AKS (deallocates node VMs, stops billing for compute)
az aks stop --resource-group rg-claims-dev-uks-001 --name aks-claims-dev-uks

# Start AKS (reallocates VMs, restores cluster state from etcd)
az aks start --resource-group rg-claims-dev-uks-001 --name aks-claims-dev-uks
```

When AKS stops, the node VMs are deallocated (no VM billing). The control plane remains (no charge in AKS). The cluster state (all your deployments, services, pods) is preserved in etcd. When you start again, Kubernetes reschedules all pods onto the new nodes.

This is why your pods were in Pending state after restarting — the nodes were not yet ready to accept them. Once the nodes became Ready, the scheduler placed the pods and they started running.

📖 [AKS node pools](https://learn.microsoft.com/en-us/azure/aks/use-multiple-node-pools)
📖 [Stop and start an AKS cluster](https://learn.microsoft.com/en-us/azure/aks/start-stop-cluster)
📖 [AKS system node pools](https://learn.microsoft.com/en-us/azure/aks/use-system-pools)

---

## Part 14 — kubectl: The Command Line for Kubernetes

kubectl is the CLI for interacting with Kubernetes. Every kubectl command sends a request to the API server.

### Essential commands for your platform

```bash
# Set cluster credentials (run after AKS start or node recreation)
az aks get-credentials \
  --resource-group rg-claims-dev-uks-001 \
  --name aks-claims-dev-uks \
  --overwrite-existing

# List all pods in the claims namespace
kubectl get pods -n claims

# List pods with more detail (node, IP, status)
kubectl get pods -n claims -o wide

# Describe a pod (events, resource usage, probe status)
kubectl describe pod -n claims {pod-name}

# View pod logs (live)
kubectl logs -n claims {pod-name} -f

# View logs from a crashed pod
kubectl logs -n claims {pod-name} --previous

# Execute a command inside a running pod
kubectl exec -n claims {pod-name} -- curl http://localhost:8000/health

# Open an interactive shell inside a pod
kubectl exec -n claims {pod-name} -it -- /bin/bash

# List all services
kubectl get svc -n claims

# List all services with external IPs
kubectl get svc -n claims -o wide

# Scale a deployment
kubectl scale deployment claims-api -n claims --replicas=3

# Check rollout status
kubectl rollout status deployment/claims-api -n claims

# Roll back a deployment
kubectl rollout undo deployment/claims-api -n claims

# Port-forward (test API locally without going through App Gateway)
kubectl port-forward -n claims svc/claims-api 8080:80
# Then: curl http://localhost:8080/health
```

### Reading kubectl output

```
NAME                          READY   STATUS    RESTARTS   AGE
claims-api-7bc8dd8c56-79zxj   1/1     Running   0          16m
```

- `NAME` — pod name = deployment name + ReplicaSet hash + pod hash
- `READY` — `1/1` means 1 container running out of 1 total (your pod has 1 container)
- `STATUS` — `Running` is healthy. `Pending` = waiting for a node. `CrashLoopBackOff` = crashing repeatedly.
- `RESTARTS` — how many times this pod has been restarted. Non-zero means it has crashed at least once.
- `AGE` — how long since this pod was created

📖 [kubectl cheat sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
📖 [kubectl reference](https://kubernetes.io/docs/reference/kubectl/)

---

## Part 15 — Reading Your Kubernetes Manifests

Your manifests are in `src/claims-api/k8s/`. Let's read through them.

### deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: claims-api
  namespace: claims
spec:
  replicas: 1                      # scaled to 1 for demos (was 3)
  selector:
    matchLabels:
      app: claims-api
  template:
    metadata:
      labels:
        app: claims-api
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: claims-api-sa
      containers:
      - name: claims-api
        image: acrclaimsdev0bd2.azurecr.io/claims-api:v9
        ports:
        - containerPort: 8000
        env:
        - name: AZURE_CLIENT_ID
          value: "780d14ad-dc71-40e9-a7fe-72186d7c54d5"
        - name: OPENAI_ENDPOINT
          value: "https://cog-claims-dev-0bd2.openai.azure.com"
        - name: OPENAI_DEPLOYMENT
          value: "gpt-4o"
```

Key things to note:
- `azure.workload.identity/use: "true"` on the pod template label — this triggers the webhook
- `serviceAccountName: claims-api-sa` — must match the SA with the workload identity annotation
- `AZURE_CLIENT_ID` — the webhook also injects this but having it explicit in env makes debugging easier
- `containerPort: 8000` — this is informational only, not a firewall rule. The container listens on 8000 regardless of whether you declare it.

### service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: claims-api
  namespace: claims
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  selector:
    app: claims-api
  ports:
  - name: http
    port: 80
    targetPort: 8000
    protocol: TCP
```

This is the resource that creates the Azure Internal Load Balancer at `10.10.16.6`. The annotation is what makes it internal — without it, AKS would create a public load balancer with a public IP.

📖 [Kubernetes manifest reference](https://kubernetes.io/docs/reference/kubernetes-api/)
📖 [AKS deployment best practices](https://learn.microsoft.com/en-us/azure/aks/developer-best-practices-pod-security)

---

## Summary

| Concept | Your Platform | Key Point |
|---------|--------------|-----------|
| Pod | claims-api-7bc8dd8c56-xxx | Ephemeral — IP changes on restart |
| Deployment | claims-api, replicas=1-3 | Manages desired pod count, handles rolling updates |
| Service | claims-api, LoadBalancer | Stable endpoint — 10.10.16.6 (internal LB) |
| Namespace | claims | Isolates application from system components |
| ServiceAccount | claims-api-sa | Kubernetes identity for Workload Identity |
| Node pool | system, 2× D4s_v5 | Azure VMSS — zone redundant across zones 1,2,3 |
| Azure CNI Overlay | pod CIDR 192.168.0.0/16 | Pod IPs not routable from outside cluster |
| Workload Identity webhook | azure-wi-webhook | Mutates pod spec to inject token and env vars |
| Liveness probe | GET /health | Restarts container if it stops responding |
| Readiness probe | GET /health | Removes pod from load balancing if not ready |

---

## Documentation Reference

📖 [Kubernetes documentation](https://kubernetes.io/docs/home/)
📖 [Kubernetes concepts](https://kubernetes.io/docs/concepts/)
📖 [Kubernetes pods](https://kubernetes.io/docs/concepts/workloads/pods/)
📖 [Kubernetes deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
📖 [Kubernetes services](https://kubernetes.io/docs/concepts/services-networking/service/)
📖 [Kubernetes namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)
📖 [kubectl cheat sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
📖 [AKS documentation hub](https://learn.microsoft.com/en-us/azure/aks/)
📖 [AKS core concepts](https://learn.microsoft.com/en-us/azure/aks/core-aks-concepts)
📖 [AKS networking concepts](https://learn.microsoft.com/en-us/azure/aks/concepts-network)
📖 [Azure CNI Overlay](https://learn.microsoft.com/en-us/azure/aks/azure-cni-overlay)
📖 [AKS internal load balancer](https://learn.microsoft.com/en-us/azure/aks/internal-lb)
📖 [AKS Workload Identity](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
📖 [AKS node pools](https://learn.microsoft.com/en-us/azure/aks/use-multiple-node-pools)
📖 [Stop and start AKS cluster](https://learn.microsoft.com/en-us/azure/aks/start-stop-cluster)
📖 [AKS best practices](https://learn.microsoft.com/en-us/azure/aks/best-practices)

---

## AZ-305 Exam Alignment

**Domain 4: Design Infrastructure Solutions (35-40%)**
- Design solutions for containerised applications
- Design compute solutions

📖 [AZ-305 exam skills outline](https://learn.microsoft.com/en-us/credentials/certifications/exams/az-305/)
📖 [AKS for AZ-305 — container solutions](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/containers/aks/baseline-aks)
📖 [Choose a compute service — decision guide](https://learn.microsoft.com/en-us/azure/architecture/guide/technology-choices/compute-decision-tree)

---

*Next: Module 4 — Azure AI Services (OpenAI, Document Intelligence, AI Search)*
