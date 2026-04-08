# OpenLDAP Deployment to k3s

This guide explains how to deploy your OpenLDAP stack from Docker to your k3s cluster.

## Components

1. **OpenLDAP** - LDAP directory service (nfrastack/openldap)
2. **LDAP Init Job** - Initializes LDAP with your organization structure
3. **LDAP Monitor** - Custom Python app with OTel instrumentation for metrics collection
4. **LAM** - LDAP Account Manager web UI for user/group management

## Prerequisites

- k3s cluster running (✓ you have this)
- Docker or containerd CLI access
- kubectl configured to access your cluster
- OTel Collector running (for LDAP Monitor to send metrics)

## Deployment Steps

### Option 1: Using Local Registry (Recommended)

If you have a local Docker registry at `localhost:5000`:

```bash
cd /home/anastasios/git/consultants/otel/k3s-lab

# Build and deploy everything
./build-and-deploy-ldap.sh
```

If your registry is at a different location:

```bash
export DOCKER_REGISTRY="registry.example.com:5000"
./build-and-deploy-ldap.sh
```

### Option 2: Manual Deployment

#### 1. Build and push the monitor image

```bash
cd ldap-monitor
docker build -t localhost:5000/ldap-monitor:latest .
docker push localhost:5000/ldap-monitor:latest
```

#### 2. Update the manifest with your registry

Edit `ldap-deployment.yaml` and update the ldap-monitor image:

```yaml
# Before:
image: ldap-monitor:latest

# After:
image: localhost:5000/ldap-monitor:latest
```

#### 3. Deploy to k3s

```bash
kubectl apply -f ldap-deployment.yaml
```

#### 4. Monitor the deployment

```bash
# Watch the deployments
kubectl rollout status deployment/lam -n ldap --timeout=5m
kubectl rollout status deployment/ldap-monitor -n ldap --timeout=5m

# Wait for initialization
kubectl wait --for=condition=complete job/ldap-init -n ldap --timeout=5m
```

## Accessing Services

### LDAP Server (Direct)

```bash
# Port-forward to LDAP
kubectl port-forward -n ldap svc/openldap 389:389

# Test connection
ldapsearch -x -H ldap://localhost:389 \
  -D "cn=admin,dc=cmk,dc=dev,dc=de" \
  -w "ldapadmin" \
  -b "dc=cmk,dc=dev,dc=de" \
  "cn=ldap.site1.admin"
```

### LAM Web UI

```bash
# Port-forward to LAM
kubectl port-forward -n ldap svc/lam 8082:80

# Access in browser
open http://localhost:8082
# Login as: cn=admin,dc=cmk,dc=dev,dc=de / ldapadmin
```

### LDAP Monitor (Metrics)

Monitor is configured to send metrics to:
```
otel-collector.otel-collectors.svc.cluster.local:4317
```

Metrics exported (OTel format):
- `openldap.connections.current`
- `openldap.connections.total`
- `openldap.threads.active`
- `openldap.threads.pending`
- `openldap.threads.open`
- `openldap.waiters.read`
- `openldap.waiters.write`
- `openldap.operations.initiated.*` (bind, search, add, delete, etc.)
- `openldap.operations.completed.*`

## Configuration

### LDAP Credentials

All credentials are stored in the `openldap-credentials` Secret:

```bash
kubectl get secret -n ldap openldap-credentials -o yaml
```

To update credentials:

```bash
kubectl set env -n ldap statefulset/openldap \
  ADMIN_PASS=newpassword \
  --overwrite
```

### LDAP Organization Structure

The initialization data is in `ldap-init-data` ConfigMap. To modify:

```bash
kubectl edit configmap -n ldap ldap-init-data
```

Then re-run the init job:

```bash
kubectl delete job -n ldap ldap-init
kubectl apply -f ldap-deployment.yaml
```

## Troubleshooting

### Check LDAP pod status

```bash
kubectl describe pod -n ldap openldap-0
kubectl logs -n ldap openldap-0
```

### Check initialization status

```bash
kubectl logs -n ldap job/ldap-init
kubectl describe job -n ldap ldap-init
```

### Check LAM status

```bash
kubectl logs -n ldap deployment/lam
```

### Check monitor status and metrics collection

```bash
kubectl logs -n ldap deployment/ldap-monitor -f
```

### Test LDAP connection from inside cluster

```bash
kubectl run -it --rm ldap-test --image=nfrastack/openldap:latest -- \
  ldapsearch -x -H ldap://openldap.ldap.svc.cluster.local:389 \
  -D "cn=admin,dc=cmk,dc=dev,dc=de" \
  -w "ldapadmin" \
  -b "dc=cmk,dc=dev,dc=de" \
  -s base
```

## Default Credentials

- **LDAP Admin**: `cn=admin,dc=cmk,dc=dev,dc=de` / `ldapadmin`
- **LAM Web UI**: `cn=admin,dc=cmk,dc=dev,dc=de` / `ldapadmin`
- **LAM Master Password**: `lam_master_password`

## Storage

LDAP data is stored in a `PersistentVolumeClaim` named `openldap-0`:

```bash
kubectl get pvc -n ldap
```

Default size is 5Gi. To resize:

```bash
kubectl patch pvc -n ldap openldap-0 -p '{"spec":{"resources":{"requests":{"storage":"10Gi"}}}}'
```

## OTel Integration

The LDAP Monitor exports metrics to the OTel Collector. Make sure:

1. OTel Collector is running in `otel-collectors` namespace
2. OTLP receiver is listening on port 4317 (gRPC)

Check connection:

```bash
kubectl logs -n ldap deployment/ldap-monitor | grep -i "otlp\|endpoint"
```

## Next Steps

1. Verify LAM web UI is accessible
2. Add users/groups through LAM or LDAP directly
3. Configure applications to authenticate against this LDAP server
4. Monitor metrics in your observability stack
