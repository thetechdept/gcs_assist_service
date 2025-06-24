#!/bin/bash

# Bicep Template Validation Script
# This script validates all Bicep templates for syntax errors

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if bicep is available
if ! az bicep version &> /dev/null; then
    print_status "Installing Bicep CLI..."
    az bicep install
fi

print_status "Validating Bicep templates..."

# Validate individual templates
templates=(
    "bicep/acr.bicep"
    "bicep/storage.bicep"
    "bicep/containerapp-environment.bicep"
    "bicep/containerapp-postgres.bicep"
    "bicep/containerapp-opensearch.bicep"
    "bicep/containerapp-api.bicep"
)

for template in "${templates[@]}"; do
    print_status "Validating $template..."
    if az bicep build --file "$template" --stdout > /dev/null 2>&1; then
        print_success "$template is valid"
    else
        print_error "$template has validation errors"
        az bicep build --file "$template" --stdout
        exit 1
    fi
done

# Validate main template
print_status "Validating main template..."
if az bicep build --file "bicep/main.bicep" --stdout > /dev/null 2>&1; then
    print_success "bicep/main.bicep is valid"
else
    print_error "bicep/main.bicep has validation errors"
    az bicep build --file "bicep/main.bicep" --stdout
    exit 1
fi

print_success "All Bicep templates are valid!"

# Optional: Build ARM templates
read -p "Do you want to build ARM templates? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Building ARM templates..."
    mkdir -p arm-templates
    
    for template in "${templates[@]}"; do
        filename=$(basename "$template" .bicep)
        print_status "Building ARM template for $filename..."
        az bicep build --file "$template" --outfile "arm-templates/$filename.json"
    done
    
    print_status "Building main ARM template..."
    az bicep build --file "bicep/main.bicep" --outfile "arm-templates/main.json"
    
    print_success "ARM templates built in arm-templates/ directory"
fi

print_success "Validation completed successfully!"
