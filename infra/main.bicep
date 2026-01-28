param functionAppName string = 'azure-func-demo-rahul-ci'
param location string = resourceGroup().location

// Storage account names must be 3-24 characters, lowercase letters and numbers only.
// Build a short name: prefix from cleaned functionAppName + short unique suffix.
var cleanedName = toLower(replace(functionAppName, '-', ''))
var uniq = substring(uniqueString(resourceGroup().id), 0, 6)
var prefixLen = max(0, 24 - length(uniq))
var prefix = substring(cleanedName, 0, prefixLen)
var storageName = '${prefix}${uniq}'

resource storage 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Enabled'
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${functionAppName}-ai'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource plan 'Microsoft.Web/serverfarms@2021-02-01' = {
  name: '${functionAppName}-plan'
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  kind: 'functionapp,linux'
  properties: {
    reserved: true
  }
}

// Use resource symbol invocation for keys so Bicep tracks the dependency automatically
var storageKey = storage.listKeys().keys[0].value
var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storageKey};EndpointSuffix=core.windows.net'

resource functionApp 'Microsoft.Web/sites@2022-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: plan.id
    siteConfig: {
    linuxFxVersion: 'PYTHON|3.10'
      appSettings: [
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'AzureWebJobsStorage'
          value: storageConnectionString
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
      ]
    }
  }
  // Bicep automatically infers dependencies from references; explicit dependsOn is unnecessary here
}

output functionAppName string = functionApp.name
output storageAccountName string = storage.name
