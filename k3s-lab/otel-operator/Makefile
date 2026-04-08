# OTel Operator Collectors - includes config.mk for helpers
include ../config.mk

.PHONY: operator-install apply delete status logs-gateway logs-postgres logs-kubernetes logs-netflow logs-logs verify test-metrics uninstall help

NAMESPACE := otel-collectors
OPERATOR_NAMESPACE := opentelemetry-operator-system

COLLECTORS := gateway postgres kubernetes netflow logs

# Generate logs-* targets dynamically
$(foreach col,$(COLLECTORS),$(eval \
	logs-$(col): \
		$$(call HEADER,Logs for $(col)-collector); \
		$$(KUBECTL) logs -n $$(NAMESPACE) -f deployment/$(col)-collector 2>/dev/null || \
		$$(KUBECTL) logs -n $$(NAMESPACE) -f daemonset/$(col)-collector \
	.PHONY: logs-$(col) \
))

# Install OTel Operator
operator-install:
	$(call HEADER,Installing OTel Operator)
	$(call helm_repo,open-telemetry,https://open-telemetry.github.io/opentelemetry-helm-charts)
	$(HELM) install opentelemetry-operator open-telemetry/opentelemetry-operator \
		--namespace $(OPERATOR_NAMESPACE) --create-namespace --wait
	$(call SUCCESS,OTel Operator installed)

# Apply all collector CRs
apply:
	$(call kubectl_apply,namespace.yaml)
	$(call kubectl_apply,gateway.yaml)
	$(call kubectl_apply,postgres.yaml)
	$(call kubectl_apply,kubernetes.yaml)
	$(call kubectl_apply,netflow.yaml)
	$(call kubectl_apply,logs.yaml)
	$(call kubectl_apply,instrumentation.yaml)
	$(call SUCCESS,All collectors deployed)

# Delete all collector CRs
delete:
	$(call kubectl_delete,instrumentation.yaml)
	$(call kubectl_delete,logs.yaml)
	$(call kubectl_delete,netflow.yaml)
	$(call kubectl_delete,kubernetes.yaml)
	$(call kubectl_delete,postgres.yaml)
	$(call kubectl_delete,gateway.yaml)
	$(call kubectl_delete,namespace.yaml)
	$(call SUCCESS,All collectors deleted)

# Show collector status
status:
	@echo "=== Operator Status ==="
	$(call kubectl_pod_status,$(OPERATOR_NAMESPACE))
	@echo ""
	@echo "=== Collectors Status ==="
	$(KUBECTL) get opentelemetrycollectors -n $(NAMESPACE)
	@echo ""
	@echo "=== Collector Pods ==="
	$(KUBECTL) get pods -n $(NAMESPACE)

# Verify collectors are communicating
verify:
	$(call HEADER,Checking gateway collector for incoming data)
	$(KUBECTL) logs -n $(NAMESPACE) deployment/gateway-collector --tail=50 | grep -E "otlp|receiver|export" | head -10

# Test metrics export
test-metrics:
	$(call HEADER,Sending test metric to gateway collector)
	$(KUBECTL) port-forward -n $(NAMESPACE) svc/gateway-collector 4317:4317 &
	sleep 2
	otelcontribcol validate --config=test-config.yaml
	pkill -f "port-forward"

# Uninstall OTel Operator
uninstall:
	$(call HEADER,Removing OTel Operator)
	$(call helm_uninstall,opentelemetry-operator,$(OPERATOR_NAMESPACE))
	$(call kubectl_delete_namespace,$(OPERATOR_NAMESPACE))
	$(call SUCCESS,OTel Operator removed)

help:
	@echo "OTel Operator Collectors - Makefile commands"
	@echo ""
	@echo "Setup:"
	@echo "  make operator-install    - Install OTel Operator (one-time)"
	@echo "  make apply              - Deploy all collector CRs"
	@echo ""
	@echo "Management:"
	@echo "  make delete             - Delete all collector CRs"
	@echo "  make status             - Show collector status"
	@echo "  make verify             - Verify data flow"
	@echo ""
	@echo "Debugging (dynamic):"
	@echo "  make logs-COLLECTOR     - Tail logs (gateway|postgres|kubernetes|netflow|logs)"
	@echo ""
	@echo "Uninstall:"
	@echo "  make uninstall          - Remove OTel Operator"

.DEFAULT_GOAL := help
