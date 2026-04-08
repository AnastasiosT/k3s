# Makefile Usage

Quick commands for managing the LDAP stack in Kubernetes.

## Available Commands

### Deployment

```bash
make deploy          # Apply all LDAP manifests
make delete          # Delete all LDAP resources
```

### Status & Info

```bash
make status          # Show pod and service status
make access-info     # Show access credentials and URLs
```

### Logs

```bash
make logs-ldap       # View OpenLDAP logs (streaming)
make logs-lam        # View LAM web UI logs (streaming)
make logs-init       # View initialization job logs
```

### Testing

```bash
make test-connection # Test LDAP connection from inside cluster
```

### Port Forwarding

```bash
make port-forward    # Access LAM at http://localhost:8082
                     # (Press Ctrl+C to stop)
```

### Pod Management

```bash
make restart-ldap    # Restart OpenLDAP and wait for ready
make restart-lam     # Restart LAM and wait for ready
make describe-ldap   # Show detailed pod info
make describe-lam    # Show detailed LAM pod info
```

## Examples

**Initial deployment:**
```bash
make deploy
make status
```

**Check if LDAP is working:**
```bash
make test-connection
```

**Access LAM web UI:**
```bash
make port-forward
# Then visit http://localhost:8082 in browser
```

**Monitor logs while troubleshooting:**
```bash
make logs-ldap     # In one terminal
make logs-lam      # In another terminal
```

**Show access info:**
```bash
make access-info
```

## Configuration

Update the Makefile variables at the top if you change:
- Namespace (default: `ldap`)
- K3s node IP (default: `192.168.121.90`)

```makefile
NAMESPACE := ldap
K3S_NODE_IP := 192.168.121.90
```

## Help

```bash
make help       # Show all available commands
```
