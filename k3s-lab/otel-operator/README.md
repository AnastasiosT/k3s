# OTel Operator Custom Resources

This directory contains OpenTelemetry Operator CRs (Custom Resources) that replace the Helm-based collector setup with a cleaner, more modular architecture.

## Architecture

```
┌─────────────────────────────────────────────────┐
│         k3s Cluster (otel-collectors NS)        │
│                                                 │
│  ┌──────────────┐  ┌──────────────┐            │
│  │ postgres     │  │ kubernetes   │            │
│  │ (Deployment) │  │ (Deployment) │            │
│  └────┬─────────┘  └────┬─────────┘            │
│       │                 │                       │
│  ┌────┴─────────┬───────┘                      │
│  │              │                              │
│  ▼              ▼                              │
│  ┌──────────────────────────┐                 │
│  │  gateway-collector       │                 │
│  │  (Deployment, port 4317) │                 │
│  └───────────┬──────────────┘                 │
│              │                                │
│  ┌───────────┼──────────────┐                │
│  ▼           ▼              ▼                │
│ netflow    logs        (traces & metrics)   │
│ (DaemonSet)(DaemonSet)                      │
│                                             │
└──────────────────────────────────────────────┘
              │
         192.168.121.1
         Checkmk Instance
              │
    ┌─────────┴─────────┐
    ▼                   ▼
  4317 (metrics)   4417 (traces)
```

## Quick Start

### 1. Install OTel Operator (one-time)

```bash
cd otel/k3s-lab/otel-operator
make operator-install
```

### 2. Deploy all collectors

```bash
make apply
```

This creates 6 collectors:
- **gateway** (Deployment) — receives from all, exports to Checkmk
- **postgres** (Deployment) — PostgreSQL metrics
- **kubernetes** (Deployment) — k8s cluster metrics
- **netflow** (DaemonSet) — NetFlow/sFlow metrics
- **logs** (DaemonSet) — pod/node logs
- **python-auto-instrument** (Instrumentation) — auto-traces Flask apps

### 3. Enable auto-instrumentation on Flask backend

```bash
kubectl annotate deployment backend -n web-shop \
  instrumentation.opentelemetry.io/inject-python=python-auto-instrument \
  --overwrite
```

The Operator will inject the OTel Python agent into your Flask pods automatically (no code changes).

## Individual Collectors

### gateway.yaml
- **Mode**: Deployment
- **Purpose**: Central collection point
- **Receives**: OTLP (gRPC 4317, HTTP 4318) from all other collectors
- **Exports**: Metrics (4317) + Traces (4417) to Checkmk
- **Service**: `gateway-collector.otel-collectors.svc.cluster.local:4317`

### postgres.yaml
- **Mode**: Deployment
- **Purpose**: Database metrics
- **Receivers**: PostgreSQL receiver (connects to postgres.postgres.svc)
- **Metrics**: backends, cache_hit_ratio, commits, locks, rows, transactions, wal
- **Exports**: To gateway via OTLP

### kubernetes.yaml
- **Mode**: Deployment
- **Purpose**: Cluster-level metrics and events
- **Receivers**: k8s_cluster (metrics), k8sobjects (events)
- **Metrics**: node status, pod phase, deployment replicas, resource quotas
- **RBAC**: ClusterRole with permissions for all k8s resources
- **Exports**: To gateway via OTLP

### netflow.yaml
- **Mode**: DaemonSet
- **Purpose**: Network flow monitoring
- **Receivers**: NetFlow v5 (UDP 2055), sFlow (UDP 6343)
- **Processors**: signal_to_metrics connector converts flows to metrics
- **Exports**: To gateway via OTLP

### logs.yaml
- **Mode**: DaemonSet
- **Purpose**: Pod and node logs
- **Receivers**: filelog (container logs), syslog (node logs)
- **Volumes**: Mounts /var/log and /var/lib/docker/containers (read-only)
- **Exports**: To gateway via OTLP

### instrumentation.yaml
- **Kind**: Instrumentation CR (not a collector)
- **Purpose**: Defines auto-instrumentation settings for Python apps
- **Endpoint**: `gateway-collector.otel-collectors.svc.cluster.local:4317`
- **Propagators**: tracecontext, baggage, b3
- **Instrumentation**: requests, urllib, psycopg2, logging

## Makefile Commands

```bash
# Status and verification
make status                    # Show collector pod status
make verify                    # Check data flow
make logs-gateway              # Tail gateway collector logs
make logs-postgres             # Tail postgres collector logs
make logs-kubernetes           # Tail kubernetes collector logs
make logs-netflow              # Tail netflow collector logs
make logs-logs                 # Tail logs collector logs

# Deployment
make apply                     # Deploy all collectors
make delete                    # Delete all collectors

# Cleanup
make uninstall                 # Remove OTel Operator completely
```

## Monitoring Data Flow

### Check if metrics are reaching Checkmk

```bash
# Watch gateway collector processing metrics
kubectl logs -n otel-collectors deployment/gateway-collector -f | grep -i "otlp\|export"

# Verify gateway is ready
kubectl get svc -n otel-collectors gateway-collector
```

### Test individual collectors

```bash
# PostgreSQL metrics
kubectl logs -n otel-collectors deployment/postgres-collector | grep -i "postgresql\|metric"

# Kubernetes metrics
kubectl logs -n otel-collectors deployment/kubernetes-collector | grep -i "k8s_cluster"

# NetFlow metrics
kubectl logs -n otel-collectors daemonset/netflow-collector | grep -i "netflow\|flow"
```

## Configuration Changes

All collector configs are in the CR `spec.config` block (YAML format).

To modify a collector:

```bash
# Edit the CR
kubectl edit opentelemetrycollector <name> -n otel-collectors

# Or edit the YAML file and reapply
vi postgres.yaml
kubectl apply -f postgres.yaml
```

The Operator will automatically restart the collector pods with the new config.

## Auto-Instrumentation

Once the `Instrumentation` CR is applied, annotate your Flask deployment:

```bash
kubectl annotate deployment backend -n web-shop \
  instrumentation.opentelemetry.io/inject-python=python-auto-instrument \
  --overwrite
```

The Operator's mutating webhook will:
1. Inject OTel Python agent as init container
2. Set OTEL_EXPORTER_OTLP_ENDPOINT to gateway-collector
3. Restart the pod

Result: Zero code changes, automatic trace collection.

## Troubleshooting

### Collectors not starting

```bash
kubectl describe opentelemetrycollector <name> -n otel-collectors
kubectl logs -n opentelemetry-operator-system deployment/opentelemetry-operator
```

### Data not reaching Checkmk

1. Verify gateway is running:
   ```bash
   kubectl get pods -n otel-collectors
   ```

2. Check gateway logs for export errors:
   ```bash
   kubectl logs -n otel-collectors deployment/gateway-collector | grep -i "error\|unavailable"
   ```

3. Verify Checkmk is listening:
   ```bash
   # From your laptop
   netstat -tlnp | grep -E "4317|4417"
   ```

4. Test connectivity from pod:
   ```bash
   kubectl run -it --rm debug --image=nicolaka/netcat --restart=Never -- -zv 192.168.121.1 4317
   ```

### Auto-instrumentation not injecting

1. Verify Instrumentation CR exists:
   ```bash
   kubectl get instrumentation -n otel-collectors
   ```

2. Check operator logs:
   ```bash
   kubectl logs -n opentelemetry-operator-system deployment/opentelemetry-operator
   ```

3. Verify annotation on deployment:
   ```bash
   kubectl get deployment backend -n web-shop -o jsonpath='{.metadata.annotations}'
   ```

## Next Steps

1. **Add more receivers** — Copy postgres.yaml pattern for other databases
2. **Custom metrics** — Modify receiver configs in each YAML
3. **Filtering** — Add attribute or metric processors in individual CRs
4. **Advanced routing** — Use gateway pipeline filtering for different Checkmk sources

## References

- [OTel Operator docs](https://opentelemetry.io/docs/kubernetes/operator/)
- [OTel Collector config](https://opentelemetry.io/docs/reference/specification/protocol/exporter/)
- [Supported receivers](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver)
