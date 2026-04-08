# New Presentation Slide: K3s Quick Start

## Slide Title: "Getting Started: Boot K3s with cert-manager & OTel in 10 Minutes"

### Slide Content (as text to add to presentation)

---

## The 3-Step Quick Start

#### Step 1: Boot K3s (3 minutes)
```bash
make k3s
```
- Starts local Docker registry (localhost:5000)
- Vagrant boots 4GB/3CPU VM with k3s
- Extracts kubeconfig to ~/.kube/config-k3s
- k3s = lightweight K8s in a single binary, uses containerd not Docker

#### Step 2: Deploy Core Infrastructure (5 minutes)
```bash
make all
```
Creates automatically:
- **cert-manager** — Watches Certificate objects, auto-issues TLS certs
- **Root CA Chain** — 10-year root CA + intermediate (5-year) for demos
- **OTel Collectors** — DaemonSet (node-level metrics) + Deployment (cluster-level)

All TLS certificates are now trusted inside k3s — no manual cert generation, no expiry tracking, no renewal headaches.

#### Step 3: Deploy PostgreSQL + Workload (3 minutes)
```bash
make postgres
```
Helm chart creates:
- StatefulSet: postgres-0 (stable ordinal name, own PVC)
- ConfigMap: init scripts + workload generator
- Service: headless DNS (postgres-0.postgres.databases.svc)
- Job: initializes e-commerce schema

---

## Architecture After Quick Start

```
┌─────────────────────────────────────────────┐
│  K3s Cluster (192.168.121.90)               │
├─────────────────────────────────────────────┤
│  otel-monitoring                            │
│  ├─ DaemonSet: otel-node-collector          │
│  │  └─ kubeletstats (pod/container metrics) │
│  │  └─ hostmetrics (OS metrics)             │
│  │  └─ filelog (container logs)             │
│  └─ Deployment: otel-cluster-collector      │
│     └─ k8s_cluster (pod phases, events)     │
│     └─ postgresql (query stats)             │
│                                              │
│  databases                                  │
│  └─ StatefulSet: postgres-0                 │
│     └─ PVC: postgres-0 (10Gi)               │
│                                              │
│  cert-manager                               │
│  └─ Controller + CA chain (3 issuers)       │
│                                              │
│  kube-system                                │
│  └─ Traefik, CoreDNS, metrics-server        │
└─────────────────────────────────────────────┘
```

---

## What Each Component Does

### cert-manager — Automatic TLS

Before cert-manager, you'd:
- Generate certs manually with openssl
- Store in Secrets manually
- Track expiry dates
- Renew on a schedule

With cert-manager:
- Declare one Certificate object → auto-issued
- Stored in Secret automatically
- Renewed automatically 30 days before expiry
- Never expires (from app perspective)

```yaml
# That's all you declare. cert-manager does the rest forever.
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: web-shop-cert
spec:
  secretName: web-shop-tls
  issuerRef:
    name: intermediate-ca-issuer
  dnsNames:
  - web-shop.k3s.local
```

### Reflector (Optional, shown on separate slide if needed)

If using reflector (not in core make all):
- Watches Secrets in one namespace
- Mirrors them to other namespaces automatically
- One source of truth for shared certs

---

## Key Concepts in These 3 Steps

| Concept | Why It Matters |
|---------|----------------|
| **k3s** | Same K8s concepts, runs on a laptop, uses containerd not Docker |
| **Local Registry** | k3s containerd doesn't share Docker's image store — explicit push required |
| **Helm Charts** | 3 commands create 20+ YAML files automatically |
| **StatefulSet** | postgres-0 always gets the same PVC, survives pod restarts with same identity |
| **DaemonSet** | OTel node collector runs on every node (automatic, one pod per node) |
| **cert-manager** | Removes manual TLS ceremony — declare once, renewed forever |
| **OTel Collectors** | Collect metrics/logs from K8s + apps, export to external Checkmk |

---

## Useful Commands During Setup

```bash
# Monitor deployment progress
make status

# Watch pods come up in real-time
kubectl get pods -A -w

# Check if all services are ready
kubectl get svc -A

# View cert-manager certificates
kubectl get certificate -A

# Inspect OTel collector config
kubectl get configmap -n otel-monitoring -o yaml | grep -A50 "config.yaml"

# Test OTel collector health
kubectl exec -n otel-monitoring ds/otel-node-opentelemetry-collector -- \
  wget -qO- localhost:13133

# View PostgreSQL status
kubectl describe statefulset postgres -n databases
kubectl get pvc -n databases
```

---

## Troubleshooting the Quick Start

If something gets stuck:

```bash
# See what went wrong
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>

# Check recent events
kubectl get events -A --sort-by='.lastTimestamp'

# Most common: waiting for image to pull or storage to be ready
# Just wait. K8s will keep retrying.
```

---

## Next: Add Your Applications

Once the core stack is up (cert-manager + OTel + PostgreSQL):

```bash
# Deploy Flask web-shop with OTel tracing
make web-shop

# Deploy Checkmk (if external, skip this)
make checkmk

# Deploy NetFlow simulator
make netflow

# Deploy mock devices (NetApp, Meraki, Redfish)
make mocks
```

Each app automatically gets:
- TLS cert (cert-manager)
- K8s metadata enrichment (OTel)
- DNS name (Traefik Ingress)
- Health checks (K8s probes)

---

## Checklist: You're Done When...

- [ ] `kubectl get nodes` shows `Ready`
- [ ] `kubectl get pods -A` shows mostly `Running`
- [ ] `helm list -A` shows cert-manager, otel-node, otel-cluster, postgres
- [ ] `kubectl get certificate -A` shows certs in `Ready` state
- [ ] PostgreSQL is `1/1 Ready` in databases namespace
- [ ] `kubectl top pods -n otel-monitoring` shows resource usage (metrics-server working)

You now have a working K8s cluster with automatic TLS and observability. Deploy your apps.

---

## One Key Insight

The complexity of K8s is **front-loaded** — setup takes longer. But then:
- Adding a new app = just declare it
- Self-healing = pods restart automatically
- Scaling = one number changes
- TLS renewal = K8s handles forever
- Monitoring = built-in from the start

Docker Compose excels at: dev laptops, quick demos, single-server setups
K8s excels at: production, multi-node, self-healing, monitoring at scale
