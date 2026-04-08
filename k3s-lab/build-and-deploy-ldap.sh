#!/bin/bash
set -e

# Configuration
REGISTRY="${DOCKER_REGISTRY:-localhost:5000}"
IMAGE_NAME="ldap-monitor"
IMAGE_TAG="latest"
NAMESPACE="ldap"

echo "================================"
echo "OpenLDAP + LDAP Monitor Deployment"
echo "================================"
echo ""
echo "Configuration:"
echo "  Registry: $REGISTRY"
echo "  Image: $REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
echo "  Namespace: $NAMESPACE"
echo ""

# Step 1: Build the monitor image
echo "1️⃣  Building ldap-monitor image..."
cd "$(dirname "$0")/ldap-monitor"
docker build -t "$REGISTRY/$IMAGE_NAME:$IMAGE_TAG" .
cd - > /dev/null

# Step 2: Push to registry
echo ""
echo "2️⃣  Pushing image to registry..."
docker push "$REGISTRY/$IMAGE_NAME:$IMAGE_TAG"

# Step 3: Update deployment manifest with correct image
echo ""
echo "3️⃣  Updating deployment manifest..."
cd "$(dirname "$0")"
if [ "$REGISTRY" != "localhost:5000" ]; then
    sed -i.bak "s|image: ldap-monitor:latest|image: $REGISTRY/$IMAGE_NAME:$IMAGE_TAG|g" ldap-deployment.yaml
    echo "   Updated image reference to: $REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
fi

# Step 4: Deploy to k3s
echo ""
echo "4️⃣  Deploying to k3s..."
kubectl apply -f ldap-deployment.yaml

# Step 5: Wait for deployments to be ready
echo ""
echo "5️⃣  Waiting for deployments to be ready..."
kubectl rollout status deployment/lam -n $NAMESPACE --timeout=5m || true
kubectl rollout status deployment/ldap-monitor -n $NAMESPACE --timeout=5m || true

# Step 6: Wait for initialization job
echo ""
echo "6️⃣  Waiting for LDAP initialization..."
kubectl wait --for=condition=complete job/ldap-init -n $NAMESPACE --timeout=5m || true

# Step 7: Show deployment status
echo ""
echo "7️⃣  Deployment Status:"
echo "===================================="
kubectl get pods -n $NAMESPACE
echo ""
echo "Services:"
kubectl get svc -n $NAMESPACE
echo ""

# Step 8: Port-forward info
echo "===================================="
echo "✅ Deployment complete!"
echo ""
echo "Access services via port-forward:"
echo "  LDAP: kubectl port-forward -n ldap svc/openldap 389:389"
echo "  LAM Web UI: kubectl port-forward -n ldap svc/lam 8082:80"
echo "    Then visit: http://localhost:8082"
echo ""
echo "Quick checks:"
echo "  Check LDAP: kubectl exec -n ldap openldap-0 -- ldapsearch -x -H ldap://localhost:389 -D 'cn=admin,dc=cmk,dc=dev,dc=de' -w ldapadmin -b 'dc=cmk,dc=dev,dc=de' 'cn=ldap.site1.admin'"
echo "  Monitor logs: kubectl logs -n ldap -l app=ldap-monitor -f"
echo "  LDAP logs: kubectl logs -n ldap openldap-0"
echo ""
