# LDAP Deployment Structure

Organized by resource type with numbered prefixes for apply order.

## File Organization

- **00-namespace.yaml** - Create the `ldap` namespace
- **01-configmap.yaml** - Configuration data (domain, base DN, LDIF init data)
- **02-secret.yaml** - Credentials (passwords)
- **03-pvc.yaml** - Storage for OpenLDAP data
- **04-service.yaml** - Services for OpenLDAP and LAM
- **05-statefulset.yaml** - OpenLDAP server
- **06-job.yaml** - LDAP initialization job
- **07-deployment.yaml** - LAM (LDAP Account Manager) web UI
- **08-ingress.yaml** - HTTPS ingress for LAM web UI

## Quick Start

Deploy all resources:

```bash
kubectl apply -f ldap/
```

The numbered prefixes ensure resources are applied in dependency order.

## Access

**LAM Web UI:**
- URL: https://ldap.k3s.local (with port-forward: http://localhost:8082)
- Credentials: `cn=admin,dc=cmk,dc=dev,dc=de` / `ldapadmin`

**LDAP Server:**
- Internal: `ldap://openldap.ldap.svc.cluster.local:389`
- Local: `ldap://localhost:389` (requires port-forward)

## Customization

- **Passwords**: Edit `02-secret.yaml`
- **Domain**: Edit `01-configmap.yaml` (DOMAIN, BASE_DN)
- **Users/Groups**: Edit `01-configmap.yaml` (org.ldif section)
- **LAM replica count**: Edit `07-deployment.yaml`
- **Storage size**: Edit `03-pvc.yaml` and `05-statefulset.yaml`

After changes, re-apply:

```bash
kubectl apply -f ldap/
```

## Troubleshooting

```bash
# Check pod status
kubectl get pods -n ldap

# View logs
kubectl logs -n ldap openldap-0                # OpenLDAP
kubectl logs -n ldap -l app=lam                # LAM
kubectl logs -n ldap job/ldap-init             # Init job

# Test LDAP connection
kubectl exec -it openldap-0 -n ldap -- ldapsearch \
  -x -H ldap://localhost:389 \
  -D "cn=admin,dc=cmk,dc=dev,dc=de" \
  -w ldapadmin \
  -b "dc=cmk,dc=dev,dc=de" \
  -s base
```
