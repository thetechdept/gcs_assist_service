param location string = resourceGroup().location
param applicationName string
param environment string

@description('Container registry admin user enabled')
param acrAdminUserEnabled bool = true

@description('Application Insights sampling percentage')
param appInsightsSamplingPercentage int = 100

@secure()
@description('PostgreSQL Password')
param postgresPassword string

@secure()
@description('OpenSearch Admin Password')
param opensearchAdminPassword string

var containerAppEnvironmentName = 'cae-${applicationName}-${environment}'
var containerRegistryName = 'acr${replace(applicationName, '-', '')}${environment}${take(uniqueString(resourceGroup().id), 6)}'
var logAnalyticsWorkspaceName = 'law-${applicationName}-${environment}'
var appInsightsName = 'appi-${applicationName}-${environment}'
var storageAccountName = 'st${replace(applicationName, '-', '')}${environment}${take(uniqueString(resourceGroup().id), 6)}'

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    SamplingPercentage: appInsightsSamplingPercentage
  }
}

// Container Registry
module containerRegistry 'acr.bicep' = {
  name: '${deployment().name}--acr'
  params: {
    name: containerRegistryName
    location: location
    adminUserEnabled: acrAdminUserEnabled
  }
}

// Storage Account for persistent volumes
module storage 'storage.bicep' = {
  name: '${deployment().name}--storage'
  params: {
    name: storageAccountName
    location: location
  }
}

// Container App Environment
module containerAppEnvironment 'containerapp-environment.bicep' = {
  name: '${deployment().name}--cae'
  params: {
    name: containerAppEnvironmentName
    location: location
    logAnalyticsWorkspaceId: logAnalyticsWorkspace.id
  }
}

// PostgreSQL Container App
module postgresContainerApp 'containerapp-postgres.bicep' = {
  name: '${deployment().name}--postgres'
  params: {
    name: 'ca-${applicationName}-postgres-${environment}'
    location: location
    containerAppEnvironmentId: containerAppEnvironment.outputs.containerAppEnvironmentId
    storageAccountName: storageAccountName
    postgresPassword: postgresPassword
  }
  dependsOn: [
    containerRegistry
    storage
  ]
}

// OpenSearch Node 1 Container App
module opensearchNode1ContainerApp 'containerapp-opensearch.bicep' = {
  name: '${deployment().name}--opensearch1'
  params: {
    name: 'ca-${applicationName}-opensearch1-${environment}'
    location: location
    containerAppEnvironmentId: containerAppEnvironment.outputs.containerAppEnvironmentId
    storageAccountName: storageAccountName
    nodeName: 'opensearch-node1'
    isBootstrapNode: true
    opensearchAdminPassword: opensearchAdminPassword
  }
  dependsOn: [
    containerRegistry
    storage
  ]
}

// OpenSearch Node 2 Container App
module opensearchNode2ContainerApp 'containerapp-opensearch.bicep' = {
  name: '${deployment().name}--opensearch2'
  params: {
    name: 'ca-${applicationName}-opensearch2-${environment}'
    location: location
    containerAppEnvironmentId: containerAppEnvironment.outputs.containerAppEnvironmentId
    storageAccountName: storageAccountName
    nodeName: 'opensearch-node2'
    isBootstrapNode: false
    opensearchAdminPassword: opensearchAdminPassword
  }
  dependsOn: [
    containerRegistry
    storage
    opensearchNode1ContainerApp
  ]
}

// Outputs
output containerRegistryName string = containerRegistryName
output containerRegistryLoginServer string = containerRegistry.outputs.loginServer
output containerAppEnvironmentId string = containerAppEnvironment.outputs.containerAppEnvironmentId
output appInsightsConnectionString string = appInsights.properties.ConnectionString
