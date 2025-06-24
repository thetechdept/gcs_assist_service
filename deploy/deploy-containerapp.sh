#!/bin/bash

# Azure Container Apps Deployment Script for GCS Assist Service
# This script can be used for manual deployment from VSCode or local development

set -e  # Exit on any error

# Configuration
APPLICATION_NAME="gcs-assist"
LOCATION="uksouth"
SUBSCRIPTION_ID="10416533-79d8-434a-ba12-b7e7d8cd982a"  # Set your Azure subscription ID
ENVIRONMENT="dev"   # Change to qa or prod as needed

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

# Function to check if required tools are installed
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install it first."
        exit 1
    fi
    
    print_success "All prerequisites are installed."
}

# Function to login to Azure
azure_login() {
    print_status "Checking Azure login status..."
    
    if ! az account show &> /dev/null; then
        print_status "Not logged in to Azure. Please login..."
        az login
    fi
    
    if [ -n "$SUBSCRIPTION_ID" ]; then
        print_status "Setting subscription to $SUBSCRIPTION_ID"
        az account set --subscription "$SUBSCRIPTION_ID"
    fi
    
    CURRENT_SUBSCRIPTION=$(az account show --query name --output tsv)
    print_success "Using subscription: $CURRENT_SUBSCRIPTION"
}

# Function to get user input for secrets
get_secrets() {
    print_status "Please provide the required secrets:"
    
    echo -n "OpenAI API Key: "
    read -s OPENAI_API_KEY
    echo
    
    echo -n "PostgreSQL Password: "
    read -s POSTGRES_PASSWORD
    echo
    
    echo -n "OpenSearch Admin Password (press enter for default): "
    read -s OPENSEARCH_ADMIN_PASSWORD
    echo
    
    # Set defaults if empty
    if [ -z "$POSTGRES_PASSWORD" ]; then
        POSTGRES_PASSWORD="SecurePassword123!"
    fi
    
    if [ -z "$OPENSEARCH_ADMIN_PASSWORD" ]; then
        OPENSEARCH_ADMIN_PASSWORD="YPC!amw_kqd-tzx2hmc"
    fi
    
    print_success "Secrets collected."
}

# Function to deploy infrastructure
deploy_infrastructure() {
    print_status "Deploying infrastructure..."
    
    RESOURCE_GROUP_NAME="rg-${APPLICATION_NAME}-${ENVIRONMENT}"
    
    # Create resource group
    print_status "Creating resource group: $RESOURCE_GROUP_NAME"
    az group create \
        --name "$RESOURCE_GROUP_NAME" \
        --location "$LOCATION" \
        --tags Environment="$ENVIRONMENT" Application="$APPLICATION_NAME"
    
    # Deploy Bicep template
    print_status "Deploying Bicep infrastructure..."
    DEPLOYMENT_OUTPUT=$(az deployment group create \
        --name "manual-deployment-$(date +%Y%m%d-%H%M%S)" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --template-file "bicep/main.bicep" \
        --parameters location="$LOCATION" \
        --parameters applicationName="$APPLICATION_NAME" \
        --parameters environment="$ENVIRONMENT" \
        --parameters openaiApiKey="$OPENAI_API_KEY" \
        --parameters postgresPassword="$POSTGRES_PASSWORD" \
        --parameters opensearchAdminPassword="$OPENSEARCH_ADMIN_PASSWORD" \
        --query 'properties.outputs' \
        --output json)
    
    # Extract outputs
    CONTAINER_REGISTRY_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.containerRegistryName.value')
    CONTAINER_REGISTRY_LOGIN_SERVER=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.containerRegistryLoginServer.value')
    
    print_success "Infrastructure deployed successfully!"
    print_status "Container Registry: $CONTAINER_REGISTRY_NAME"
    print_status "Login Server: $CONTAINER_REGISTRY_LOGIN_SERVER"
}

# Function to build and push Docker image
build_and_push_image() {
    print_status "Building and pushing Docker image..."
    
    # Get ACR credentials
    ACR_PASSWORD=$(az acr credential show --name "$CONTAINER_REGISTRY_NAME" --query "passwords[0].value" --output tsv)
    ACR_USERNAME=$(az acr credential show --name "$CONTAINER_REGISTRY_NAME" --query "username" --output tsv)
    
    # Login to ACR
    print_status "Logging into Container Registry..."
    echo "$ACR_PASSWORD" | docker login "$CONTAINER_REGISTRY_LOGIN_SERVER" --username "$ACR_USERNAME" --password-stdin
    
    # Build image
    print_status "Building Docker image..."
    cd ..  # Go back to project root
    docker build -t "${CONTAINER_REGISTRY_LOGIN_SERVER}/${APPLICATION_NAME}-api:latest" \
                 --build-arg DEBUG_MODE=False \
                 -f Dockerfile .
    
    # Push image
    print_status "Pushing Docker image..."
    docker push "${CONTAINER_REGISTRY_LOGIN_SERVER}/${APPLICATION_NAME}-api:latest"
    
    cd deploy  # Return to deploy directory
    print_success "Docker image built and pushed successfully!"
}

# Function to update container apps
update_container_apps() {
    print_status "Updating Container Apps..."
    
    RESOURCE_GROUP_NAME="rg-${APPLICATION_NAME}-${ENVIRONMENT}"
    
    # Update API Container App
    print_status "Updating API Container App..."
    az containerapp update \
        --name "ca-${APPLICATION_NAME}-api-${ENVIRONMENT}" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --image "${CONTAINER_REGISTRY_LOGIN_SERVER}/${APPLICATION_NAME}-api:latest"
    
    print_success "Container Apps updated successfully!"
}

# Function to run post-deployment tasks
run_post_deployment_tasks() {
    print_status "Running post-deployment tasks..."
    
    RESOURCE_GROUP_NAME="rg-${APPLICATION_NAME}-${ENVIRONMENT}"
    
    # Wait for container to be ready
    print_status "Waiting for container to be ready..."
    sleep 30
    
    # Run database migrations
    print_status "Running database migrations..."
    az containerapp exec \
        --name "ca-${APPLICATION_NAME}-api-${ENVIRONMENT}" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --command "cd app/alembic && alembic upgrade head" || print_warning "Migration command completed with warnings"
    
    # Sync OpenSearch indexes
    print_status "Syncing OpenSearch indexes..."
    az containerapp exec \
        --name "ca-${APPLICATION_NAME}-api-${ENVIRONMENT}" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --command "python scripts/sync_opensearch/sync_central_rag.py" || print_warning "OpenSearch sync completed with warnings"
    
    print_success "Post-deployment tasks completed!"
}

# Function to get application URL
get_application_url() {
    print_status "Getting application URL..."
    
    RESOURCE_GROUP_NAME="rg-${APPLICATION_NAME}-${ENVIRONMENT}"
    
    APP_URL=$(az containerapp show \
        --name "ca-${APPLICATION_NAME}-api-${ENVIRONMENT}" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --query "properties.configuration.ingress.fqdn" \
        --output tsv)
    
    print_success "Deployment completed successfully!"
    echo
    echo "=========================================="
    echo "Application URLs:"
    echo "Main Application: https://$APP_URL"
    echo "API Documentation: https://$APP_URL/docs"
    echo "Health Check: https://$APP_URL/healthcheck"
    echo "=========================================="
}

# Main deployment function
main() {
    echo "=========================================="
    echo "GCS Assist Service - Azure Container Apps Deployment"
    echo "Environment: $ENVIRONMENT"
    echo "Location: $LOCATION"
    echo "=========================================="
    
    check_prerequisites
    azure_login
    get_secrets
    deploy_infrastructure
    build_and_push_image
    update_container_apps
    run_post_deployment_tasks
    get_application_url
    
    print_success "Deployment completed successfully!"
}

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
