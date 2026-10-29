@description('Azure region')
param location string = resourceGroup().location

@description('Container image, for example ghcr.io/jasonandrewwakeman/phixem:latest')
param containerImage string

@description('Public hostname used by Phoenix (ACA FQDN or custom domain)')
param phxHost string

@secure()
@description('mix phx.gen.secret output')
param secretKeyBase string

@secure()
@description('Storage account access key (filled after storage is created if omitted from params; pass the key from the created account)')
param storageAccountKey string = ''

@description('GitHub user or org for GHCR pulls (leave empty if the image is public)')
param ghcrUsername string = ''

@secure()
param ghcrPassword string = ''

var namePrefix = 'phixem'
var storageName = take('phixembak${uniqueString(resourceGroup().id)}', 24)
var envName = '${namePrefix}-env'
var appName = namePrefix
var containerName = 'phixem-backups'
var replicaPath = '/phixem.db'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${namePrefix}-logs'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storage
  name: 'default'
}

resource backups 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

resource managedEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: envName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

var registryPassword = ghcrPassword
var resolvedStorageKey = empty(storageAccountKey) ? storage.listKeys().keys[0].value : storageAccountKey

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  properties: {
    managedEnvironmentId: managedEnv.id
    configuration: {
      secrets: concat(
        [
          { name: 'secret-key-base', value: secretKeyBase }
          { name: 'litestream-account-key', value: resolvedStorageKey }
        ],
        empty(ghcrPassword)
          ? []
          : [{ name: 'ghcr-password', value: registryPassword }]
      )
      registries: empty(ghcrPassword)
        ? []
        : [
            {
              server: 'ghcr.io'
              username: ghcrUsername
              passwordSecretRef: 'ghcr-password'
            }
          ]
      ingress: {
        external: true
        targetPort: 8080
        allowInsecure: false
        transport: 'auto'
      }
    }
    template: {
      terminationGracePeriodSeconds: 30
      scale: {
        minReplicas: 0
        maxReplicas: 1
      }
      containers: [
        {
          name: appName
          image: containerImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          probes: [
            {
              type: 'Startup'
              httpGet: { path: '/health', port: 8080, scheme: 'HTTP' }
              periodSeconds: 5
              failureThreshold: 24
            }
            {
              type: 'Liveness'
              httpGet: { path: '/health', port: 8080, scheme: 'HTTP' }
              periodSeconds: 30
              initialDelaySeconds: 10
            }
            {
              type: 'Readiness'
              httpGet: { path: '/health', port: 8080, scheme: 'HTTP' }
              periodSeconds: 10
              initialDelaySeconds: 5
            }
          ]
          env: [
            { name: 'PHX_SERVER', value: 'true' }
            { name: 'PORT', value: '8080' }
            { name: 'SHELL', value: '/bin/sh' }
            { name: 'PHX_HOST', value: phxHost }
            { name: 'DATABASE_PATH', value: '/tmp/phixem.db' }
            { name: 'LITESTREAM_BIN', value: '/usr/local/bin/litestream' }
            { name: 'LITESTREAM_AZURE_ACCOUNT_NAME', value: storage.name }
            { name: 'LITESTREAM_AZURE_CONTAINER', value: containerName }
            { name: 'LITESTREAM_AZURE_PATH', value: replicaPath }
            { name: 'SECRET_KEY_BASE', secretRef: 'secret-key-base' }
            { name: 'LITESTREAM_AZURE_ACCOUNT_KEY', secretRef: 'litestream-account-key' }
          ]
        }
      ]
    }
  }
}

output fqdn string = containerApp.properties.configuration.ingress.fqdn
output storageAccountName string = storage.name
output containerAppName string = containerApp.name
output resourceGroupName string = resourceGroup().name
