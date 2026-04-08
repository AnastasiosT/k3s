# config.mk — shared config for all k3s Makefiles
#
# Included by:
#   k3s/Makefile          →  include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))config.mk
#   k3s/mocks/Makefile    →  include ../config.mk
#
# K3S_VM_IP is defined by Terraform (terraform/variables.tf).
# Override at runtime: make <target> K3S_VM_IP=x.x.x.x

CONFIG_DIR  := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
TF_DIR      := $(CONFIG_DIR)terraform

# VM configuration
VM_NAME     := checkmk-k3s
K3S_VM_IP   ?= 192.168.121.90

# CheckMK endpoint (for OTLP metric export from OTEL)
CHECKMK_HOST ?= 192.168.121.1:4317

# Detect current user (handle sudo case)
CURRENT_USER := $(shell if [ -n "$$SUDO_USER" ]; then echo $$SUDO_USER; else echo $$USER; fi)
USER_HOME    := $(shell echo ~$(CURRENT_USER))

REGISTRY    := 192.168.121.1:5000
KUBECONFIG  := $(USER_HOME)/.kube/config-k3s
KUBECTL     := kubectl --kubeconfig=$(KUBECONFIG)
HELM        := helm --kubeconfig=$(KUBECONFIG)

# Auto-discover mockup-apps relative to this repo (git/consultants/otel/k3s-lab → git/consultants/mockup-apps)
MOCKUP_APPS ?= $(dir $(CONFIG_DIR))../mockup-apps

# ============================================================
# Reusable Makefile Helpers (from common.mk)
# ============================================================

# Helper: Apply Kubernetes manifest(s)
define kubectl_apply
	$(KUBECTL) apply -f $(1)
endef

# Helper: Delete Kubernetes manifest(s) safely
define kubectl_delete
	$(KUBECTL) delete -f $(1) --ignore-not-found
endef

# Helper: Tail logs for any pod
define kubectl_logs
	$(KUBECTL) logs -n $(1) -f $(2)
endef

# Helper: Get pod by label
define kubectl_get_pod
	$(KUBECTL) get pods -n $(1) -l $(2) -o jsonpath='{.items[0].metadata.name}'
endef

# Helper: Create namespace if doesn't exist
define kubectl_create_namespace
	$(KUBECTL) create namespace $(1) --dry-run=client -o yaml | $(KUBECTL) apply -f -
endef

# Helper: Delete namespace
define kubectl_delete_namespace
	$(KUBECTL) delete namespace $(1) --ignore-not-found
endef

# Helper: Get status of pods in namespace
define kubectl_pod_status
	$(KUBECTL) get pods -n $(1) --no-headers 2>/dev/null || echo "(not deployed)"
endef

# Helper: Helm add/update repo
define helm_repo
	@$(HELM) repo add $(1) $(2) 2>/dev/null || true
	@$(HELM) repo update
endef

# Helper: Helm install/upgrade
define helm_install
	$(HELM) upgrade --install $(1) $(2) \
		--namespace $(3) --create-namespace \
		--wait --timeout $(TIMEOUT) \
		$(4)
endef

# Helper: Helm uninstall
define helm_uninstall
	$(HELM) uninstall $(1) -n $(2) || true
endef

# ============================================================
# Output Formatting Helpers
# ============================================================

HEADER = @echo "==> $(1)..."
SUCCESS = @echo "✓ $(1)"
INFO = @echo "   $(1)"

# Helper: Status template - print pod/svc status for component
define status_template
	@echo "==> $(1):"
	@$(KUBECTL) get pods,svc -n $(2) 2>/dev/null || echo "    (not deployed)"
endef
