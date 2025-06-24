param name string
param location string = resourceGroup().location
param containerAppEnvironmentId string
param storageAccountName string
param nodeName string
param isBootstrapNode bool = false

@description('OpenSearch version')
param opensearchVersion string = '2.11.1'

@description('OpenSearch cluster name')
param clusterName string = 'gcs-assist-cluster'

@description('OpenSearch admin password')
@secure()
param opensearchAdminPassword string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: name
  location: location
  dependsOn: [
    opensearchStorage
  ]
  properties: {
    managedEnvironmentId: containerAppEnvironmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: 9200
        transport: 'http'
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
    }
    template: {
      containers: [
        {
          image: 'opensearchproject/opensearch:${opensearchVersion}'
          name: 'opensearch'
          env: [
            {
              name: 'cluster.name'
              value: clusterName
            }
            {
              name: 'node.name'
              value: nodeName
            }
            {
              name: 'discovery.seed_hosts'
              value: isBootstrapNode ? '${nodeName}' : 'opensearch-node1,${nodeName}'
            }
            {
              name: 'cluster.initial_cluster_manager_nodes'
              value: isBootstrapNode ? nodeName : 'opensearch-node1'
            }
            {
              name: 'bootstrap.memory_lock'
              value: 'true'
            }
            {
              name: 'OPENSEARCH_JAVA_OPTS'
              value: '-Xms512m -Xmx512m'
            }
            {
              name: 'OPENSEARCH_INITIAL_ADMIN_PASSWORD'
              value: opensearchAdminPassword
            }
            {
              name: 'DISABLE_INSTALL_DEMO_CONFIG'
              value: 'true'
            }
            {
              name: 'DISABLE_SECURITY_PLUGIN'
              value: 'true'
            }
            {
              name: 'discovery.type'
              value: isBootstrapNode ? 'zen' : ''
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          volumeMounts: [
            {
              mountPath: '/usr/share/opensearch/data'
              volumeName: 'opensearch-data'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
      volumes: [
        {
          name: 'opensearch-data'
          storageType: 'AzureFile'
          storageName: 'opensearch-storage'
        }
      ]
    }
  }
}

resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' existing = {
  name: split(containerAppEnvironmentId, '/')[8]
}

resource opensearchStorage 'Microsoft.App/managedEnvironments/storages@2023-05-01' = {
  parent: containerAppEnvironment
  name: 'opensearch-storage'
  properties: {
    azureFile: {
      accountName: storageAccount.name
      accountKey: storageAccount.listKeys().keys[0].value
      shareName: 'opensearch-data'
      accessMode: 'ReadWrite'
    }
  }
}

output fqdn string = containerApp.properties.configuration.ingress.fqdn
output name string = containerApp.name
