# Makefile — k3s OTel + PostgreSQL + monitoring setup
#
# Usage:
#   make k3s        → start registry + VM (once)
#   make all        → deploy core infrastructure (kubeconfig, TLS, OTel)
#   make postgres   → deploy PostgreSQL
#   make stop       → halt VM + stop registry
#   make destroy    → destroy VM completely + stop registry
#   make status     → check pod status
#
# Optional:
#   make checkmk    → deploy CheckMK monitoring
#   make mocks      → deploy mock applications (netapp-mock)
#   make web-shop   → deploy OTel demo app (frontend + backend)
#   make cmdb       → deploy CMDB with test devices
#   make netflow    → deploy NetFlow collector (NetFlow v5/v9/IPFIX + sFlow)

SCRIPT_DIR    := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
include $(SCRIPT_DIR)config.mk
APP_DIR       ?= $(SCRIPT_DIR)apps/flask-web-shop/src
DATABASES_DIR := $(SCRIPT_DIR)databases

export KUBECONFIG

.PHONY: all k3s stop destroy status postgres checkmk checkmk-endpoint mocks web-shop cmdb netflow

## Start registry + k3s VM
k3s:
	@echo "==> Configuring Docker to allow HTTP registry at $(REGISTRY)..."
	@CONFIG_CHANGED=false; \
	if [ -f /etc/docker/daemon.json ]; then \
		if ! grep -q "$(REGISTRY)" /etc/docker/daemon.json; then \
			CONFIG_CHANGED=true; \
			tmp=$$(mktemp); \
			jq --arg reg "$(REGISTRY)" '.["insecure-registries"] = ((.["insecure-registries"] // []) + [$$reg] | unique)' /etc/docker/daemon.json > $$tmp && \
			sudo mv $$tmp /etc/docker/daemon.json || { rm -f $$tmp; echo "ERROR: Failed to update daemon.json"; exit 1; }; \
		fi; \
	else \
		CONFIG_CHANGED=true; \
		echo '{"insecure-registries": ["$(REGISTRY)"]}' | sudo tee /etc/docker/daemon.json > /dev/null; \
	fi; \
	if [ "$$CONFIG_CHANGED" = "true" ]; then \
		echo "==> Restarting Docker daemon..."; \
		sudo systemctl restart docker || { echo "ERROR: Failed to restart docker"; exit 1; }; \
	else \
		echo "    Docker already configured."; \
	fi
	@echo "==> Checking local registry..."
	@if sudo docker ps | grep -q k3s-registry; then \
		echo "    Registry already running, skipping."; \
	else \
		echo "    Starting registry..."; \
		sudo docker compose -f $(SCRIPT_DIR)docker-compose.yml up -d registry; \
	fi
	@echo "==> Starting k3s VM (4GB, 3 CPUs, 100GB disk)..."
	@cd $(SCRIPT_DIR) && vagrant up
	@echo ""
	@echo "==> Fetching kubeconfig from k3s VM..."
	@mkdir -p $(USER_HOME)/.kube
	@ssh vagrant@$(K3S_VM_IP) "sudo cat /etc/rancher/k3s/k3s.yaml" \
		| sed "s/127.0.0.1/$(K3S_VM_IP)/g" \
		| sed "s/certificate-authority-data:.*/insecure-skip-tls-verify: true/" > $(KUBECONFIG).tmp
	@if [ ! -s $(KUBECONFIG).tmp ]; then \
		rm -f $(KUBECONFIG).tmp; \
		echo "ERROR: kubeconfig is empty — is the VM running?"; \
		exit 1; \
	fi
	@mv $(KUBECONFIG).tmp $(KUBECONFIG)
	@chmod 644 $(KUBECONFIG)
	@echo "    Saved to $(KUBECONFIG)"
	@if [ "$$(id -u)" -eq 0 ]; then \
		echo "    Fixing ownership for $(CURRENT_USER)..."; \
		chown $(CURRENT_USER):$(CURRENT_USER) $(KUBECONFIG) $(USER_HOME)/.kube 2>/dev/null || true; \
	fi
	@echo ""
	@echo "✓ k3s is ready! kubectl is configured."
	@echo ""
	@echo "To use kubectl automatically, add to your shell profile:"
	@echo "  echo 'export KUBECONFIG=~/.kube/config-k3s' >> ~/.zshrc"
	@echo "  source ~/.zshrc"
	@echo ""
	@echo "Or for this session only:"
	@echo "  export KUBECONFIG=~/.kube/config-k3s"
	@echo "  kubectl get nodes"

## Halt VM + stop registry
stop:
	@echo "==> Halting k3s VM..."
	@cd $(SCRIPT_DIR) && vagrant halt
	@echo "==> Stopping local registry..."
	@sudo docker compose -f $(SCRIPT_DIR)docker-compose.yml stop registry

## Destroy VM completely + stop registry
destroy:
	@echo "==> Destroying k3s VM..."
	@cd $(SCRIPT_DIR) && vagrant destroy -f
	@echo "==> Stopping local registry..."
	@sudo docker compose -f $(SCRIPT_DIR)docker-compose.yml stop registry

## Deploy core infrastructure (kubeconfig, TLS, OTel)
all:
	@echo "==> Fetching kubeconfig from k3s VM..."
	@mkdir -p $(HOME)/.kube
	@ssh vagrant@$(K3S_VM_IP) "sudo cat /etc/rancher/k3s/k3s.yaml" \
		| sed "s/127.0.0.1/$(K3S_VM_IP)/g" \
		| sed "s/certificate-authority-data:.*/insecure-skip-tls-verify: true/" > $(KUBECONFIG).tmp
	@if [ ! -s $(KUBECONFIG).tmp ]; then \
		rm -f $(KUBECONFIG).tmp; \
		echo "ERROR: kubeconfig is empty — is the VM running? (make k3s)"; \
		exit 1; \
	fi
	@mv $(KUBECONFIG).tmp $(KUBECONFIG)
	@chmod 600 $(KUBECONFIG)
	@echo "    Saved to $(KUBECONFIG)"
	@echo ""
	@$(MAKE) -C $(SCRIPT_DIR)optional-examples/certmanager all
	@echo ""
	@echo "==> Deploying OTel collectors..."
	@if ! $(HELM) repo list 2>/dev/null | grep -q open-telemetry; then \
		$(HELM) repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts; \
	fi
	@$(HELM) repo update
	$(HELM) upgrade --install otel-node open-telemetry/opentelemetry-collector \
		--namespace otel-monitoring --create-namespace \
		--values $(SCRIPT_DIR)otel/values-node.yaml \
		--wait --timeout 120s
	$(HELM) upgrade --install otel-cluster open-telemetry/opentelemetry-collector \
		--namespace otel-monitoring --create-namespace \
		--values $(SCRIPT_DIR)otel/values-cluster.yaml \
		--wait --timeout 120s
	@$(MAKE) status
	@echo ""
	@echo "✓ Core infrastructure deployed!"
	@echo ""
	@echo "Next steps:"
	@echo "  - make postgres    (deploy PostgreSQL)"
	@echo "  - make mocks       (deploy mock applications)"
	@echo ""

## Deploy PostgreSQL
postgres:
	@echo "==> Deploying PostgreSQL via Helm..."
	$(HELM) upgrade --install postgres $(SCRIPT_DIR)charts/postgres \
		--namespace postgres --create-namespace \
		--wait --timeout 120s
	@$(MAKE) status
	@echo ""
	@echo "✓ PostgreSQL deployed!"
	@echo ""

## Show all pods across relevant namespaces
status:
	@echo "==> OTel collectors:"
	@$(KUBECTL) get pods -n otel-monitoring 2>/dev/null || echo "    (not deployed)"
	@echo ""
	@echo "==> NetFlow collector:"
	@$(KUBECTL) get pods -n netflow 2>/dev/null || echo "    (not deployed)"
	@echo ""
	@echo "==> Demo app:"
	@$(KUBECTL) get pods -n flask-web-shop 2>/dev/null || echo "    (not deployed)"
	@echo ""
	@echo "==> PostgreSQL:"
	@$(KUBECTL) get pods -n postgres 2>/dev/null || echo "    (not deployed)"

## Optional: Deploy CheckMK monitoring
checkmk:
	@$(MAKE) -C $(SCRIPT_DIR)apps/checkmk all

## Configure OTEL to export metrics to CheckMK
checkmk-endpoint:
	@echo "==> Updating OTEL exporter to send metrics to $(CHECKMK_HOST)..."
	@$(KUBECTL) -n otel-monitoring get configmap otel-cluster-opentelemetry-collector -o yaml | \
		sed 's|endpoint: checkmk.k3s.local:4317|endpoint: $(CHECKMK_HOST)|g' | \
		$(KUBECTL) apply -f -
	@$(KUBECTL) rollout restart deployment/otel-cluster-opentelemetry-collector -n otel-monitoring
	@$(KUBECTL) rollout status deployment/otel-cluster-opentelemetry-collector -n otel-monitoring --timeout=120s
	@echo "✓ OTEL configured to send metrics to $(CHECKMK_HOST)"

## Optional: Deploy mock applications
mocks:
	@$(MAKE) -C $(SCRIPT_DIR)optional-examples/mocks all

## Optional: Deploy OTel demo app (frontend + backend with tracing)
web-shop: postgres
	@echo "==> Building demo app images..."
	@cd /home/anastasios/git/consultants/otel/otel-test-lab/otelstack/docker/demo-app && \
		docker build -t $(REGISTRY)/demo-app-backend:latest ./backend && \
		docker push $(REGISTRY)/demo-app-backend:latest && \
		docker build -t $(REGISTRY)/demo-app-frontend:latest ./frontend && \
		docker push $(REGISTRY)/demo-app-frontend:latest
	@echo "==> Initializing database..."
	@$(KUBECTL) apply -f $(SCRIPT_DIR)apps/web-shop/db-init.yaml
	@echo "==> Deploying demo app..."
	@$(KUBECTL) apply -f $(SCRIPT_DIR)apps/web-shop/demo-app.yaml
	@$(KUBECTL) apply -f $(SCRIPT_DIR)apps/web-shop/postgres-secret-reflector.yaml
	@$(KUBECTL) apply -f $(SCRIPT_DIR)apps/web-shop/load-generator.yaml
	@$(KUBECTL) rollout status deployment/backend -n web-shop --timeout=120s
	@$(KUBECTL) rollout status deployment/frontend -n web-shop --timeout=120s
	@echo ""
	@echo "✓ Demo app deployed with load generator!"
	@echo ""
	@echo "Access at: https://web-shop.k3s.local"
	@echo "Add to /etc/hosts: 192.168.121.90 web-shop.k3s.local"
	@echo ""

## Optional: Deploy NetFlow collector + simulator (NetFlow v5 + sFlow)
netflow:
	@$(MAKE) -C $(SCRIPT_DIR)apps/netflow all

## Optional: Deploy CMDB + initialize with test devices
cmdb:
	@echo "==> Deploying CMDB..."
	@$(KUBECTL) apply -f $(SCRIPT_DIR)apps/cmdb/cmdb.yaml
	@$(KUBECTL) rollout status deployment/cmdb -n cmdb --timeout=120s
	@echo "==> Initializing with test devices..."
	@$(KUBECTL) apply -f $(SCRIPT_DIR)apps/cmdb/init-devices.yaml
	@$(KUBECTL) wait --for=condition=complete job/cmdb-init-devices -n cmdb --timeout=120s
	@echo ""
	@echo "✓ CMDB deployed with 6 test devices!"
	@echo ""
	@echo "Access at: https://cmdb.k3s.local/api/devices"
	@echo "Add to /etc/hosts: 192.168.121.90 cmdb.k3s.local"
	@echo ""
