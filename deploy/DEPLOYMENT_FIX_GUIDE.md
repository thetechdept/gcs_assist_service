# Azure Container Apps Deployment Fix Guide

## Problem Description

The deployment was failing with the following error:

```
ERROR: {"status":"Failed","error":{"code":"DeploymentFailed",...
"message":"Failed to provision revision for container app 'ca-gcs-assist-api-dev'.
Error details: The following field(s) are either invalid or missing.
Field 'template.containers.api.image' is invalid with details:
'Invalid value: \"acrgcsassistdev5nuu5k.azurecr.io/gcs-assist-api:latest\":
GET https:: MANIFEST_UNKNOWN: manifest tagged by \"latest\" is not found; map[Tag:latest]';"
```

## Root Cause

This is a classic "chicken-and-egg" problem in the deployment process:

1. **Infrastructure deployment** (including API container app) happens first
2. **Docker image build and push** happens second
3. But the API container app creation requires the image to already exist in the Azure Container Registry

The original deployment script (`deploy-containerapp.sh`) tries to deploy everything at once, but the Bicep template references a Docker image that doesn't exist yet.

## Solutions

### Solution 1: Staged Deployment (Recommended)

This approach separates the deployment into stages:

1. **Stage 1**: Deploy infrastructure without the API container app
2. **Stage 2**: Build and push the Docker image
3. **Stage 3**: Deploy the API container app

**Files Created:**

- `deploy/bicep/main-infrastructure-only.bicep` - Infrastructure without API container app
- `deploy/deploy-containerapp-fixed.sh` - Fixed deployment script

**Usage:**

```bash
cd deploy
./deploy-containerapp-fixed.sh
```

**How it works:**

1. Deploys Azure Container Registry, PostgreSQL, OpenSearch, and supporting infrastructure
2. Builds and pushes the Docker image to the newly created registry
3. Deploys the API container app with the actual image

### Solution 2: Placeholder Image Approach (Alternative)

This approach uses a placeholder image initially, then updates with the actual image:

**Files Created:**

- `deploy/bicep/containerapp-api-with-placeholder.bicep` - API container app with placeholder support

**How it works:**

1. Deploys the API container app with a Microsoft-provided placeholder image
2. Builds and pushes the actual Docker image
3. Updates the container app to use the actual image

## Recommended Approach

**Use Solution 1 (Staged Deployment)** because:

1. **Cleaner separation of concerns** - Infrastructure and application deployment are separate
2. **Better error handling** - If image build fails, infrastructure is still intact
3. **More predictable** - Each stage has clear success/failure criteria
4. **Easier troubleshooting** - Can debug each stage independently

## Implementation Steps

### Using the Fixed Deployment Script

1. **Navigate to the deploy directory:**

   ```bash
   cd deploy
   ```

2. **Run the fixed deployment script:**

   ```bash
   ./deploy-containerapp-fixed.sh
   ```

3. **Follow the prompts:**

   - Enter your OpenAI API key
   - Enter a PostgreSQL password
   - Enter an OpenSearch admin password (or use default)

4. **Monitor the deployment:**
   The script will show progress through 5 stages:
   - Step 1: Deploy infrastructure (without API container app)
   - Step 2: Build and push Docker image
   - Step 3: Deploy API Container App
   - Step 4: Run post-deployment tasks
   - Step 5: Get application URLs

### Manual Steps (if needed)

If you prefer to run the steps manually:

1. **Deploy infrastructure only:**

   ```bash
   az deployment group create \
     --name "infrastructure-deployment-$(date +%Y%m%d-%H%M%S)" \
     --resource-group "rg-gcs-assist-dev" \
     --template-file "bicep/main-infrastructure-only.bicep" \
     --parameters location="uksouth" \
     --parameters applicationName="gcs-assist" \
     --parameters environment="dev" \
     --parameters postgresPassword="YourPassword" \
     --parameters opensearchAdminPassword="YourPassword"
   ```

2. **Build and push image:**

   ```bash
   # Get registry details from deployment output
   REGISTRY_NAME="acrgcsassistdev..."
   REGISTRY_SERVER="acrgcsassistdev....azurecr.io"

   # Login to registry
   az acr login --name $REGISTRY_NAME

   # Build and push
   docker build -t $REGISTRY_SERVER/gcs-assist-api:latest .
   docker push $REGISTRY_SERVER/gcs-assist-api:latest
   ```

3. **Deploy API container app:**
   ```bash
   az deployment group create \
     --name "api-deployment-$(date +%Y%m%d-%H%M%S)" \
     --resource-group "rg-gcs-assist-dev" \
     --template-file "bicep/containerapp-api.bicep" \
     --parameters name="ca-gcs-assist-api-dev" \
     --parameters containerRegistryName="$REGISTRY_NAME" \
     # ... other parameters
   ```

## Verification

After successful deployment, verify:

1. **Check container app status:**

   ```bash
   az containerapp show \
     --name "ca-gcs-assist-api-dev" \
     --resource-group "rg-gcs-assist-dev" \
     --query "properties.provisioningState"
   ```

2. **Test the application:**

   ```bash
   # Get the application URL
   APP_URL=$(az containerapp show \
     --name "ca-gcs-assist-api-dev" \
     --resource-group "rg-gcs-assist-dev" \
     --query "properties.configuration.ingress.fqdn" \
     --output tsv)

   # Test health check
   curl https://$APP_URL/healthcheck
   ```

3. **Check logs if needed:**
   ```bash
   az containerapp logs show \
     --name "ca-gcs-assist-api-dev" \
     --resource-group "rg-gcs-assist-dev" \
     --follow
   ```

## Troubleshooting

### Common Issues

1. **Docker build fails:**

   - Check Dockerfile syntax
   - Ensure all dependencies are available
   - Check Docker daemon is running

2. **Image push fails:**

   - Verify ACR login credentials
   - Check network connectivity
   - Ensure sufficient permissions

3. **Architecture mismatch error (`linux/arm64` vs `linux/amd64`):**

   - This occurs when building on Apple Silicon Macs (M1/M2/M3)
   - Azure Container Apps requires `linux/amd64` architecture
   - The fixed script includes `--platform linux/amd64` flag
   - If building manually, use: `docker build --platform linux/amd64 -t your-image .`

4. **Container app deployment fails:**
   - Verify all required parameters are provided
   - Check container registry permissions
   - Ensure image exists in registry
   - Check image architecture matches `linux/amd64`

### Debug Commands

```bash
# Check resource group resources
az resource list --resource-group "rg-gcs-assist-dev" --output table

# Check container registry images
az acr repository list --name "acrgcsassistdev..." --output table

# Check container app revisions
az containerapp revision list \
  --name "ca-gcs-assist-api-dev" \
  --resource-group "rg-gcs-assist-dev" \
  --output table
```

## Next Steps

After successful deployment:

1. **Set up monitoring** - Configure Application Insights alerts
2. **Configure custom domains** - If needed for production
3. **Set up CI/CD** - Automate future deployments
4. **Backup strategy** - Implement database and data backups
5. **Security review** - Review access controls and secrets management

## OpenSearch Multi-Node Deployment Fix

### Additional Issue: OpenSearch Node 2 Failure

If you encounter OpenSearch node 2 failing with port mismatch errors:

```
runningState: Failed
runningStateDetails: 'Deployment Progress Deadline Exceeded. 0/1 replicas ready.
The TargetPort 9200 does not match any of the listening ports: [9650 9600]. 1/1
Container crashing: opensearch'
```

This indicates OpenSearch clustering issues in Azure Container Apps environment.

### OpenSearch Fix Solution

**Quick Fix Script**: `deploy/fix-opensearch-deployment.sh`

```bash
cd deploy
./fix-opensearch-deployment.sh
```

**What the fix does:**

1. Configures each OpenSearch node as a single-node cluster
2. Creates separate storage volumes for each node
3. Updates network and discovery settings for Azure Container Apps
4. Ensures proper port configuration (9200 for HTTP)

**Key Changes Made:**

- Set `discovery.type=single-node` for both nodes
- Separate file shares for each node's data
- Proper network host binding (`0.0.0.0`)
- Disabled memory lock (not supported in containers)
- Fixed Java options for container environment

## Files Modified/Created

- ✅ `deploy/bicep/main-infrastructure-only.bicep` - New infrastructure-only template
- ✅ `deploy/deploy-containerapp-fixed.sh` - Fixed deployment script with AMD64 architecture
- ✅ `deploy/bicep/containerapp-api-with-placeholder.bicep` - Alternative placeholder approach
- ✅ `deploy/bicep/containerapp-opensearch.bicep` - Fixed OpenSearch configuration
- ✅ `deploy/bicep/storage.bicep` - Updated with separate file shares for OpenSearch nodes
- ✅ `deploy/fix-opensearch-deployment.sh` - Script to fix existing OpenSearch deployment
- ✅ `deploy/rebuild-image-amd64.sh` - Script to rebuild Docker image with correct architecture
- ✅ `deploy/DEPLOYMENT_FIX_GUIDE.md` - This comprehensive guide

## Original Files (updated)

- `deploy/bicep/main.bicep` - Updated with new OpenSearch parameters
- `deploy/bicep/main-infrastructure-only.bicep` - Updated with new OpenSearch parameters
- `deploy/deploy-containerapp.sh` - Original script (kept for reference)
