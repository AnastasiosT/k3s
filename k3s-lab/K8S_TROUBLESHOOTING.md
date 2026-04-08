# Kubernetes Troubleshooting Guide

Practical debugging workflows for k3s clusters. When something breaks, follow these patterns.

## The Mental Model

K8s has three layers:
1. **Object Definition** (YAML) — what you declared
2. **Controller Reconciliation** — K8s trying to reach desired state
3. **Actual Runtime** — what's actually running

Debugging = check all three layers.

---

## Pod Stuck in Pending

Pod exists but won't start. Check:

```bash
# 1. View pod definition and reason
kubectl describe pod <pod-name> -n <namespace>
# Look for: Events section, Condition messages, Node assignment

# 2. Check if node is available
kubectl get nodes
kubectl describe node <node-name>
# Look for: MemoryPressure, DiskPressure, PIDPressure, Ready status

# 3. Check resource requests vs node capacity
kubectl describe pod <pod-name> -n <namespace> | grep -A5 Requests
# Is requested CPU/memory bigger than node has free?

# 4. Check for missing resources
kubectl get pvc -n <namespace>
# PVC stuck in Pending = storage not available
kubectl get pv
```

**Common causes:**
- PVC not bound to PV (`PersistentVolumeClaim` shows "Pending")
- Insufficient CPU/memory on node
- Node has taints pod doesn't tolerate
- Image pull error (next section)

---

## Pod Stuck in ImagePullBackOff

Container image can't be pulled. Check:

```bash
# 1. See the exact error
kubectl describe pod <pod-name> -n <namespace>
# Look for: Events, last error message

# 2. Check image exists in registry
docker image ls | grep <image-name>
# Or check remote registry

# 3. If using local registry, verify it's running
docker ps | grep registry
kubectl get svc -n <namespace> | grep registry

# 4. Check credentials (if private registry)
kubectl get secrets -n <namespace>
# Look for dockercfg or dockerconfigjson type

# 5. Check image typo in manifest
kubectl get deployment <name> -n <namespace> -o yaml | grep image:
```

**Fix steps:**
```bash
# If image is on local docker but not in registry:
docker tag myimage:latest localhost:5000/myimage:latest
docker push localhost:5000/myimage:latest

# Then trigger pod restart:
kubectl rollout restart deployment/<name> -n <namespace>
```

---

## Pod Stuck in CrashLoopBackOff

Container starts but crashes immediately. Check:

```bash
# 1. View current logs
kubectl logs <pod-name> -n <namespace>

# 2. View logs from previous run (crashed pod)
kubectl logs <pod-name> -n <namespace> --previous

# 3. Check restart count
kubectl get pod <pod-name> -n <namespace> -o wide
# Look for RESTARTS column (should be increasing)

# 4. Check exit code
kubectl describe pod <pod-name> -n <namespace>
# Look for: Last State > Terminated > ExitCode
# 1 = general error, 143 = killed by SIGTERM

# 5. Check if probes are killing the pod
kubectl describe pod <pod-name> -n <namespace> | grep -A10 "Liveness\|Readiness"
```

**Common causes:**
- Missing environment variable or config
- Port already in use
- Missing dependency (database not ready)
- Application crash (check logs)

**Fix:**
```bash
# If an init dependency is missing, wait for it
# Example: wait for PostgreSQL
kubectl exec <pod-name> -n <namespace> -- sh -c \
  'until pg_isready -h postgres.databases.svc -p 5432; do sleep 2; done'
```

---

## Pod Stuck in Init:0/1 or Init:N/M

Init containers haven't completed. Check:

```bash
# 1. Which init container is stuck?
kubectl describe pod <pod-name> -n <namespace>
# Look for: Init Containers, State

# 2. View init container logs
kubectl logs <pod-name> -n <namespace> -c <init-container-name>

# 3. Check if init container has a dependency issue
kubectl logs <pod-name> -n <namespace> -c <init-container-name> --previous

# 4. Check for ConfigMap/Secret the init needs
kubectl get configmap -n <namespace>
kubectl get secret -n <namespace>
```

**Example: Init waiting for database**
```bash
# Init container tries to connect to DB but it's not ready yet
kubectl logs postgres-init-d2f8b -n databases

# Wait for postgres pod to be Ready
kubectl rollout status statefulset/postgres -n databases --timeout=120s
```

---

## Service Not Reachable

Pod running but can't reach it. Check:

```bash
# 1. Service exists and has endpoints
kubectl get svc -n <namespace>
kubectl get endpoints -n <namespace>
# Endpoints should show pod IPs. If empty = no pods match selector

# 2. Check service selector matches pod labels
kubectl get svc <service-name> -n <namespace> -o yaml | grep selector -A3
kubectl get pods -n <namespace> -L <label-key>
# Labels must match exactly (case-sensitive)

# 3. Test DNS inside cluster
kubectl run -it --rm debug --image=alpine --restart=Never -- \
  nslookup <service-name>.<namespace>.svc.cluster.local
# Should resolve to service ClusterIP

# 4. Test if port is correct
kubectl get svc <service-name> -n <namespace> -o yaml | grep port -A2
# targetPort must match pod containerPort

# 5. Check pod can accept traffic
kubectl logs <pod-name> -n <namespace>
# Does pod show it's listening on the port?
kubectl exec <pod-name> -n <namespace> -- netstat -tlnp
# Or: curl localhost:<port>
```

**Common fixes:**
```bash
# Pod labels don't match service selector
kubectl label pod <pod-name> app=myapp -n <namespace> --overwrite

# Service port mapping wrong
kubectl patch svc <service-name> -n <namespace> \
  -p '{"spec":{"ports":[{"port":80,"targetPort":8080}]}}'
```

---

## Deployment Won't Scale

Can't scale replicas or pods don't come up. Check:

```bash
# 1. Check current vs desired replicas
kubectl get deployment <name> -n <namespace>
# DESIRED vs READY mismatch = pods aren't starting

# 2. View ReplicaSet status
kubectl get rs -n <namespace>
# Shows actual pod count per RS

# 3. Check latest ReplicaSet events
kubectl describe rs <rs-name> -n <namespace>
# Look for Events section

# 4. Scale and watch
kubectl scale deployment <name> --replicas=3 -n <namespace>
kubectl get pods -n <namespace> -w
# Watch for Pending → Running transition

# 5. If pods stuck in Pending
# See "Pod Stuck in Pending" section above
```

---

## StatefulSet Pod Won't Come Up

StatefulSet ordinal ordering issue. Check:

```bash
# 1. Check StatefulSet status
kubectl describe statefulset <name> -n <namespace>
# Look for: Replicas, ReadyReplicas, UpdatedReplicas, Partition

# 2. Check PVC status
kubectl get pvc -n <namespace>
# Each StatefulSet pod needs its own PVC

# 3. Check if pod-0 is running
# StatefulSets start pods sequentially: 0, then 1, then 2...
kubectl get pods -n <namespace> | grep <statefulset-name>

# 4. View pod-0 logs if it exists
kubectl logs <statefulset-name>-0 -n <namespace>
```

**Common issue: PVC not bound**
```bash
# PVC waiting for PV
kubectl get pvc -n <namespace>
# Status should be "Bound", if "Pending" = no matching PV

# Check if PV exists
kubectl get pv
# For k3s, PVs are hostPath-backed
```

---

## ConfigMap Changes Not Applied

Changed ConfigMap but pods still use old config. Remember:

**ConfigMaps are NOT hot-reloaded by default!** Pods cache the config in memory.

```bash
# 1. Verify ConfigMap was updated
kubectl get configmap <name> -n <namespace> -o yaml

# 2. Restart pods to pick up new config
kubectl rollout restart deployment/<name> -n <namespace>
kubectl rollout restart statefulset/<name> -n <namespace>
kubectl rollout restart daemonset/<name> -n <namespace>

# 3. Wait for rollout
kubectl rollout status deployment/<name> -n <namespace>

# 4. Verify new config is mounted
kubectl exec <pod-name> -n <namespace> -- cat /path/to/mounted/file
# Should show the new content
```

---

## Helm Install/Upgrade Failed

Helm chart apply error. Check:

```bash
# 1. Check Helm release status
helm list -n <namespace>
# Look for STATUS: deployed vs failed

# 2. See what Helm rendered (before applying)
helm template <release-name> ./charts/<chart> -n <namespace> -f values.yaml
# Shows the raw Kubernetes YAML Helm would apply

# 3. Validate syntax
helm lint ./charts/<chart>

# 4. Dry run (render without applying)
helm upgrade --install <release-name> ./charts/<chart> \
  -n <namespace> --dry-run --debug -f values.yaml

# 5. Check Helm history
helm history <release-name> -n <namespace>
# Shows all releases and their status

# 6. View Helm release YAML applied
helm get manifest <release-name> -n <namespace> | less
```

**Rollback if needed:**
```bash
# Revert to previous release
helm rollback <release-name> <revision-number> -n <namespace>
```

---

## Pod Exec Fails

Can't execute commands inside pod. Check:

```bash
# 1. Pod must be in Running state
kubectl get pods -n <namespace>
# Status should be Running, not Pending/CrashLoop

# 2. Check if container has shell
kubectl exec <pod-name> -n <namespace> -- which sh
kubectl exec <pod-name> -n <namespace> -- which bash

# 3. Use the available shell
kubectl exec <pod-name> -n <namespace> -- /bin/sh
# Instead of: /bin/bash (alpine has sh, not bash)

# 4. View available commands
kubectl exec <pod-name> -n <namespace> -- ls -la /bin
```

---

## Node Health Check

Node marked as NotReady. Check:

```bash
# 1. Node status
kubectl get nodes
# Status should be "Ready"

# 2. Detailed node info
kubectl describe node <node-name>
# Look for: Conditions (MemoryPressure, DiskPressure, Ready, etc.)

# 3. Node resource usage
kubectl top nodes
# Requires metrics-server (k3s has it by default)

# 4. Check kubelet logs (SSH to node)
vagrant ssh k3s
sudo journalctl -u k3s -f
# Or on full K8s: systemctl status kubelet
```

---

## Events: The Gold Mine

Kubernetes stores event history. Check here first:

```bash
# 1. Namespace-level events (recent)
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# 2. All events (entire cluster)
kubectl get events -A --sort-by='.lastTimestamp'

# 3. Pod-specific events
kubectl describe pod <pod-name> -n <namespace> | grep -A20 Events

# 4. Deployment-specific events
kubectl describe deployment <name> -n <namespace> | grep -A20 Events

# 5. Real-time event stream
kubectl get events -n <namespace> -w
```

Events show:
- Image pull failures
- Probe failures
- Scheduling failures
- Pod creation/deletion
- Volume attach/detach

---

## Quick Debugging Checklist

When a pod won't start:

```bash
# 1. Pod status
kubectl get pods -n <namespace>

# 2. Pod details
kubectl describe pod <pod-name> -n <namespace>
# Check: Conditions, Events, Node assignment

# 3. Resource availability
kubectl describe node <node-name>

# 4. Logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous

# 5. Config validation
kubectl get configmap -n <namespace>
kubectl get secret -n <namespace>

# 6. Storage status
kubectl get pvc -n <namespace>
kubectl get pv

# 7. Service connectivity
kubectl get svc -n <namespace>
kubectl get endpoints -n <namespace>

# 8. Events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

---

## Common Fixes Quick Reference

| Problem | Command |
|---------|---------|
| Pod not starting | `kubectl describe pod <pod> -n <ns>` |
| ConfigMap not picked up | `kubectl rollout restart deployment/<name> -n <ns>` |
| Can't reach service | Check labels: `kubectl get pods --show-labels -n <ns>` |
| StatefulSet stuck | Check PVC: `kubectl get pvc -n <ns>` |
| Helm failed | `helm get manifest <name> -n <ns>` |
| Image not found | `docker push localhost:5000/<image>:latest` |
| Pod exec fails | Use correct shell: `/bin/sh` not `/bin/bash` |
| Out of resources | `kubectl top nodes` and `kubectl top pods -n <ns>` |

---

## Advanced: Get Raw YAML

When you need to see exactly what K8s thinks:

```bash
# Pod definition
kubectl get pod <pod-name> -n <namespace> -o yaml

# Deployment
kubectl get deployment <name> -n <namespace> -o yaml

# Service endpoints
kubectl get endpoints <service-name> -n <namespace> -o yaml

# All objects in namespace
kubectl get all -n <namespace> -o yaml

# Export for backup
kubectl get all -n <namespace> -o yaml > backup.yaml
```

---

## Debug Pod Pattern

Launch a debug pod inside the cluster to test connectivity:

```bash
# Alpine-based debug pod (lightweight)
kubectl run -it --rm debug --image=alpine --restart=Never -n <namespace> -- /bin/sh

# Inside the debug pod:
nslookup <service-name>.<namespace>.svc.cluster.local
curl http://<service-name>.<namespace>.svc.cluster.local:8080
wget -qO- http://<service-name>:8080

# Or use busy box (has more tools)
kubectl run -it --rm debug --image=busybox --restart=Never -n <namespace> -- /bin/sh
```

---

## One-Liners for Common Tasks

```bash
# List all pods by node
kubectl get pods -n <namespace> -o wide

# Get pod logs from last 10 minutes
kubectl logs <pod> -n <namespace> --since=10m

# Stream logs from all pods with label
kubectl logs -n <namespace> -l app=myapp -f

# Watch pod status changes
kubectl get pods -n <namespace> -w

# Get CPU/memory usage
kubectl top pods -n <namespace>

# Count pods by status
kubectl get pods -n <namespace> -o json | jq '.items[] | .status.phase' | sort | uniq -c

# Find pods on a specific node
kubectl get pods -n <namespace> --field-selector spec.nodeName=<node-name>

# Get resource requests vs actual
kubectl describe pod <pod> -n <namespace> | grep -A5 "Requests\|Limits"
```
