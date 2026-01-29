@description('Function App name (must be globally unique).')
param functionAppName string = 'azure-func-demo-rahul-prem'

@description('Deployment location (defaults to RG location).')
param location string = resourceGroup().location

@description('Application name for the APP_NAME app setting')
param appName string = 'azure-func-demo-rahul'

@description('Application version for the APP_VERSION app setting')
param appVersion string = '1.0.0'

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
// App Configuration Store
// ------------------------------
var appConfigName = 'appcfg-${cleanedName}-${uniq}'

resource appConfiguration 'Microsoft.AppConfiguration/configurationStores@2023-03-01' = {
  name: appConfigName
  location: location
  sku: {
    name: 'standard'
  }
  properties: {
    enablePurgeProtection: false
    publicNetworkAccess: 'Enabled'
  }
}

// Create Key-Value configurations in App Configuration
resource configAppName 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfiguration
  name: 'APP_NAME'
  properties: {
    value: appName
    contentType: 'application/json'
  }
}

resource configAppVersion 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfiguration
  name: 'APP_VERSION'
  properties: {
    value: appVersion
    contentType: 'application/json'
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
    targetWorkerCount: 1
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
        // Use Oryx build during deployment; do NOT use run-from-package (it bypasses build)
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'true' }

        // --- App Insights ---
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }

        // --- App Configuration ---
        { name: 'APP_CONFIG_ENDPOINT', value: appConfiguration.properties.endpoint }

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
// RBAC for MI (assigned at resource group level)
// Storage Blob Data Contributor and Storage Queue Data Contributor
// will be granted via role assignment on the storage account in the workflow
// ------------------------------
// Note: Role assignments are better managed in the deployment workflow
// to avoid deployment conflicts. See .github/workflows/azure-functions-ci-cd.yml



// ------------------------------
// Outputs
// ------------------------------
output functionAppName string = functionApp.name
output storageAccountName string = storage.name
output appConfigurationEndpoint string = appConfiguration.properties.endpoint
output appConfigurationName string = appConfiguration.name