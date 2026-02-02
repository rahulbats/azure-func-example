# ------------------------------
# Terraform configuration for Azure Function App
# Equivalent to main.bicep
# ------------------------------

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  use_oidc = true
  storage_use_azuread = true  # Use Azure AD for storage data plane (required when shared keys disabled)
}

# ------------------------------
# Variables
# ------------------------------
variable "function_app_name" {
  description = "Function App name (must be globally unique)"
  type        = string
  default     = "azure-func-demo-rahul-prem"
}

variable "location" {
  description = "Deployment location"
  type        = string
  default     = "centralus"
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "app_name" {
  description = "Application name for the APP_NAME app setting"
  type        = string
  default     = "azure-func-demo-rahul"
}

variable "app_version" {
  description = "Application version for the APP_VERSION app setting"
  type        = string
  default     = "1.0.0"
}

# ------------------------------
# Data sources
# ------------------------------
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

data "azurerm_client_config" "current" {}

# ------------------------------
# Random suffix for unique names
# ------------------------------
resource "random_string" "unique" {
  length  = 6
  special = false
  upper   = false
}

locals {
  cleaned_name = lower(replace(var.function_app_name, "-", ""))
  storage_name = substr("${local.cleaned_name}${random_string.unique.result}", 0, 24)
  app_config_name = "appcfg-${local.cleaned_name}-${random_string.unique.result}"
}

# ------------------------------
# Storage Account (Shared Key disabled; MI-only)
# ------------------------------
resource "azurerm_storage_account" "storage" {
  name                     = local.storage_name
  resource_group_name      = data.azurerm_resource_group.rg.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"
  
  shared_access_key_enabled       = false
  public_network_access_enabled   = true
  
  # Required: Grant deploying SP data plane access for Terraform to manage blobs/queues
  # The SP needs 'Storage Blob Data Contributor' role on this storage account
}

# ------------------------------
# App Configuration Store
# ------------------------------
resource "azurerm_app_configuration" "appconfig" {
  name                = local.app_config_name
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  sku                 = "standard"
  
  purge_protection_enabled   = false
  public_network_access      = "Enabled"
  local_auth_enabled         = true  # Required for Terraform to write keys
}

# ------------------------------
# RBAC: App Configuration Data Owner for deploying Service Principal
# This allows Terraform to create/update keys in App Configuration
# ------------------------------
resource "azurerm_role_assignment" "appconfig_data_owner_deployer" {
  scope                = azurerm_app_configuration.appconfig.id
  role_definition_name = "App Configuration Data Owner"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = "ServicePrincipal"
}

# Create Key-Value configurations in App Configuration
resource "azurerm_app_configuration_key" "app_name" {
  configuration_store_id = azurerm_app_configuration.appconfig.id
  key                    = "APP_NAME"
  value                  = var.app_name
  content_type           = "application/json"
  
  depends_on = [azurerm_role_assignment.appconfig_data_owner_deployer]
}

resource "azurerm_app_configuration_key" "app_version" {
  configuration_store_id = azurerm_app_configuration.appconfig.id
  key                    = "APP_VERSION"
  value                  = var.app_version
  content_type           = "application/json"
  
  depends_on = [azurerm_role_assignment.appconfig_data_owner_deployer]
}

# ------------------------------
# Application Insights
# ------------------------------
resource "azurerm_application_insights" "appinsights" {
  name                = "${var.function_app_name}-ai"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  application_type    = "web"
}

# ------------------------------
# Premium plan (EP1)
# ------------------------------
resource "azurerm_service_plan" "plan" {
  name                = "${var.function_app_name}-plan"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "EP1"
}

# ------------------------------
# Function App (Linux, Python 3.10) with System-Assigned MI
# ------------------------------
resource "azurerm_linux_function_app" "functionapp" {
  name                = var.function_app_name
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  service_plan_id     = azurerm_service_plan.plan.id
  
  # Storage configuration with managed identity
  storage_account_name          = azurerm_storage_account.storage.name
  storage_uses_managed_identity = true
  
  https_only = true
  
  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on = true
    application_stack {
      python_version = "3.10"
    }
  }

  app_settings = {
    # Functions runtime
    FUNCTIONS_WORKER_RUNTIME      = "python"
    FUNCTIONS_EXTENSION_VERSION   = "~4"
    AzureWebJobsFeatureFlags      = "EnableWorkerIndexing"
    
    # Package deployment / Kudu (ZipDeploy or Oryx)
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    
    # App Insights
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.appinsights.connection_string
    
    # App Configuration
    APP_CONFIG_ENDPOINT = azurerm_app_configuration.appconfig.endpoint
    
    # Identity-based AzureWebJobsStorage (NO keys)
    "AzureWebJobsStorage__credential"      = "managedidentity"
    "AzureWebJobsStorage__accountName"     = azurerm_storage_account.storage.name
    "AzureWebJobsStorage__blobServiceUri"  = azurerm_storage_account.storage.primary_blob_endpoint
    "AzureWebJobsStorage__queueServiceUri" = azurerm_storage_account.storage.primary_queue_endpoint
  }

  # Ignore changes to app settings that may be modified by deployment
  lifecycle {
    ignore_changes = [
      app_settings["WEBSITE_RUN_FROM_PACKAGE"],
    ]
  }
}

# ------------------------------
# RBAC: App Configuration Data Reader for Function App MI
# ------------------------------
resource "azurerm_role_assignment" "appconfig_data_reader" {
  scope                = azurerm_app_configuration.appconfig.id
  role_definition_name = "App Configuration Data Reader"
  principal_id         = azurerm_linux_function_app.functionapp.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# ------------------------------
# RBAC: Storage Blob Data Contributor for Function App MI
# ------------------------------
resource "azurerm_role_assignment" "storage_blob_contributor" {
  scope                = azurerm_storage_account.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.functionapp.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# ------------------------------
# RBAC: Storage Queue Data Contributor for Function App MI
# ------------------------------
resource "azurerm_role_assignment" "storage_queue_contributor" {
  scope                = azurerm_storage_account.storage.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_linux_function_app.functionapp.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# ------------------------------
# Outputs
# ------------------------------
output "function_app_name" {
  value = azurerm_linux_function_app.functionapp.name
}

output "storage_account_name" {
  value = azurerm_storage_account.storage.name
}

output "app_configuration_endpoint" {
  value = azurerm_app_configuration.appconfig.endpoint
}

output "app_configuration_name" {
  value = azurerm_app_configuration.appconfig.name
}
