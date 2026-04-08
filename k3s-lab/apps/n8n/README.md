# n8n in k3s

Workflow automation platform deployed to k3s cluster.

## Quick Start

```bash
# Deploy n8n
kubectl apply -f n8n.yaml

# Wait for pod
kubectl rollout status deployment/n8n -n n8n --timeout=120s

# Access at https://n8n.k3s.local
# (assumes wildcard TLS cert is installed, run `make all` first)
```

## Custom Image with Checkmk Nodes

To use your custom Dockerfile with n8n-nodes-checkmk:

### 1. Build and push to local registry

```bash
cd ~/Docker/n8n
docker build -t 192.168.121.1:5000/n8n:custom .
docker push 192.168.121.1:5000/n8n:custom
```

### 2. Update n8n.yaml

Change the image:
```yaml
image: 192.168.121.1:5000/n8n:custom
```

Then redeploy:
```bash
kubectl apply -f n8n.yaml
```

## Access

- **UI**: https://n8n.k3s.local (after TLS setup)
- **Port**: 5678 internally, mapped to 80 via Service

## Data Persistence

- Data stored in PVC (5Gi by default)
- Located at `/home/node/.n8n` in container
- Survives pod restarts

## Environment Variables

Configured via ConfigMap:
- `GENERIC_TIMEZONE`: Europe/Berlin
- `TZ`: Europe/Berlin
- `N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS`: true
- `N8N_COMMUNITY_PACKAGES_ENABLED`: true
- `NODE_TLS_REJECT_UNAUTHORIZED`: 0 (for self-signed certs)

## Clean Up

```bash
kubectl delete -f n8n.yaml
```
