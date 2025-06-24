#!/bin/bash

# Script to rebuild and push Docker image with correct architecture (linux/amd64)
# Use this if you need to fix an existing deployment with architecture issues

set -e  # Exit on any error

# Configuration
APPLICATION_NAME="gcs-assist"
ENVIRONMENT="dev"   # Change to qa or prod as needed
RESOURCE_GROUP_NAME="rg-${APPLICATION_NAME}-${ENVIRONMENT}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "=========================================="
echo "Rebuilding Docker Image with AMD64 Architecture"
echo "Environment: $ENVIRONMENT"
echo "=========================================="

# Get container registry details
print_status "Getting container registry details..."
CONTAINER_REGISTRY_NAME=$(az resource list \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --resource-type "Microsoft.ContainerRegistry/registries" \
    --query "[0].name" \
    --output tsv)

if [ -z "$CONTAINER_REGISTRY_NAME" ]; then
    print_error "Container registry not found in resource group $RESOURCE_GROUP_NAME"
    exit 1
fi

CONTAINER_REGISTRY_LOGIN_SERVER=$(az acr show \
    --name "$CONTAINER_REGISTRY_NAME" \
    --query "loginServer" \
    --output tsv)

print_success "Found container registry: $CONTAINER_REGISTRY_NAME"
print_status "Login server: $CONTAINER_REGISTRY_LOGIN_SERVER"

# Get ACR credentials and login
print_status "Logging into Container Registry..."
ACR_PASSWORD=$(az acr credential show --name "$CONTAINER_REGISTRY_NAME" --query "passwords[0].value" --output tsv)
ACR_USERNAME=$(az acr credential show --name "$CONTAINER_REGISTRY_NAME" --query "username" --output tsv)

echo "$ACR_PASSWORD" | docker login "$CONTAINER_REGISTRY_LOGIN_SERVER" --username "$ACR_USERNAME" --password-stdin

# Remove existing image locally if it exists
print_status "Cleaning up local images..."
docker rmi "${CONTAINER_REGISTRY_LOGIN_SERVER}/${APPLICATION_NAME}-api:latest" 2>/dev/null || true

# Build image with correct architecture
print_status "Building Docker image with linux/amd64 architecture..."
cd ..  # Go back to project root
docker build -t "${CONTAINER_REGISTRY_LOGIN_SERVER}/${APPLICATION_NAME}-api:latest" \
             --platform linux/amd64 \
             --build-arg DEBUG_MODE=False \
             -f Dockerfile .

# Push image
print_status "Pushing Docker image..."
docker push "${CONTAINER_REGISTRY_LOGIN_SERVER}/${APPLICATION_NAME}-api:latest"

cd deploy  # Return to deploy directory

# Update the container app to use the new image
print_status "Updating container app to use the new image..."
az containerapp update \
    --name "ca-${APPLICATION_NAME}-api-${ENVIRONMENT}" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --image "${CONTAINER_REGISTRY_LOGIN_SERVER}/${APPLICATION_NAME}-api:latest"

print_success "Image rebuilt and container app updated successfully!"

# Get application URL
APP_URL=$(az containerapp show \
    --name "ca-${APPLICATION_NAME}-api-${ENVIRONMENT}" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query "properties.configuration.ingress.fqdn" \
    --output tsv)

echo
echo "=========================================="
echo "Container app updated with new image!"
echo "Application URL: https://$APP_URL"
echo "API Documentation: https://$APP_URL/docs"
echo "Health Check: https://$APP_URL/healthcheck"
echo "=========================================="

print_status "Waiting for container to be ready (30 seconds)..."
sleep 30

print_status "Testing health check..."
if curl -f -s "https://$APP_URL/healthcheck" > /dev/null; then
    print_success "Health check passed! Application is running correctly."
else
    print_warning "Health check failed. Check container logs:"
    echo "az containerapp logs show --name ca-${APPLICATION_NAME}-api-${ENVIRONMENT} --resource-group ${RESOURCE_GROUP_NAME} --follow"
fi
