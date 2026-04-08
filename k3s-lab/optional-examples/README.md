# Optional Examples

These are optional components that are not deployed by default. Use them as needed:

## demo-apps — Demo Applications

⚠️ **Status: Not Implemented**

Demo app deployment scripts have been removed. If you need demo applications (Nginx, Redis, Whoami, Echo, Dashboard), you can either:
1. Deploy them manually via kubectl with custom YAML
2. Implement a new Helm chart for demo apps

See `charts/` directory for Helm chart examples.

## cert-manager — TLS Certificate Management

Full PKI chain with wildcard certificates for HTTPS:
- Self-signed root CA
- Intermediate CA
- Wildcard cert for *.k3s.local
- Traefik TLS Store integration

**Status:** ✅ Deployed automatically by `make all` in the main Makefile.

For manual deployment or individual targets, see [certmanager/Makefile](certmanager/Makefile).

## mocks — Mock Applications

Mock services for testing (e.g., netapp-mock):

Deploy:
```bash
make mocks
```

Or from this directory:
```bash
cd mocks
make all
```

See [mocks/Makefile](mocks/Makefile) for details.
