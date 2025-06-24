# GCS Assist Service - Azure Container Apps Deployment

This directory contains all the necessary files to deploy the GCS Assist Service to Azure Container Apps using either manual deployment (VSCode) or automated deployment (Azure DevOps).

## Architecture Overview

The deployment creates a fully containerized environment with:

- **API Container**: FastAPI application (your main service)
- **PostgreSQL Container**: Database with persistent storage
- **OpenSearch Containers**: Two-node cluster for search functionality
- **Azure Container Registry**: For storing container images
- **Application Insights**: For monitoring and logging
- **Azure Files**: For persistent storage volumes

## Prerequisites

### For Manual Deployment (VSCode)

- Azure CLI installed and configured
- Docker installed and running
- jq installed (for JSON parsing)
- Azure subscription with appropriate permissions

### For Azure DevOps Pipeline

- Azure DevOps project
- Azure service connection configured
- Variable groups set up with secrets

## File Structure

```
deploy/
├── README.md                           # This file
├── azure-pipelines.yaml               # Main pipeline definition
├── azure-deployment-steps.yaml        # Reusable deployment steps
├── deploy-containerapp.sh             # Manual deployment script
└── bicep/
    ├── main.bicep                      # Main orchestration template
    ├── acr.bicep                       # Container Registry
    ├── storage.bicep                   # Storage Account with file shares
    ├── containerapp-environment.bicep  # Container App Environment
    ├── containerapp-api.bicep          # API Container App
    ├── containerapp-postgres.bicep     # PostgreSQL Container App
    └── containerapp-opensearch.bicep   # OpenSearch Container App
```

## Manual Deployment (VSCode)

### 1. Prerequisites Setup

Install required tools:

```bash
# Install Azure CLI (macOS)
brew install azure-cli

# Install jq (macOS)
brew install jq

# Verify Docker is running
docker --version
```

### 2. Azure Login

```bash
# Login to Azure
az login

# Set your subscription (optional)
az account set --subscription "your-subscription-id"
```

### 3. Configure Deployment

Edit `deploy-containerapp.sh` and update:

```bash
SUBSCRIPTION_ID="your-azure-subscription-id"  # Optional
ENVIRONMENT="dev"  # or "qa", "prod"
```

### 4. Run Deployment

```bash
cd deploy
./deploy-containerapp.sh
```

The script will:

1. Check prerequisites
2. Prompt for secrets (OpenAI API key, PostgreSQL password)
3. Deploy infrastructure using Bicep
4. Build and push Docker image
5. Update container apps
6. Run database migrations
7. Sync OpenSearch indexes
8. Display application URLs

### 5. Access Your Application

After successful deployment, you'll see:

```
Application URLs:
Main Application: https://ca-gcs-assist-api-dev.kindpond-12345678.uksouth.azurecontainerapps.io
API Documentation: https://ca-gcs-assist-api-dev.kindpond-12345678.uksouth.azurecontainerapps.io/docs
Health Check: https://ca-gcs-assist-api-dev.kindpond-12345678.uksouth.azurecontainerapps.io/healthcheck
```

## Azure DevOps Pipeline Deployment

### 1. Setup Azure DevOps

1. Create a new Azure DevOps project
2. Set up Azure service connection:
   - Go to Project Settings > Service connections
   - Create new Azure Resource Manager connection
   - Name it `GCS-Assist-Service` (or update the name in `azure-pipelines.yaml`)

### 2. Configure Variable Groups

Create variable groups for each environment (dev, qa, prod):

**Variable Group: `gcs-assist-secrets-dev`**

- `openaiApiKey.dev`: Your OpenAI API key (mark as secret)
- `postgresPassword.dev`: PostgreSQL password (mark as secret)
- `opensearchAdminPassword.dev`: OpenSearch admin password (mark as secret)

Repeat for `qa` and `prod` environments.

### 3. Create Pipeline

1. Go to Pipelines > Create Pipeline
2. Choose "Azure Repos Git" or your repository location
3. Select "Existing Azure Pipelines YAML file"
4. Choose `/deploy/azure-pipelines.yaml`
5. Save and run

### 4. Pipeline Parameters

When running the pipeline, you can set:

- `deployBicep`: `true` for first deployment or infrastructure changes

## Environment Configuration

### Environment Variables

The deployment automatically configures all environment variables from your `.env` file, with production-appropriate values:

- `IS_DEV`: `False`
- `DEBUG_MODE`: `False`
- `SHOW_DEVELOPER_ENDPOINTS_IN_DOCS`: `False`
- Database connections point to containerized PostgreSQL
- OpenSearch connections point to containerized OpenSearch cluster

### Secrets Management

Sensitive values are stored as Container App secrets:

- OpenAI API key
- PostgreSQL password
- OpenSearch admin password

### Scaling Configuration

- **API Container**: Auto-scales 1-10 replicas based on HTTP requests
- **Database Containers**: Fixed at 1 replica (stateful)
- **OpenSearch Containers**: Fixed at 1 replica each (stateful)

## Monitoring and Troubleshooting

### Application Insights

All containers send logs and metrics to Application Insights:

- Application performance monitoring
- Request tracing
- Error tracking
- Custom metrics

### Container Logs

View container logs:

```bash
# API container logs
az containerapp logs show \
  --name ca-gcs-assist-api-dev \
  --resource-group rg-gcs-assist-dev \
  --follow

# PostgreSQL container logs
az containerapp logs show \
  --name ca-gcs-assist-postgres-dev \
  --resource-group rg-gcs-assist-dev \
  --follow
```

### Health Checks

- API Health: `https://your-app-url/healthcheck`
- API Documentation: `https://your-app-url/docs`

### Common Issues

1. **Container startup failures**: Check logs for missing environment variables
2. **Database connection issues**: Verify PostgreSQL container is running
3. **OpenSearch connection issues**: Check OpenSearch containers are healthy
4. **Image pull failures**: Verify Container Registry permissions

## Cost Optimization

### Development Environment

- Use `Consumption` pricing tier for Container Apps
- Scale API to zero when not in use
- Use `Standard_LRS` storage for file shares

### Production Environment

- Consider `Dedicated` pricing tier for consistent performance
- Set appropriate min/max replica counts
- Use `Premium_LRS` storage for better performance

## Security Considerations

1. **Network Security**: All internal communication uses private networking
2. **Secrets Management**: Sensitive values stored as Container App secrets
3. **Container Registry**: Private registry with admin access disabled in production
4. **HTTPS**: All external traffic uses HTTPS
5. **Database**: PostgreSQL not exposed externally

## Backup and Disaster Recovery

### Database Backup

PostgreSQL data is stored in Azure Files with built-in redundancy.

For additional backup:

```bash
# Manual backup
az containerapp exec \
  --name ca-gcs-assist-postgres-dev \
  --resource-group rg-gcs-assist-dev \
  --command "pg_dump -U postgres gcs_assist_db > /var/lib/postgresql/data/backup.sql"
```

### OpenSearch Backup

OpenSearch data is stored in Azure Files. Consider implementing snapshot policies for production.

## Updating the Application

### Manual Update

```bash
cd deploy
./deploy-containerapp.sh
```

### Pipeline Update

Push changes to your repository and run the pipeline.

## Support

For issues with deployment:

1. Check container logs
2. Verify all prerequisites are installed
3. Ensure Azure permissions are correct
4. Check Application Insights for runtime errors

## Next Steps

1. Set up monitoring alerts in Application Insights
2. Configure custom domains if needed
3. Implement backup strategies for production
4. Set up staging slots for zero-downtime deployments
