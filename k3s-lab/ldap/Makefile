.PHONY: help deploy delete status logs test-connection port-forward

NAMESPACE := ldap
LDAP_POD := openldap-0
LAM_POD := $(shell kubectl get pod -n $(NAMESPACE) -l app=lam -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
K3S_NODE_IP := 192.168.121.90

help:
	@echo "LDAP Kubernetes Management"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  deploy              Apply all LDAP manifests"
	@echo "  delete              Delete all LDAP resources"
	@echo "  status              Show pod and service status"
	@echo "  logs-ldap           View OpenLDAP logs"
	@echo "  logs-lam            View LAM logs"
	@echo "  logs-init           View LDAP init job logs"
	@echo "  test-connection     Test LDAP connection from pod"
	@echo "  port-forward        Port-forward LAM web UI (http://localhost:8082)"
	@echo "  restart-ldap        Restart OpenLDAP pod"
	@echo "  restart-lam         Restart LAM deployment"
	@echo "  describe-ldap       Describe OpenLDAP pod"
	@echo "  describe-lam        Describe LAM pod"
	@echo "  access-info         Show access information"

deploy:
	@echo "Deploying LDAP stack..."
	kubectl apply -f .

delete:
	@echo "Deleting LDAP stack..."
	kubectl delete -f . --ignore-not-found=true
	@echo "LDAP stack deleted"

status:
	@echo "=== LDAP Namespace Status ==="
	@kubectl get pods -n $(NAMESPACE)
	@echo ""
	@echo "=== Services ==="
	@kubectl get svc -n $(NAMESPACE)
	@echo ""
	@echo "=== Ingress ==="
	@kubectl get ingress -n $(NAMESPACE)

logs-ldap:
	kubectl logs -n $(NAMESPACE) $(LDAP_POD) -f

logs-lam:
	kubectl logs -n $(NAMESPACE) -l app=lam -f

logs-init:
	kubectl logs -n $(NAMESPACE) job/ldap-init -f

test-connection:
	@echo "Testing LDAP connection..."
	kubectl exec -it $(LDAP_POD) -n $(NAMESPACE) -- ldapsearch \
		-x -H ldap://localhost:389 \
		-D "cn=admin,dc=cmk,dc=dev,dc=de" \
		-w ldapadmin \
		-b "dc=cmk,dc=dev,dc=de" \
		-s base

port-forward:
	@echo "Port-forwarding LAM to http://localhost:8082"
	@echo "Press Ctrl+C to stop"
	kubectl port-forward -n $(NAMESPACE) svc/lam 8082:80

restart-ldap:
	@echo "Restarting OpenLDAP..."
	kubectl rollout restart statefulset/openldap -n $(NAMESPACE)
	kubectl rollout status statefulset/openldap -n $(NAMESPACE)

restart-lam:
	@echo "Restarting LAM..."
	kubectl rollout restart deployment/lam -n $(NAMESPACE)
	kubectl rollout status deployment/lam -n $(NAMESPACE)

describe-ldap:
	kubectl describe pod $(LDAP_POD) -n $(NAMESPACE)

describe-lam:
	kubectl describe pod $(LAM_POD) -n $(NAMESPACE)

access-info:
	@echo "=== LDAP Access Information ==="
	@echo ""
	@echo "LAM Web UI:"
	@echo "  Internal (with port-forward): http://localhost:8082"
	@echo "  With Ingress: https://ldap.k3s.local"
	@echo "  Credentials: cn=admin,dc=cmk,dc=dev,dc=de / ldapadmin"
	@echo ""
	@echo "LDAP Server:"
	@echo "  Internal: ldap://openldap.ldap.svc.cluster.local:389"
	@echo "  External (NodePort): ldap://$(K3S_NODE_IP):30389"
	@echo "  Bind DN: cn=admin,dc=cmk,dc=dev,dc=de"
	@echo "  Password: ldapadmin"
	@echo ""
	@echo "Add to /etc/hosts for Ingress:"
	@echo "  $(K3S_NODE_IP) ldap.k3s.local"
