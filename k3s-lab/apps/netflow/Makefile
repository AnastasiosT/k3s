# NetFlow - includes config.mk for helpers
include ../../config.mk

.PHONY: all deploy status clean

NAMESPACE_NF := netflow

all: deploy

deploy:
	$(call HEADER,Creating NetFlow namespace)
	$(call kubectl_create_namespace,$(NAMESPACE_NF))
	$(call HEADER,Deploying NetFlow simulator)
	$(call kubectl_apply,netflow-simulator.yaml)
	$(call SUCCESS,NetFlow simulator deployed)
	@echo ""
	@echo "Check logs:"
	@echo "  kubectl logs -n $(NAMESPACE_NF) deployment/netflow-python-simulator -f"

status:
	$(call status_template,NetFlow,$(NAMESPACE_NF))

clean:
	$(call HEADER,Removing NetFlow namespace)
	$(call kubectl_delete_namespace,$(NAMESPACE_NF))
	$(call SUCCESS,NetFlow cleaned up)
