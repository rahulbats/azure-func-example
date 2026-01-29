@description('Function App name (must be globally unique).')
param functionAppName string = 'azure-func-demo-rahul-prem'

@description('Deployment location (defaults to RG location).')
param location string = resourceGroup().location

// ------------------------------
// Storage account (3–24, lowercase/numbers)
// ------------------------------
var cleanedName = toLower(replace(functionAppName, '-', ''))
var uniq       = substring(uniqueString(resourceGroup().id), 0, 6)
var prefixLen  = max(0, 24 - length(uniq))
var prefix     = substring(cleanedName, 0, prefixLen)
var storageName = '${prefix}${uniq}'

// ------------------------------
// Storage Account (Shared Key disabled; MI-only)
// ------------------------------
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
  }
}

// ------------------------------
// Application Insights
// ------------------------------
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${functionAppName}-ai'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

// ------------------------------
// Premium plan (EP1)
// ------------------------------
resource plan 'Microsoft.Web/serverfarms@2021-02-01' = {
  name: '${functionAppName}-plan'
  location: location
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    capacity: 1
  }
  kind: 'functionapp,linux'
  properties: {
    reserved: true // Linux
   
    numberOfWorkers: 1
    maximumElasticWorkerCount: 5 
  }
}

// ------------------------------
// Function App (Linux, Python 3.10) with System-Assigned MI
// ------------------------------
resource functionApp 'Microsoft.Web/sites@2022-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Python|3.10'
      alwaysOn: true // Premium supports always-on; good for cold starts and CI stability
      appSettings: [
        // --- Functions runtime ---
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }

        // --- Package deployment / Kudu (ZipDeploy or Oryx) ---
        { name: 'WEBSITE_RUN_FROM_PACKAGE', value: '1' }
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'true' }

        // --- App Insights ---
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }

        // --- Identity-based AzureWebJobsStorage (NO keys) ---
        { name: 'AzureWebJobsStorage__credential', value: 'managedidentity' }
        { name: 'AzureWebJobsStorage__accountName', value: storage.name }
        { name: 'AzureWebJobsStorage__blobServiceUri', value: storage.properties.primaryEndpoints.blob }
        { name: 'AzureWebJobsStorage__queueServiceUri', value: storage.properties.primaryEndpoints.queue }
        // Add tables if needed:
        // { name: 'AzureWebJobsStorage__tableServiceUri', value: storage.properties.primaryEndpoints.table }
      ]
    }
  }
}

// ------------------------------
// RBAC for MI on storage (Blob + Queue Data Contributor)
// ------------------------------
var blobDataContributorRoleId  = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var queueDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')

resource raBlob 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, blobDataContributorRoleId, 'azurewebjobs-mi')
  scope: storage
  properties: {
    roleDefinitionId: blobDataContributorRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource raQueue 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, queueDataContributorRoleId, 'azurewebjobs-mi')
  scope: storage
  properties: {
    roleDefinitionId: queueDataContributorRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ------------------------------
// Outputs
// ------------------------------
output functionAppName string = functionApp.name
output storageAccountName string = storage.name