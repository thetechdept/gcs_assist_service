param name string
param location string = resourceGroup().location
param containerAppEnvironmentId string
param containerRegistryName string
param appInsightsConnectionString string
param applicationName string
param environment string

@description('Container image tag')
param imageTag string = 'latest'

@description('Minimum number of replicas')
param minReplicas int = 1

@description('Maximum number of replicas')
param maxReplicas int = 10

// Environment variables - these should be configured in the pipeline
@secure()
param openaiApiKey string
@secure()
param postgresPassword string
@secure()
param opensearchAdminPassword string

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: containerRegistryName
}

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: name
  location: location
  properties: {
    managedEnvironmentId: containerAppEnvironmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 5312
        transport: 'http'
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          username: containerRegistry.listCredentials().username
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        {
          name: 'registry-password'
          value: containerRegistry.listCredentials().passwords[0].value
        }
        {
          name: 'openai-api-key'
          value: openaiApiKey
        }
        {
          name: 'postgres-password'
          value: postgresPassword
        }
        {
          name: 'opensearch-admin-password'
          value: opensearchAdminPassword
        }
      ]
    }
    template: {
      containers: [
        {
          image: '${containerRegistry.properties.loginServer}/${applicationName}-api:${imageTag}'
          name: 'api'
          env: [
            // General Development Settings
            {
              name: 'IS_DEV'
              value: 'False'
            }
            {
              name: 'PORT'
              value: '5312'
            }
            {
              name: 'DEBUG_MODE'
              value: 'False'
            }
            // Documentation Display Settings
            {
              name: 'SHOW_HEADER_PARAMS_IN_DOCS'
              value: 'False'
            }
            {
              name: 'SHOW_DEVELOPER_ENDPOINTS_IN_DOCS'
              value: 'False'
            }
            // Authentication and Session Validation
            {
              name: 'BYPASS_SESSION_VALIDATOR'
              value: 'False'
            }
            {
              name: 'BYPASS_AUTH_VALIDATOR'
              value: 'False'
            }
            // Error Handling and Logging
            {
              name: 'SHOW_DETAILED_ERROR_MESSAGES'
              value: 'False'
            }
            {
              name: 'DEBUG_LOGGING'
              value: 'False'
            }
            // OpenSearch Configuration
            {
              name: 'OPENSEARCH_DISABLE_SSL'
              value: 'True'
            }
            {
              name: 'OPENSEARCH_HOST'
              value: 'opensearch-node1'
            }
            {
              name: 'OPENSEARCH_PORT'
              value: '9200'
            }
            {
              name: 'OPENSEARCH_USER'
              value: 'admin'
            }
            {
              name: 'OPENSEARCH_PASSWORD'
              secretRef: 'opensearch-admin-password'
            }
            {
              name: 'OPENSEARCH_INITIAL_ADMIN_PASSWORD'
              secretRef: 'opensearch-admin-password'
            }
            // PostgreSQL Configuration
            {
              name: 'POSTGRES_USER'
              value: 'postgres'
            }
            {
              name: 'POSTGRES_PASSWORD'
              secretRef: 'postgres-password'
            }
            {
              name: 'POSTGRES_DB'
              value: 'gcs_assist_db'
            }
            {
              name: 'POSTGRES_HOST'
              value: 'postgres'
            }
            {
              name: 'POSTGRES_PORT'
              value: '5432'
            }
            {
              name: 'TEST_POSTGRES_DB'
              value: 'test_db_test'
            }
            // RAG Configuration
            {
              name: 'RAG_LLM_MODEL_INDEX_ROUTER'
              value: 'gpt-4o'
            }
            {
              name: 'RAG_SYSTEM_PROMPT_INDEX_ROUTER'
              value: 'index_router_1'
            }
            {
              name: 'RAG_LLM_MODEL_QUERY_REWRITER'
              value: 'gpt-4o'
            }
            {
              name: 'RAG_SYSTEM_PROMPT_QUERY_REWRITER'
              value: 'query_rewriter_1'
            }
            {
              name: 'RAG_LLM_MODEL_CHUNK_REVIEWER'
              value: 'gpt-4o'
            }
            {
              name: 'RAG_SYSTEM_PROMPT_CHUNK_REVIEWER'
              value: 'chunk_reviewer_1'
            }
            // LLM Configuration
            {
              name: 'LLM_DEFAULT_PROVIDER'
              value: 'openai'
            }
            {
              name: 'LLM_DOCUMENT_RELEVANCY_MODEL'
              value: 'gpt-4o'
            }
            {
              name: 'LLM_DEFAULT_MODEL'
              value: 'gpt-4o'
            }
            {
              name: 'OPENAI_API_KEY'
              secretRef: 'openai-api-key'
            }
            // Test Variables
            {
              name: 'TEST_DEFAULT_QUERY'
              value: 'hello'
            }
            {
              name: 'TEST_SESSION_UUID'
              value: 'd121ec43-9a66-4a80-b4a1-6ed4ea863a5a'
            }
            {
              name: 'TEST_USER_UUID'
              value: 'a2571054-bc45-4924-add9-6a90bdec2508'
            }
            // Application Insights
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsightsConnectionString
            }
          ]
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}

output fqdn string = containerApp.properties.configuration.ingress.fqdn
output name string = containerApp.name
