#!/bin/bash

# Setup a local Docker registry for k3s image management
# This allows you to build images locally and push them to the registry
# accessible from your k3s cluster

REGISTRY_PORT="${1:-5000}"
REGISTRY_DATA_DIR="${2:-./registry-data}"

echo "========================================="
echo "Setting up local Docker Registry"
echo "========================================="
echo ""
echo "Configuration:"
echo "  Port: $REGISTRY_PORT"
echo "  Data directory: $REGISTRY_DATA_DIR"
echo ""

# Create data directory if it doesn't exist
mkdir -p "$REGISTRY_DATA_DIR"

# Stop and remove existing registry container (if any)
echo "1️⃣  Checking for existing registry container..."
if docker ps -a --filter "name=local-registry" | grep -q local-registry; then
    echo "   Removing existing registry container..."
    docker rm -f local-registry 2>/dev/null || true
fi

# Start new registry
echo ""
echo "2️⃣  Starting local Docker registry..."
docker run -d \
    --name local-registry \
    --restart=always \
    -p "$REGISTRY_PORT:5000" \
    -v "$REGISTRY_DATA_DIR":/var/lib/registry \
    registry:2

# Wait for registry to be ready
echo ""
echo "3️⃣  Waiting for registry to be ready..."
for i in {1..10}; do
    if curl -s http://localhost:"$REGISTRY_PORT"/v2/ > /dev/null 2>&1; then
        echo "   ✅ Registry is ready!"
        break
    fi
    echo "   Attempt $i/10... waiting..."
    sleep 1
done

# Configure k3s to use insecure registry
echo ""
echo "4️⃣  Configuring k3s for insecure registry..."
echo ""
echo "   Your k3s host will need to trust the insecure registry."
echo "   If k3s is running on this machine, add to /etc/rancher/k3s/registries.yaml:"
echo ""
echo "   mirrors:"
echo "     localhost:$REGISTRY_PORT:"
echo "       endpoint:"
echo "         - \"http://localhost:$REGISTRY_PORT\""
echo ""

# Test the registry
echo ""
echo "5️⃣  Testing registry..."
HEALTH=$(curl -s http://localhost:"$REGISTRY_PORT"/v2/ | wc -c)
if [ "$HEALTH" -gt 0 ]; then
    echo "   ✅ Registry is responding correctly"
else
    echo "   ❌ Registry may not be responding"
fi

echo ""
echo "========================================="
echo "✅ Local registry is ready!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. If your k3s is on a different machine, configure it to use this registry"
echo "2. Tag and push images to: localhost:$REGISTRY_PORT/<image-name>:<tag>"
echo "3. Use in deployments with image: localhost:$REGISTRY_PORT/<image-name>:<tag>"
echo ""
echo "Example:"
echo "  docker build -t localhost:$REGISTRY_PORT/ldap-monitor:latest ./ldap-monitor"
echo "  docker push localhost:$REGISTRY_PORT/ldap-monitor:latest"
echo ""
echo "Registry details:"
echo "  Container: docker logs local-registry"
echo "  Stop: docker stop local-registry"
echo "  Remove: docker rm local-registry"
echo ""
