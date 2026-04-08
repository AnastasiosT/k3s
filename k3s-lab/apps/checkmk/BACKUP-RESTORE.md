# Checkmk Backup & Restore Guide

## Overview
This guide covers backing up and restoring checkmk v250 site in Kubernetes.

**Data location:** `/mnt/checkmk-data/v250` (VM) → `/omd/sites/v250` (pod)

---

## Prerequisites
```bash
export KUBECONFIG=/home/anastasios/.kube/config-k3s
export CHECKMK_NS=checkmk
export CHECKMK_POD=$(kubectl get pod -n $CHECKMK_NS -l app=checkmk -o jsonpath='{.items[0].metadata.name}')
```

---

## Backup Procedure

### 1. From Checkmk Web UI (Easiest)
1. Login to `https://checkmk.k3s.local/v250/check_mk/`
2. Go: **Setup** → **Backup & Restore**
3. Click **Create backup**
4. Download the `.tar.gz` file

### 2. Via CLI (Pod)
```bash
# Exec into pod
kubectl exec -it -n $CHECKMK_NS $CHECKMK_POD -- bash

# Create backup
su - v250
cmk -b /tmp/v250-backup.tar.gz

# Exit
exit
exit

# Copy to your local machine
kubectl cp $CHECKMK_NS/$CHECKMK_POD:/tmp/v250-backup.tar.gz ~/Downloads/v250-backup.tar.gz
```

### 3. Direct from VM
```bash
# SSH to VM
vagrant ssh

# Backup as root
sudo tar czf /mnt/checkmk-data/v250-backup.tar.gz -C /mnt/checkmk-data v250/

# Exit
exit

# Copy from VM to local
scp vagrant@192.168.121.90:/mnt/checkmk-data/v250-backup.tar.gz ~/Downloads/
```

---

## Restore Procedure

### Prerequisites
- Have backup file: `v250-backup.tar.gz`
- Ensure disk space available: `df -h /` (needs ~2x backup size)

### Option 1: Via Web UI (Recommended)
```bash
# Just upload and restore in the UI:
# 1. https://checkmk.k3s.local/v250/check_mk/
# 2. Setup → Backup & Restore → Upload backup file
# 3. Select file and click "Restore"
```

### Option 2: Via CLI (Pod)
```bash
# Copy backup into pod
kubectl cp ~/Downloads/v250-backup.tar.gz $CHECKMK_NS/$CHECKMK_POD:/tmp/

# Exec into pod
kubectl exec -it -n $CHECKMK_NS $CHECKMK_POD -- bash

# Stop site
sudo /opt/omd/versions/*/bin/omd stop v250

# Restore
su - v250
cmk -r /tmp/v250-backup.tar.gz

# Start site
exit
sudo /opt/omd/versions/*/bin/omd start v250

# Verify
sudo /opt/omd/versions/*/bin/omd status v250

# Exit
exit
exit
```

### Option 3: Via VM hostPath (Fastest for Large Backups)
```bash
# From local machine, copy to VM
scp ~/Downloads/v250-backup.tar.gz vagrant@192.168.121.90:/tmp/

# SSH into VM
vagrant ssh

# Stop checkmk in pod
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl exec -it -n checkmk $(kubectl get pod -n checkmk -l app=checkmk -o jsonpath='{.items[0].metadata.name}') -- sudo /opt/omd/versions/*/bin/omd stop v250

# Extract backup (as root to avoid permissions issues)
cd /mnt/checkmk-data
sudo cp /tmp/v250-backup.tar.gz .
sudo tar xzf v250-backup.tar.gz

# Fix permissions (IMPORTANT!)
sudo chown -R 1000:1000 /mnt/checkmk-data/v250/

# Start checkmk
kubectl exec -it -n checkmk $(kubectl get pod -n checkmk -l app=checkmk -o jsonpath='{.items[0].metadata.name}') -- sudo /opt/omd/versions/*/bin/omd start v250

# Verify
kubectl exec -it -n checkmk $(kubectl get pod -n checkmk -l app=checkmk -o jsonpath='{.items[0].metadata.name}') -- sudo /opt/omd/versions/*/bin/omd status v250

# Clean up backup tar
sudo rm /mnt/checkmk-data/v250-backup.tar.gz

# Exit VM
exit
```

### Post-Restore
```bash
# Restart pod to pick up restored data
kubectl rollout restart deployment/checkmk -n $CHECKMK_NS
kubectl rollout status deployment/checkmk -n $CHECKMK_NS --timeout=180s

# Test login
curl -k -u cmkadmin:cmk https://checkmk.k3s.local/v250/check_mk/
```

---

## Troubleshooting

### Pod stuck after restore
```bash
# Remove taint
kubectl taint nodes checkmk-k3s node.kubernetes.io/disk-pressure:NoSchedule- 2>/dev/null || true

# Delete evicted pods
kubectl delete pod -n $CHECKMK_NS --field-selector status.phase=Evicted
```

### Permission denied errors
```bash
# Fix ownership
kubectl exec -it -n $CHECKMK_NS $CHECKMK_POD -- sudo chown -R 1000:1000 /mnt/checkmk-data/v250/
```

### Disk full (disk-pressure taint)
```bash
# Check usage
df -h /

# Expand VM disk if needed (see Vagrantfile notes)
# Or clean up old backups: sudo rm /mnt/checkmk-data/*.tar.gz
```

### Container status unknown
Wait 30 seconds and check logs:
```bash
kubectl logs -n $CHECKMK_NS $CHECKMK_POD --tail=50
```

---

## Best Practices

1. **Backup frequency:** Daily or before major changes
2. **Test restores:** Periodically test restore on staging environment
3. **Disk space:** Keep 30GB+ free on VM (current: 100GB disk)
4. **Cleanup:** Remove old backup `.tar.gz` files to save space
5. **Permissions:** After restore, always fix permissions with `chown 1000:1000`

---

## Configuration
- **Backup location (VM):** `/mnt/checkmk-data/`
- **Checkmk site (VM):** `/mnt/checkmk-data/v250/`
- **Checkmk site (pod):** `/omd/sites/v250/`
- **Default password:** `cmk` (user: `cmkadmin`)
- **Web UI:** `https://checkmk.k3s.local/v250/check_mk/`
