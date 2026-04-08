# Checkmk on k3s

## Backup & Restore

### Backup from source machine
```bash
omd backup v250 /tmp/v250-backup.tar.gz
scp /tmp/v250-backup.tar.gz vagrant@192.168.121.90:/tmp/
```

### Restore into k3s PVC

**1. Find the PVC path on the VM:**
```bash
kubectl describe pv $(kubectl get pvc checkmk-data -n checkmk -o jsonpath='{.spec.volumeName}') | grep Path
```

**2. Stop the pod:**
```bash
kubectl scale deployment checkmk -n checkmk --replicas=0
```

**3. Restore:**
```bash
PVC_PATH=/var/lib/rancher/k3s/storage/pvc-45b372b2-32c4-4ef2-bafb-3ac4064d6c3c_checkmk_checkmk-data
sudo tar -xzf /tmp/v250-backup.tar.gz -C $PVC_PATH
```

**4. Start the pod:**
```bash
kubectl scale deployment checkmk -n checkmk --replicas=1
kubectl rollout status deployment/checkmk -n checkmk --timeout=120s
```

**5. Fix Apache listening address (required):**

After restore, Apache will listen on `127.0.0.1:5012` (localhost only). Traefik needs it on all interfaces (`0.0.0.0:5012`):

```bash
POD=$(kubectl get pods -n checkmk -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n checkmk $POD -- bash -c 'cat > /omd/sites/v250/etc/apache/listen-port.conf << EOF
# This file is created by '"'"'omd config set APACHE_TCP_PORT'"'"'.
# Better do not edit manually
ServerName 0.0.0.0:5012
Listen 0.0.0.0:5012
EOF'

kubectl exec -n checkmk $POD -- omd restart apache
```

Access the site at: **https://checkmk.k3s.local/v250/check_mk/**

> **Note:** Source and target must run the same Checkmk version.
> Current version: `2.5.0b1.ultimatemt`
>
> **Permanent fix (on source laptop):** Before backing up, run:
> ```bash
> omd config set APACHE_TCP_PORT 5012
> omd config set APACHE_TCP_ADDR 0.0.0.0
> omd restart apache
> ```
> Then all future restores will have the correct config.
