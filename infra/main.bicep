
@description('Function App name (must be globally unique in its DNS scope).')
param functionAppName string = 'azure-func-demo-rahul-ci'

@description('Deployment location (defaults to RG location).')
param location string = resourceGroup().location

// ------------------------------
// Storage account name (3–24, lowercase/numbers)
// ------------------------------
var cleanedName = toLower(replace(functionAppName, '-', ''))
var uniq       = substring(uniqueString(resourceGroup().id), 0, 6)
var prefixLen  = max(0, 24 - length(uniq))
var prefix     = substring(cleanedName, 0, prefixLen)
var storageName = '${prefix}${uniq}'

// ------------------------------
// Storage Account  (Shared Key disabled per CSA policy)
// ------------------------------
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    // IMPORTANT: policy-compliant
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
  }
}

// ------------------------------
// Application Insights (classic component) for demo
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
// Linux Consumption (Y1) plan
// ------------------------------
resource plan 'Microsoft.Web/serverfarms@2021-02-01' = {
  name: '${functionAppName}-plan'
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  // For Linux Functions
  kind: 'functionapp,linux'
  properties: {
    reserved: true // Linux
  }
}

// ------------------------------
// Function App (Linux, Python 3.10) with System-Assigned MI
// Identity-based connection to AzureWebJobsStorage
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
    siteConfig: {
      // Fix the exact casing; invalid casing causes BadRequest
      linuxFxVersion: 'Python|3.10'
      appSettings: [
        // --- Functions runtime ---
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }

        // --- Package deployment ---
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }

        // --- App Insights (recommended modern setting) ---
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }

        // --- Identity-based AzureWebJobsStorage (NO keys) ---
        // Grant MI → Storage RBAC below. These URIs typically end with '/' — fine for the host.
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storage.name
        }
        {
          name: 'AzureWebJobsStorage__blobServiceUri'
          value: storage.properties.primaryEndpoints.blob
        }
        {
          name: 'AzureWebJobsStorage__queueServiceUri'
          value: storage.properties.primaryEndpoints.queue
        }
        // Add tables if you use them:
        // { name: 'AzureWebJobsStorage__tableServiceUri'; value: storage.properties.primaryEndpoints.table }
      ]
    }
  }
}

// ------------------------------
// RBAC: grant the Function App MI data-plane roles on the storage account
// (so the host can use AzureWebJobsStorage without keys)
// ------------------------------
var blobDataContributorRoleId  = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')  // Storage Blob Data Contributor
var queueDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88') // Storage Queue Data Contributor
// If you use Tables, add: '76199698-9eea-4c19-bc75-cec21354c6b6' (Storage Table Data Contributor)

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

// NOTE: Role assignment creation requires Microsoft.Authorization/roleAssignments/write
// permission at the scope. CI service principals often lack this permission.
// We omit creating role assignments here so infra can deploy under restricted policies.
// An admin should grant the following roles to the Function App's principalId after deployment:
// - Storage Blob Data Contributor
// - Storage Queue Data Contributor

// ------------------------------
// Outputs
// ------------------------------
output functionAppName string = functionApp.name
output storageAccountName string = storage.name
