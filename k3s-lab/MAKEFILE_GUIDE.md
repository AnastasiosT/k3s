# Makefile Consolidation Guide

## Overview

The k3s-lab project uses a **hierarchical Makefile system** with shared helpers in `common.mk` to reduce duplication and improve maintainability.

## Structure

```
k3s-lab/
├── config.mk                          ← Environment config + helpers
├── Makefile                           ← Main orchestration
├── otel-operator/Makefile             ← OTel Collectors
├── apps/
│   ├── checkmk/Makefile              ← CheckMK deployment
│   ├── netflow/Makefile              ← NetFlow simulator
│   └── web-shop/load-generator.yaml  ← Load test CronJob
└── optional-examples/
    ├── mocks/Makefile
    └── certmanager/Makefile
```

All child Makefiles include `config.mk` to get both environment configuration and reusable helpers.

## Usage

### Quick Start Workflow

```bash
# 1. Initialize k3s VM and registry (one-time)
make k3s

# 2. Deploy core infrastructure
make all

# 3. Deploy optional components as needed
make checkmk          # CheckMK monitoring
make mocks            # Mock applications
make web-shop         # Web-shop demo app
make netflow          # NetFlow simulator

# 4. Deploy OTel collectors
cd otel-operator
make apply

# 5. Manage collectors
make status           # Show all collector pods
make logs-gateway     # Tail gateway logs
make logs-postgres    # Tail postgres logs
make verify           # Verify data flow

# 6. Cleanup
make delete          # Delete collectors
make clean           # Delete optional components
make destroy         # Destroy VM
```

## Config.mk Helpers & Functions

All child Makefiles include `config.mk` for environment configuration + these helpers:

### kubectl Helpers

```makefile
# Apply manifest(s)
$(call kubectl_apply,path/to/file.yaml)

# Delete manifest(s) safely
$(call kubectl_delete,path/to/file.yaml)

# Tail pod logs
$(call kubectl_logs,NAMESPACE,deployment/app)

# Get pod by label
$(call kubectl_get_pod,NAMESPACE,app=myapp)

# Create namespace if missing
$(call kubectl_create_namespace,my-namespace)

# Delete namespace
$(call kubectl_delete_namespace,my-namespace)

# Pod status in namespace
$(call kubectl_pod_status,NAMESPACE)
```

### Helm Helpers

```makefile
# Add and update repo
$(call helm_repo,repo-name,https://charts.example.com)

# Install/upgrade release
$(call helm_install,release-name,chart-name,namespace,extra-flags)

# Uninstall release
$(call helm_uninstall,release-name,namespace)
```

### Output Formatting

```makefile
$(call HEADER,Message)    # ==> Message...
$(call SUCCESS,Message)   # ✓ Message
$(call INFO,Message)      # Message (indented)
```

## Consolidation Benefits

| Aspect | Before | After | Saved |
|--------|--------|-------|-------|
| **Total lines** | ~400 | ~280 | 30% |
| **Duplicated helm patterns** | 3× | 1× | ~20 lines |
| **Duplicated kubectl patterns** | 5× | 1× | ~30 lines |
| **logs-* targets** | 5 hardcoded | Dynamic | ~10 lines |
| **Status targets** | Scattered | Unified | ~15 lines |

## Example: Adding a New Component

To add a new component (e.g., `make my-app`):

```makefile
# apps/my-app/Makefile
include ../../config.mk

.PHONY: all deploy clean status

NAMESPACE_MY := my-app

all: deploy

deploy:
	$(call HEADER,Deploying my-app)
	$(call kubectl_apply,my-app.yaml)
	$(call SUCCESS,my-app deployed)

status:
	$(call status_template,My App,$(NAMESPACE_MY))

clean:
	$(call HEADER,Removing my-app)
	$(call kubectl_delete_namespace,$(NAMESPACE_MY))
	$(call SUCCESS,my-app cleaned up)
```

Then in main Makefile:

```makefile
my-app:
	@$(MAKE) -C $(SCRIPT_DIR)apps/my-app all
```

## OTel Operator Dynamic Logs

The `otel-operator/Makefile` now generates log targets dynamically:

```bash
make logs-gateway        # Tails gateway collector
make logs-postgres       # Tails postgres collector
make logs-kubernetes     # Tails kubernetes collector
make logs-netflow        # Tails netflow collector
make logs-logs           # Tails logs collector
```

This eliminates copy-paste and works even if collectors change.

## Best Practices

1. **Always include config.mk** in child Makefiles:
   ```makefile
   include ../config.mk  # Gets env config + helpers
   ```

2. **Use helpers instead of raw kubectl/helm**:
   ```makefile
   # ✓ Good
   $(call kubectl_apply,manifest.yaml)
   
   # ✗ Avoid
   kubectl apply -f manifest.yaml
   ```

3. **Organize targets by function**:
   ```makefile
   .PHONY: all deploy status clean
   
   all: deploy          # Default target
   deploy: ...          # Main action
   status: ...          # Monitoring
   clean: ...           # Cleanup
   ```

4. **Use .PHONY declarations** to prevent file conflicts

5. **Add descriptive comments** above each target

## Troubleshooting

### "include: config.mk: No such file or directory"

Check the path from your Makefile location:
```makefile
# From k3s-lab/apps/checkmk/Makefile
include ../../config.mk  # Go up 2 levels

# From k3s-lab/otel-operator/Makefile  
include ../config.mk     # Go up 1 level
```

### Helm/kubectl not found

Add to your shell:
```bash
export PATH="/path/to/helm:/path/to/kubectl:$PATH"
```

Or configure in config.mk:
```makefile
HELM := /usr/local/bin/helm
KUBECTL := /usr/local/bin/kubectl
```

## Future Improvements

- [ ] Add `make logs-web-shop` for app logs
- [ ] Create `make status-all` to show all components at once
- [ ] Add `make test` for validation  
- [ ] Create component dependency ordering (e.g., `make all` = k3s → otel → postgres → apps)
