#!/bin/bash
set -e
set -o pipefail

# Deploy script for Azure AKS
# Usage: ./scripts/deploy-image.sh

PROJECT_NAME="dotnet_jwt_mcont2_1929"
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s-*$//')

echo "=== Azure AKS Deployment ==="

# Ask for cluster details
read -p "Enter Azure resource group: " RESOURCE_GROUP
read -p "Enter AKS cluster name: " CLUSTER_NAME
read -p "Enter full image URI (registry/repo:tag): " IMAGE_URI

# Ask for environment variables
echo ""
echo "Enter values for the application's environment variables."
echo "Press Enter to skip (use default or leave unset)."
echo ""

read -p "Enter value for AppSettings__Secret (or press Enter to skip): " APPSETTINGS_SECRET

# Configure kubectl for the AKS cluster
echo ""
echo "=== Configuring kubectl for AKS cluster ==="
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME"
if [ $? -ne 0 ]; then
    echo "Failed to configure kubectl for AKS cluster"
    exit 1
fi

# Verify cluster connectivity
kubectl cluster-info || exit 1

# Create the namespace
echo ""
echo "=== Creating namespace ==="
kubectl apply -f kubernetes/namespace.yaml

# Create the Secret for credentials
echo ""
echo "=== Creating Kubernetes Secret ==="
SECRET_ARGS=""
if [ -n "$APPSETTINGS_SECRET" ]; then
    SECRET_ARGS="--from-literal=appsettings-secret=\"$APPSETTINGS_SECRET\""
fi

if [ -n "$SECRET_ARGS" ]; then
    kubectl create secret generic ${IMAGE_NAME}-secrets -n ${IMAGE_NAME} $SECRET_ARGS --dry-run=client -o yaml | kubectl apply -f -
else
    echo "No credentials provided. Skipping Secret creation."
    echo "You may need to create the secret manually before deploying."
fi

# Replace placeholders in deployment.yaml
echo ""
echo "=== Deploying application ==="
sed -i.bak 's|{{IMAGE_URI}}|'$IMAGE_URI'|g' kubernetes/deployment.yaml
sed -i.bak 's|{{NAMESPACE}}|'$IMAGE_NAME'|g' kubernetes/deployment.yaml

# Add env var placeholders if provided
if [ -n "$APPSETTINGS_SECRET" ]; then
    : # Secret is handled via secretKeyRef, no placeholder needed
fi

# Clean up backup files
rm -f kubernetes/deployment.yaml.bak

# Apply deployment, service, and ingress
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/ingress.yaml

# Wait for rollout
echo ""
echo "=== Waiting for rollout ==="
kubectl rollout status deployment/${IMAGE_NAME} -n ${IMAGE_NAME}

# Show deployment info
echo ""
echo "=== Deployment status ==="
kubectl get pods,svc,ingress -n ${IMAGE_NAME}

# Show application URL
echo ""
echo "=== Application URL ==="
INGRESS_IP=$(kubectl get ingress ${IMAGE_NAME}-ingress -n ${IMAGE_NAME} -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
if [ "$INGRESS_IP" != "pending" ] && [ -n "$INGRESS_IP" ]; then
    echo "Application URL: http://${INGRESS_IP}"
else
    echo "Application URL: https://${IMAGE_NAME}.example.com (may take a moment to become available)"
fi

echo ""
echo "=== Deployment complete ==="
echo "To rollback on failure: kubectl rollout undo deployment/${IMAGE_NAME} -n ${IMAGE_NAME}"
