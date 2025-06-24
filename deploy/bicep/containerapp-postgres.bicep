param name string
param location string = resourceGroup().location
param containerAppEnvironmentId string
param containerRegistryName string
param storageAccountName string

@description('PostgreSQL version')
param postgresVersion string = '15'

@description('PostgreSQL database name')
param postgresDb string = 'gcs_assist_db'

@description('PostgreSQL user')
param postgresUser string = 'postgres'

@secure()
@description('PostgreSQL password')
param postgresPassword string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: name
  location: location
  properties: {
    managedEnvironmentId: containerAppEnvironmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: 5432
        transport: 'tcp'
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
          image: 'postgres:${postgresVersion}'
          name: 'postgres'
          env: [
            {
              name: 'POSTGRES_DB'
              value: postgresDb
            }
            {
              name: 'POSTGRES_USER'
              value: postgresUser
            }
            {
              name: 'POSTGRES_PASSWORD'
              value: postgresPassword
            }
            {
              name: 'PGDATA'
              value: '/var/lib/postgresql/data/pgdata'
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          volumeMounts: [
            {
              mountPath: '/var/lib/postgresql/data'
              volumeName: 'postgres-data'
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
          name: 'postgres-data'
          storageType: 'AzureFile'
          storageName: 'postgres-storage'
        }
      ]
    }
  }
}

resource postgresStorage 'Microsoft.App/managedEnvironments/storages@2023-05-01' = {
  parent: containerAppEnvironment
  name: 'postgres-storage'
  properties: {
    azureFile: {
      accountName: storageAccount.name
      accountKey: storageAccount.listKeys().keys[0].value
      shareName: 'postgres-data'
      accessMode: 'ReadWrite'
    }
  }
}

resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' existing = {
  name: split(containerAppEnvironmentId, '/')[8]
}

output fqdn string = containerApp.properties.configuration.ingress.fqdn
output name string = containerApp.name
