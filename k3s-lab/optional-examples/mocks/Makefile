# Makefile — mockups → k3s
#
# Usage:
#   make all           → build + deploy all mocks
#   make netapp        → build + deploy netapp-mock
#   make build-netapp  → build and push netapp-mock image
#   make deploy-netapp → apply netapp-mock k8s manifest
#   make status        → show pods for all mocks
#   make clean         → delete all mock namespaces

SCRIPT_DIR  := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
include $(SCRIPT_DIR)../../config.mk
include $(SCRIPT_DIR)../../common.mk

.PHONY: all netapp build-netapp deploy-netapp status clean

all: netapp

## netapp-mock
netapp: build-netapp deploy-netapp

build-netapp:
	@echo "==> Building netapp-mock image..."
	docker build -t $(REGISTRY)/netapp-mock:latest $(MOCKUP_APPS)/netapp-mock
	docker push $(REGISTRY)/netapp-mock:latest

deploy-netapp:
	@echo "==> Deploying netapp-mock..."
	$(KUBECTL) apply -f $(SCRIPT_DIR)netapp-mock/netapp-mock.yaml
	$(KUBECTL) rollout status deployment/netapp-mock -n netapp-mock --timeout=60s

## Status + cleanup
status:
	@echo "==> netapp-mock:"
	@$(KUBECTL) get pods,svc -n netapp-mock 2>/dev/null || echo "    (not deployed)"

clean:
	$(KUBECTL) delete namespace netapp-mock || true
