#!/bin/bash
set -e

# Build and push script for Azure ACR
# Usage: ./scripts/build-push.sh

PROJECT_NAME="dotnet_jwt_mcont2_1929"

# Sanitize project name to a valid image name
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

# Ask for registry details
read -p "Enter Azure ACR name (ACR_NAME): " ACR_NAME
read -p "Enter image tag (press Enter for latest): " IMAGE_TAG

# Sanitize tag: empty means latest
if [ -z "$IMAGE_TAG" ]; then
    IMAGE_TAG="latest"
fi

# Sanitize tag
IMAGE_TAG=$(echo "$IMAGE_TAG" | tr -cs 'a-z0-9._-' '-' | sed 's/^-*//;s/-*$//')

FULL_IMAGE_NAME="${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"

echo "=== Building Docker image: $FULL_IMAGE_NAME ==="
docker build -f Dockerfile -t "$FULL_IMAGE_NAME" .

echo "=== Logging in to Azure ACR: $ACR_NAME ==="
az acr login --name "$ACR_NAME"

echo "=== Pushing Docker image: $FULL_IMAGE_NAME ==="
docker push "$FULL_IMAGE_NAME"

echo "=== Build and push complete ==="
echo "Image: $FULL_IMAGE_NAME"
