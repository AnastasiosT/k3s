# CheckMK monitoring - includes config.mk for helpers
include ../../config.mk

.PHONY: all deploy status clean

RELEASE_NAME ?= myrelease
RELEASE_NS ?= checkmk-monitoring
CHART_REPO ?= https://checkmk.github.io/checkmk_kube_agent
CHART_NAME ?= checkmk-chart/checkmk

all: deploy

deploy:
	$(call HEADER,Deploying CheckMK monitoring)
	$(call helm_repo,checkmk-chart,$(CHART_REPO))
	$(call helm_install,$(RELEASE_NAME),$(CHART_NAME),$(RELEASE_NS), \
		--set containerdOverride="/run/k3s/containerd/containerd.sock" \
		--set clusterCollector.service.type="NodePort" \
		--set clusterCollector.service.nodePort="30035")
	$(call SUCCESS,CheckMK monitoring deployed)
	@echo ""
	@echo "Get token:"
	@echo "  kubectl -n $(RELEASE_NS) get secret $(RELEASE_NAME)-checkmk-checkmk -o jsonpath='{.data.token}' | base64 -d"

status:
	$(call status_template,CheckMK,$(RELEASE_NS))

clean:
	$(call HEADER,Removing CheckMK monitoring)
	$(call helm_uninstall,$(RELEASE_NAME),$(RELEASE_NS))
	$(call kubectl_delete_namespace,$(RELEASE_NS))
	$(call SUCCESS,CheckMK removed)
