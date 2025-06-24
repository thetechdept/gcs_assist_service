#!/bin/bash

# Script to fix the OpenSearch deployment issue
# This script updates the existing OpenSearch container apps with the corrected configuration

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
echo "Fixing OpenSearch Deployment"
echo "Environment: $ENVIRONMENT"
echo "=========================================="

# Get OpenSearch admin password
print_status "Please provide the OpenSearch admin password:"
echo -n "OpenSearch Admin Password: "
read -s OPENSEARCH_ADMIN_PASSWORD
echo

if [ -z "$OPENSEARCH_ADMIN_PASSWORD" ]; then
    OPENSEARCH_ADMIN_PASSWORD="YPC!amw_kqd-tzx2hmc"
    print_warning "Using default password"
fi

# Get storage account name
print_status "Getting storage account details..."
STORAGE_ACCOUNT_NAME=$(az resource list \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --resource-type "Microsoft.Storage/storageAccounts" \
    --query "[0].name" \
    --output tsv)

if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
    print_error "Storage account not found in resource group $RESOURCE_GROUP_NAME"
    exit 1
fi

print_success "Found storage account: $STORAGE_ACCOUNT_NAME"

# Get container app environment ID
print_status "Getting container app environment details..."
CONTAINER_APP_ENVIRONMENT_ID=$(az resource list \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --resource-type "Microsoft.App/managedEnvironments" \
    --query "[0].id" \
    --output tsv)

if [ -z "$CONTAINER_APP_ENVIRONMENT_ID" ]; then
    print_error "Container app environment not found in resource group $RESOURCE_GROUP_NAME"
    exit 1
fi

print_success "Found container app environment"

# Create file shares for each OpenSearch node
print_status "Creating file shares for OpenSearch nodes..."

# Create file share for node 1
az storage share create \
    --name "opensearch-data-opensearch-node1" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --quota 20 \
    --output none || print_warning "File share for node 1 may already exist"

# Create file share for node 2
az storage share create \
    --name "opensearch-data-opensearch-node2" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --quota 20 \
    --output none || print_warning "File share for node 2 may already exist"

print_success "File shares created/verified"

# Update OpenSearch Node 1
print_status "Updating OpenSearch Node 1..."
az deployment group create \
    --name "opensearch1-fix-$(date +%Y%m%d-%H%M%S)" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --template-file "bicep/containerapp-opensearch.bicep" \
    --parameters name="ca-${APPLICATION_NAME}-opensearch1-${ENVIRONMENT}" \
    --parameters location="uksouth" \
    --parameters containerAppEnvironmentId="$CONTAINER_APP_ENVIRONMENT_ID" \
    --parameters storageAccountName="$STORAGE_ACCOUNT_NAME" \
    --parameters nodeName="opensearch-node1" \
    --parameters isBootstrapNode=true \
    --parameters applicationName="$APPLICATION_NAME" \
    --parameters environment="$ENVIRONMENT" \
    --parameters opensearchAdminPassword="$OPENSEARCH_ADMIN_PASSWORD"

print_success "OpenSearch Node 1 updated successfully!"

# Wait a bit before updating node 2
print_status "Waiting 30 seconds before updating Node 2..."
sleep 30

# Update OpenSearch Node 2
print_status "Updating OpenSearch Node 2..."
az deployment group create \
    --name "opensearch2-fix-$(date +%Y%m%d-%H%M%S)" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --template-file "bicep/containerapp-opensearch.bicep" \
    --parameters name="ca-${APPLICATION_NAME}-opensearch2-${ENVIRONMENT}" \
    --parameters location="uksouth" \
    --parameters containerAppEnvironmentId="$CONTAINER_APP_ENVIRONMENT_ID" \
    --parameters storageAccountName="$STORAGE_ACCOUNT_NAME" \
    --parameters nodeName="opensearch-node2" \
    --parameters isBootstrapNode=false \
    --parameters applicationName="$APPLICATION_NAME" \
    --parameters environment="$ENVIRONMENT" \
    --parameters opensearchAdminPassword="$OPENSEARCH_ADMIN_PASSWORD"

print_success "OpenSearch Node 2 updated successfully!"

# Check the status of both nodes
print_status "Checking OpenSearch container app status..."

NODE1_STATUS=$(az containerapp show \
    --name "ca-${APPLICATION_NAME}-opensearch1-${ENVIRONMENT}" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query "properties.provisioningState" \
    --output tsv)

NODE2_STATUS=$(az containerapp show \
    --name "ca-${APPLICATION_NAME}-opensearch2-${ENVIRONMENT}" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query "properties.provisioningState" \
    --output tsv)

echo
echo "=========================================="
echo "OpenSearch Deployment Status:"
echo "Node 1 Status: $NODE1_STATUS"
echo "Node 2 Status: $NODE2_STATUS"
echo "=========================================="

if [ "$NODE1_STATUS" = "Succeeded" ] && [ "$NODE2_STATUS" = "Succeeded" ]; then
    print_success "Both OpenSearch nodes are running successfully!"
    
    # Get the URLs
    NODE1_URL=$(az containerapp show \
        --name "ca-${APPLICATION_NAME}-opensearch1-${ENVIRONMENT}" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --query "properties.configuration.ingress.fqdn" \
        --output tsv)
    
    NODE2_URL=$(az containerapp show \
        --name "ca-${APPLICATION_NAME}-opensearch2-${ENVIRONMENT}" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --query "properties.configuration.ingress.fqdn" \
        --output tsv)
    
    echo
    echo "OpenSearch Node URLs (internal):"
    echo "Node 1: https://$NODE1_URL"
    echo "Node 2: https://$NODE2_URL"
    echo
    
    print_status "Testing OpenSearch connectivity..."
    
    # Wait for containers to be ready
    sleep 30
    
    # Test node 1
    if curl -f -s "https://$NODE1_URL" > /dev/null; then
        print_success "Node 1 is responding!"
    else
        print_warning "Node 1 may still be starting up. Check logs if needed:"
        echo "az containerapp logs show --name ca-${APPLICATION_NAME}-opensearch1-${ENVIRONMENT} --resource-group ${RESOURCE_GROUP_NAME} --follow"
    fi
    
    # Test node 2
    if curl -f -s "https://$NODE2_URL" > /dev/null; then
        print_success "Node 2 is responding!"
    else
        print_warning "Node 2 may still be starting up. Check logs if needed:"
        echo "az containerapp logs show --name ca-${APPLICATION_NAME}-opensearch2-${ENVIRONMENT} --resource-group ${RESOURCE_GROUP_NAME} --follow"
    fi
    
else
    print_warning "One or both nodes are not in 'Succeeded' state. Check the Azure portal or container logs for details."
fi

print_success "OpenSearch deployment fix completed!"
