# Makefile — cert-manager PKI setup
#
# Apply in order: make all
# Or step by step if needed.
#
# Usage:
#   make all          → install cert-manager + full PKI chain + wildcard cert + traefik TLS
#   make install      → install cert-manager via helm
#   make pki          → deploy root CA → intermediate CA → issuers
#   make wildcard     → issue wildcard cert
#   make traefik-tls  → configure Traefik default cert (TLSStore)
#   make reflector    → install reflector + patch secret for auto-sync
#   make status       → show all cert-manager resources
#   make clean        → uninstall cert-manager and remove PKI resources

SCRIPT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
include $(SCRIPT_DIR)../../config.mk
include $(SCRIPT_DIR)../../common.mk

.PHONY: all install pki wildcard traefik-tls reflector status clean

all: install pki wildcard traefik-tls reflector

## Install cert-manager via helm
install:
	@echo "==> Installing cert-manager..."
	@$(HELM) repo add jetstack https://charts.jetstack.io 2>/dev/null || true
	@$(HELM) repo update
	$(HELM) upgrade --install cert-manager jetstack/cert-manager \
		--namespace cert-manager --create-namespace \
		--set crds.enabled=true \
		--wait

## Deploy PKI chain: selfsigned → root CA → root issuer → intermediate CA → intermediate issuer
pki:
	@echo "==> Deploying PKI chain..."
	$(KUBECTL) apply -f $(SCRIPT_DIR)selfsigned-issuer.yaml
	@sleep 2
	$(KUBECTL) apply -f $(SCRIPT_DIR)root-ca.yaml
	$(KUBECTL) wait --for=condition=Ready certificate/root-ca -n cert-manager --timeout=60s
	$(KUBECTL) apply -f $(SCRIPT_DIR)root-ca-issuer.yaml
	@sleep 2
	$(KUBECTL) apply -f $(SCRIPT_DIR)intermediate-ca.yaml
	$(KUBECTL) wait --for=condition=Ready certificate/intermediate-ca -n cert-manager --timeout=60s
	$(KUBECTL) apply -f $(SCRIPT_DIR)intermediate-ca-issuer.yaml

## Issue wildcard cert
wildcard:
	@echo "==> Issuing wildcard cert..."
	$(KUBECTL) apply -f $(SCRIPT_DIR)wildcard-cert.yaml
	$(KUBECTL) wait --for=condition=Ready certificate/wildcard-local -n cert-manager --timeout=60s
	@echo "    Done. Import root CA into browser:"
	@echo "    kubectl get secret root-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/k3s-root-ca.crt"

## Configure Traefik default cert (fixes full chain sending)
traefik-tls:
	@echo "==> Configuring Traefik TLS store..."
	$(KUBECTL) apply -f $(SCRIPT_DIR)tls-store.yaml
	$(KUBECTL) rollout restart deployment/traefik -n kube-system

## Install reflector + annotate wildcard secret for auto-sync
reflector:
	@echo "==> Installing reflector..."
	@$(HELM) repo add emberstack https://emberstack.github.io/helm-charts 2>/dev/null || true
	@$(HELM) repo update
	$(HELM) upgrade --install reflector emberstack/reflector --namespace kube-system --wait
	@echo "==> Patching wildcard secret for auto-sync..."
	$(KUBECTL) apply -f $(SCRIPT_DIR)reflector-patch.yaml

## Show all cert-manager resources
status:
	@echo "==> ClusterIssuers:"
	@$(KUBECTL) get clusterissuer
	@echo ""
	@echo "==> Certificates:"
	@$(KUBECTL) get certificate -n cert-manager
	@echo ""
	@echo "==> Secrets:"
	@$(KUBECTL) get secret -n cert-manager | grep -E "tls|ca"

## Uninstall cert-manager and remove PKI resources
clean:
	$(KUBECTL) delete -f $(SCRIPT_DIR)wildcard-cert.yaml || true
	$(KUBECTL) delete -f $(SCRIPT_DIR)intermediate-ca-issuer.yaml || true
	$(KUBECTL) delete -f $(SCRIPT_DIR)intermediate-ca.yaml || true
	$(KUBECTL) delete -f $(SCRIPT_DIR)root-ca-issuer.yaml || true
	$(KUBECTL) delete -f $(SCRIPT_DIR)root-ca.yaml || true
	$(KUBECTL) delete -f $(SCRIPT_DIR)selfsigned-issuer.yaml || true
	$(KUBECTL) delete -f $(SCRIPT_DIR)tls-store.yaml || true
	$(HELM) uninstall cert-manager -n cert-manager || true
	$(HELM) uninstall reflector -n kube-system || true
