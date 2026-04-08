# K3s Cluster with OTel Monitoring + Demo Applications

This Terraform setup deploys a complete k3s cluster with OpenTelemetry observability and multiple demo applications:

- **OpenTelemetry Collectors** (DaemonSet + Deployment) shipping metrics, traces, and logs to Checkmk
- **flask-web-shop** — instrumented demo app to generate real traces and spans
- **CheckMK Kubernetes Agent** for cluster monitoring
- **Nginx + Redis** for web services and caching
- **Whoami + Echo Server + Dashboard** for testing and demos

## Quick Start

```bash
make k3s      # Start VM + k3s + all core services
make status   # Check pod status
make stop     # Halt VM
make destroy  # Destroy VM completely
```

> **TL;DR:** Run `make k3s` from this directory. Everything deploys automatically (first run ~3–4 min).

## Directory Structure

```
.
├── Makefile                     # Core targets: k3s, all, status, clean, stop, destroy
├── config.mk                    # Shared Make config (kubectl, helm, kubeconfig paths)
├── terraform/                   # Terraform IaC: VM spec (8GB, 4 CPUs, 100GB disk)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── cloud-init/
├── docker-compose.yml           # Local Docker registry
│
├── apps/
│   └── checkmk/                 # Checkmk monitoring site
│       ├── checkmk.yaml         # Deployment + Service + Ingress
│       └── README.md            # Backup/restore guide
│
├── databases/                   # Database deployments
│   └── postgres/                # PostgreSQL StatefulSet
│
├── otel-operator/               # OpenTelemetry Operator Custom Resources
│   ├── gateway.yaml             # Central gateway collector (metrics, traces → Checkmk)
│   ├── postgres.yaml            # PostgreSQL metrics + pg_stat_statements receiver
│   ├── kubernetes.yaml          # K8s cluster metrics + events + transform processor
│   ├── netflow.yaml             # NetFlow v5/sFlow receiver for network metrics
│   ├── logs.yaml                # Log collection (filelog + kubernetes)
│   ├── instrumentation.yaml     # Auto-instrumentation rules (Python, Java, etc.)
│   └── Makefile                 # Deploy/manage OTel operator
│
├── optional-examples/           # Optional components (not deployed by default)
│   ├── certmanager/             # TLS PKI chain + wildcard certificates
│   ├── demo-apps/               # Demo apps (deprecated, scripts removed)
│   ├── mocks/                   # Mock applications (netapp-mock)
│   └── README.md
│
└── scripts/
    └── provision.sh             # k3s + Checkmk provisioning (called by Vagrantfile)
```

## Prerequisites

- **Terraform** >= 1.5 (for Infrastructure as Code)
- **libvirt** + KVM (qemu-kvm, libvirt-daemon-system)
- **Docker** + docker compose (for local registry)
- **kubectl** and **helm** on your PATH
- **SSH key pair** at `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`

### Install (Ubuntu/Debian - libvirt):
```bash
sudo apt install -y qemu-kvm libvirt-daemon-system docker.io docker-compose

# Install Terraform (https://developer.hashicorp.com/terraform/downloads)
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt install -y terraform
```

## Getting Started

### Step 1 — Start k3s

```bash
cd /path/to/k3s-lab
make k3s
```

This will:
1. Configure Docker to allow HTTP pushes to the local registry (one-time)
2. Start the local Docker registry at `192.168.121.1:5000`
3. Use Terraform to provision a k3s VM with 8GB memory, 4 CPUs, and **100GB disk**
4. Provision k3s + install Checkmk agent via cloud-init and provision.sh
5. **Fetch kubeconfig** and save to `~/.kube/config-k3s`

After `make k3s` completes, kubectl is ready to use:
```bash
export KUBECONFIG=~/.kube/config-k3s
kubectl get nodes
```

**First run takes ~2–3 minutes.**

### Step 2 — Deploy Infrastructure

```bash
# Deploy core infrastructure (kubeconfig, TLS, OTel)
make all

# Then optionally deploy PostgreSQL
make postgres     # Deploy PostgreSQL

# Or deploy other optional components
make mocks        # Mock applications (netapp-mock)
make demo-apps    # Demo services (Nginx, Redis, Whoami, Echo)
```

### Step 3 — Verify Deployment

After `make all` completes, verify everything:

```bash
make status
```

Core infrastructure pods (OTel, Cert-Manager, Traefik, Reflector) should show `Running`:

```bash
export KUBECONFIG=~/.kube/config-k3s

# Check OTel Operator collectors
kubectl get opentelemetrycollectors -n otel-collectors

# View gateway collector logs
kubectl logs -n otel-collectors deployment/gateway-collector --tail=50

# View postgres collector logs
kubectl logs -n otel-collectors deployment/postgres-collector --tail=50
```

### Step 4 — Configure OTel Collectors (if needed)

All collectors are defined as OTel Operator Custom Resources in `otel-operator/`:

**To change Checkmk endpoint:**
```bash
# Edit otel-operator/gateway.yaml
# Change: exporters.otlp/checkmk-metrics.endpoint to your Checkmk IP:4317
kubectl apply -f otel-operator/gateway.yaml
```

**To change PostgreSQL connection:**
```bash
# Edit otel-operator/postgres.yaml
# Change: receivers.postgresql.endpoint to your DB server
kubectl apply -f otel-operator/postgres.yaml
```

**To add/remove collectors:**
```bash
# Each YAML file is a standalone OpenTelemetryCollector resource
kubectl apply -f otel-operator/YOUR-COLLECTOR.yaml
```

### Step 5 — Configure Checkmk Kubernetes Monitoring

If you want Checkmk to monitor the k3s cluster:

#### Get credentials from the VM

```bash
# Service account token (for API authentication)
ssh ubuntu@192.168.121.90 "cat /home/ubuntu/token.txt" | tr -d '\n'

# k3s API CA certificate
ssh ubuntu@192.168.121.90 "cat /home/ubuntu/ca.crt"
```

#### Upload CA to Checkmk

In Checkmk UI: **Setup → Global settings → Trusted certificate authorities for SSL**
- Paste the full certificate block

#### Create Kubernetes monitoring rule

In Checkmk UI: **Setup → Agents → VM, cloud, container → Kubernetes**

| Field | Value |
|-------|-------|
| Cluster name | `k3s` |
| Token | (paste from command above, no trailing newline) |
| API server endpoint | `https://192.168.121.90:6443` |
| SSL certificate verification | enabled |
| Proxy | No proxy |
| Cluster collector endpoint | `http://192.168.121.90:30035` |

#### Verify connection

```bash
# Test API connectivity
ssh ubuntu@192.168.121.90 "curl -k https://kubernetes.default.svc.cluster.local:443/version"
```

## Network

| Component | Value |
|-----------|-------|
| VM IP | `192.168.121.90` |
| Local registry | `192.168.121.1:5000` (host virbr0 interface) |
| Bridge NIC | `virbr0` (default) — override with `BRIDGE_NIC=<name>` |

Override VM IP:
```bash
export VM_IP="10.0.1.90"
export BRIDGE_NIC="br0"
make k3s
```

## Deployed Services

**Auto-deployed by `make all`:**

| Service | URL | Description |
|---------|-----|-------------|
| **CheckMK** | `http://192.168.121.90:30035` | Kubernetes monitoring |

**Optional (deploy manually):**

| Service | Command | URL | Description |
|---------|---------|-----|-------------|
| **PostgreSQL** | `make postgres` | `192.168.121.90:5432` | Database |
| **NetFlow** | `make netflow` | Various ports | NetFlow collector + simulator |
| **CMDB** | `make cmdb` | `http://192.168.121.90/api/devices` | Device management |
| **Web-Shop** | `make web-shop` | `https://web-shop.k3s.local` | Demo app with tracing |
| **Mocks** | `make mocks` | Internal | Mock services (netapp-mock) |

## OpenTelemetry

Two collectors run in the `otel-monitoring` namespace:

**Node Collector (DaemonSet)** — runs on every node, collects:
- Kubelet stats (CPU/memory/network per pod and container)
- Host metrics (CPU, memory, disk, network, load, processes)
- Container logs from `/var/log/pods`
- OTLP traces/metrics/logs from apps (port 4317/4318)

**Cluster Collector (Deployment)** — runs once, collects:
- Kubernetes cluster state (deployments, pods, nodes, jobs)
- Kubernetes object events

All telemetry is exported to Checkmk via OTLP gRPC (`192.168.178.25:4317`).

### flask-web-shop Traces

The flask-web-shop app is auto-instrumented with OpenTelemetry Python SDK. Every HTTP request to `/order` generates a trace. These appear in Checkmk as distributed traces attributed to the `flask-web-shop` service.

```bash
# Generate some traces
for i in {1..10}; do
  curl -s "http://192.168.121.90:30500/order?item=laptop" > /dev/null
done
```

### Checkmk Integration

The OTel collectors enrich all telemetry with Kubernetes metadata via the `k8sattributes` processor:
- `k8s.namespace.name`
- `k8s.pod.name`
- `k8s.deployment.name`
- `k8s.node.name`

In Checkmk, filter hosts by these attributes under **Setup → Dynamic host management**.

The CheckMK Kubernetes Agent (port 30035) provides cluster-level piggyback data. Configure it under **Setup → Add rule: Kubernetes** with:
- Cluster collector endpoint: `http://192.168.121.90:30035`
- API server: `https://192.168.121.90:6443`

Get the required token:
```bash
ssh ubuntu@192.168.121.90

# Token (inside the VM)
kubectl -n checkmk-monitoring get secret $(kubectl -n checkmk-monitoring get sa myrelease-checkmk-checkmk -o jsonpath='{.secrets[0].name}') -o jsonpath='{.data.token}' | base64 -d | tr -d '\n'

# CA cert (inside the VM)
cat /home/ubuntu/ca.crt

# Or from your host:
ssh ubuntu@192.168.121.90 "cat /home/ubuntu/ca.crt"
```

## Make Commands

Run all make commands from the root `k3s-lab/` directory.

| Command | Purpose |
|---------|---------|
| `make k3s` | Start registry + VM (once) |
| `make all` | Deploy core infrastructure (kubeconfig, TLS, OTel) |
| `make postgres` | Deploy PostgreSQL |
| `make status` | Check pod status across all namespaces |
| `make stop` | Halt VM + registry |
| `make destroy` | Destroy VM + registry |
| `make mocks` | Deploy mock applications (netapp-mock) |
| `make web-shops` | Deploy demo services (Nginx, Redis, Whoami, Echo) |

Override VM IP:
```bash
make k3s VM_IP=10.0.1.90
```

## Pod Status

```bash
# Check pods
export KUBECONFIG=~/.kube/config-k3s
kubectl get pods -A

# Or SSH into the VM
ssh ubuntu@192.168.121.90
kubectl get pods -A
```

## Re-provisioning / Reset

```bash
# Re-deploy OTel collectors only (no VM rebuild)
make all

# Full reset (destroy VM and re-create)
make destroy
make k3s && make all

# Reprovision k3s and apps (via SSH)
ssh ubuntu@192.168.121.90 "sudo /tmp/provision.sh"
```

## Cleanup

```bash
# Stop VM (keep data)
make stop

# Halt and destroy VM completely
make destroy

# Remove cached registry images (optional)
docker volume rm otel_registry-data
```

## Architecture

```
Host machine
├── Docker registry  :5000  (stores flask-web-shop images)
├── Terraform (libvirt)
└── KVM/libvirt VM  192.168.121.90  (8GB RAM, 4 CPUs, 100GB disk)
    └── k3s cluster
        ├── otel-monitoring namespace
        │   ├── DaemonSet: node collector   (kubelet + hostmetrics + logs + OTLP)
        │   └── Deployment: cluster collector (k8s_cluster + k8sobjects)
        │           │
        │           └── OTLP gRPC ──► Checkmk  checkmk.k3s.local:4317
        │
        ├── flask-web-shop namespace
        │   ├── frontend  :30500  (auto-instrumented Flask)
        │   └── backend              ──► node collector :4317
        │
        ├── checkmk-monitoring namespace
        │   └── CheckMK agent  :30035  (piggyback data)
        │
        ├── web-shops namespace
        │   ├── Nginx  :30081
        │   └── Redis  :30379
        │
        └── demo-stack namespace
            ├── Dashboard  :30084
            ├── Whoami     :30082  (3 replicas)
            └── Echo       :30083  (2 replicas)
```

## Troubleshooting

**VM fails to start (domain already exists):**
```bash
virsh list --all
virsh undefine k3s_default
# Then remove disk: sudo rm /var/lib/libvirt/images/k3s_default.img
make k3s
```

**Registry push errors (HTTPS):**
The host Docker daemon must allow the insecure registry. `make k3s` calls `make setup-host` automatically — if it fails, run manually:
```bash
make setup-host
```

**OTel collectors not starting:**
```bash
ssh ubuntu@192.168.121.90
kubectl -n otel-monitoring get pods
kubectl -n otel-monitoring logs <pod-name>
```

**Checkmk 401/400 errors:**
- Use the ServiceAccount token from the `checkmk` secret, not the k3s node token
- Strip trailing newlines: `tr -d '\n' < token.txt`
- Port 30035 is HTTP, not HTTPS

**Pods pending (image pull errors):**
```bash
ssh ubuntu@192.168.121.90
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
# If registry unreachable, check /etc/rancher/k3s/registries.yaml on the VM
```

## Learning Resources

- [K3s Documentation](https://docs.k3s.io)
- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [Checkmk Kubernetes Integration](https://docs.checkmk.com/latest/en/monitoring_kubernetes.html)
- [Kubernetes Basics](https://kubernetes.io/docs/tutorials/)
- [Terraform Documentation](https://www.terraform.io/docs)
- [terraform-provider-libvirt](https://github.com/dmacvicar/terraform-provider-libvirt)
