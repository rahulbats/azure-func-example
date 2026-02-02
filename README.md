# Azure Function Demo - Deployment Guide

This repository contains a **demo Azure Function application** that demonstrates how to read environment variables and print them via HTTP triggers. The environment variables are automatically injected using **Bicep Infrastructure-as-Code (IaC) templates**, and the entire deployment pipeline is fully automated using **GitHub Actions CI/CD** with Oryx build configuration.

## Overview

- **Function Behavior**: The Azure Function HTTP trigger reads 2 sample environment variables (`APP_NAME`, `APP_VERSION`) and outputs them in the HTTP response
- **Infrastructure Automation**: All Azure resources (Storage, App Insights, App Service Plan, Function App) and app settings are defined in Bicep templates
- **Deployment Automation**: GitHub Actions automatically deploys infrastructure and application code on every push to the main branch
- **Zero-Touch Deployment**: No manual configuration needed—everything is automated via IaC and CI/CD

## Table of Contents

- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Local Development Setup](#local-development-setup)
- [Deployment Steps](#deployment-steps)
- [Infrastructure](#infrastructure)
- [CI/CD Pipeline](#cicd-pipeline)

## Prerequisites

- **Azure Subscription**: An active Azure subscription
- **Azure CLI**: [Install Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- **Python 3.11+**: [Download Python](https://www.python.org/downloads/)
- **Bicep CLI**: `az bicep install`
- **Git**: For version control

### Azure Entra (AD) Configuration for GitHub Actions OIDC

For CI/CD automation, configure the following in Azure Entra:

1. **Service Principal**: Create an Azure AD Application (Service Principal) that GitHub Actions will use
2. **Federated Credentials**: Configure GitHub as a federated identity provider:
   - Add federated credential linking your GitHub repository to the Azure AD app
   - This enables keyless OIDC authentication (no secrets needed in GitHub)
   - Configure for: `repo:<owner>/<repo>:ref:refs/heads/main`
3. **Contributor Role**: Assign the **Contributor** role to the service principal at the subscription or resource group level
   - This allows GitHub Actions to deploy resources via Bicep templates
   - Minimum required permissions: Can create/modify Storage, App Insights, App Service Plan, and Function App resources

## Project Structure

```
azure-function-test/
├── function_app.py              # Azure Function application code
├── host.json                    # Azure Functions host configuration
├── requirements.txt             # Python dependencies
├── README.md                    # This file
├── .funcignore                  # Files to ignore when publishing
├── .gitignore                   # Git ignore rules
├── infra/
│   └── main.bicep              # Bicep template for Azure resources
├── .github/
│   └── workflows/
│       └── azure-functions-deploy.yml  # GitHub Actions workflow
└── .vscode/
    ├── launch.json             # VS Code debug configuration
    ├── settings.json           # VS Code workspace settings
    ├── tasks.json              # VS Code tasks
    └── extensions.json         # Recommended VS Code extensions
```

## Local Development Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd azure-function-test
```

### 2. Create Python Virtual Environment

```bash
python -m venv .venv
```

**Activate the virtual environment:**

- **Windows (PowerShell)**: `.\.venv\Scripts\Activate.ps1`
- **Windows (cmd)**: `.\.venv\Scripts\activate.bat`
- **macOS/Linux**: `source .venv/bin/activate`

### 3. Install Dependencies

```bash
pip install -r requirements.txt
```

### 4. Run Locally

Start the Azure Functions runtime:

```bash
func start
```

The function will be available at `http://localhost:7071`

### 5. Test the Function

```bash
curl http://localhost:7071/api/<function-name>
```

## Deployment Steps

### Step 1: Prepare Azure Resources

1. **Login to Azure**:
   ```bash
   az login
   ```

2. **Set your subscription** (if you have multiple):
   ```bash
   az account set --subscription <subscription-id>
   ```

3. **Create a Resource Group**:
   ```bash
   az group create --name azure-func-rg --location eastus
   ```

### Step 2: Deploy Infrastructure with Bicep

The Bicep template creates:
- Storage Account (for function state and logs)
- App Insights (for monitoring and diagnostics)
- App Service Plan (Dynamic Y1 tier for Functions)
- Azure Function App (Linux-based with Python 3.11 runtime)

**Deploy the infrastructure**:

```bash
az deployment group create \
  --resource-group azure-func-rg \
  --template-file infra/main.bicep \
  --parameters functionAppName=azure-func-demo-rahul-ci
```

**Customize parameters**:

```bash
az deployment group create \
  --resource-group azure-func-rg \
  --template-file infra/main.bicep \
  --parameters \
    functionAppName=my-custom-function-name \
    location=eastus
```

### Step 3: Build and Package Application

**Option A: Using Oryx (Automated - Recommended)**

Oryx automatically detects Python and builds your application:

```bash
# Navigate to project root
cd /path/to/azure-function-test

# Oryx will detect requirements.txt and install dependencies
# This is done automatically during deployment
```

**Option B: Manual Build

```bash
# Create deployment package
func azure functionapp publish <function-app-name> --build remote
```

### Step 4: Deploy to Azure Function

**Using Azure Functions CLI**:

```bash
# Publish the function app
func azure functionapp publish <function-app-name> --build remote

# The `--build remote` flag triggers Oryx build on Azure
```

**Using Azure CLI**:

```bash
# Create a zip package
Compress-Archive -Path ./* -DestinationPath function.zip -Force

# Deploy the zip
az functionapp deployment source config-zip \
  --resource-group azure-func-rg \
  --name <function-app-name> \
  --src-path function.zip
```

### Step 5: Verify Deployment

```bash
# Check function app status
az functionapp show \
  --resource-group azure-func-rg \
  --name <function-app-name>

# Get the function URL
az functionapp show \
  --resource-group azure-func-rg \
  --name <function-app-name> \
  --query defaultHostName \
  --output tsv

# Test the deployed function
curl https://<function-app-name>.azurewebsites.net/api/<function-name>
```

## Infrastructure

### Bicep Template Overview

The `infra/main.bicep` template defines:

**Parameters**:
- `functionAppName`: Name of the Azure Function App
- `location`: Azure region for resources

**Resources Created**:

1. **Storage Account**
   - SKU: Standard_LRS
   - Kind: StorageV2
   - Used for function runtime and state

2. **Application Insights**
   - Type: Web
   - Provides monitoring and diagnostics

3. **App Service Plan**
   - Tier: Dynamic (Y1)
   - Kind: functionapp
   - Auto-scales for serverless execution

4. **Azure Function App**
   - Runtime: Python 3.11
   - OS: Linux
   - Connected to Storage and Application Insights

**Outputs**:
- `functionAppName`: Name of the deployed function app
- `storageAccountName`: Name of the storage account

### Deployment Architecture

```
Resource Group (azure-func-rg)
├── Storage Account
├── Application Insights
├── App Service Plan
└── Azure Function App
    ├── Runtime: Python 3.11
    └── Configuration: App Settings (Storage Connection, App Insights Key, etc.)
```

## CI/CD Pipeline

The repository includes a GitHub Actions workflow (`.github/workflows/azure-functions-deploy.yml`) that automates deployment:

### Workflow Triggers

- Push to `main` branch
- Manual trigger via GitHub Actions

### Workflow Steps

1. **Checkout code**
2. **Setup Python** (3.11)
3. **Install dependencies** using Oryx-compatible approach
4. **Build** (Oryx build on Azure)
5. **Deploy** to Azure Function App

### Setup CI/CD

1. **Configure OIDC Authentication** (Recommended - No secrets needed after initial setup):
   - Set up Federated credentials in Azure AD for GitHub Actions
   - This enables keyless authentication using OpenID Connect (OIDC)

2. **Create GitHub Secrets** for OIDC:
   - `AZURE_CLIENT_ID`: Your Azure AD application client ID
   - `AZURE_TENANT_ID`: Your Azure AD tenant ID
   - `AZURE_SUBSCRIPTION_ID`: Your Azure subscription ID

   To add secrets:
   1. Go to your repository on GitHub
   2. Settings → Secrets and variables → Actions
   3. Click "New repository secret"
   4. Add each of the three secrets above

3. **Trigger workflow**:
   - Push to main branch, or
   - Manually from GitHub Actions tab

## Terraform Deployment (Alternative to Bicep)

The repository also includes Terraform templates in `infra/terraform/` as an alternative to Bicep.

### Terraform vs Bicep

| Aspect | Bicep | Terraform |
|--------|-------|-----------|
| State Management | Azure ARM (no state file) | Requires state storage |
| Permissions | Contributor role sufficient | Additional data plane roles needed |
| Multi-cloud | Azure only | Multi-cloud support |

### Prerequisites: Bootstrap Service Principal Permissions

Before running Terraform via GitHub Actions, you must **manually grant permissions** to your Service Principal. This is a one-time setup because:
- The SP cannot grant itself permissions it doesn't have
- Terraform needs these permissions before it can create any resources

#### Step 1: Get Your Service Principal Details

```bash
# Get your subscription ID
az account show --query id -o tsv

# Find your Service Principal (replace with your SP name)
az ad sp list --display-name "github-action-deployer" --query "[0].{appId:appId, objectId:id}" -o table
```

#### Step 2: Create Resource Groups

```bash
# App resource group
az group create --name <your-resource-group> --location centralus

# Terraform state resource group
az group create --name terraform-state-rg --location centralus
```

#### Step 3: Create Terraform State Storage

```bash
# Create storage account (name must be globally unique)
az storage account create \
    --name <unique-storage-name> \
    --resource-group terraform-state-rg \
    --sku Standard_LRS \
    --encryption-services blob \
    --min-tls-version TLS1_2

# Create container for state files
az storage container create \
    --name tfstate \
    --account-name <unique-storage-name> \
    --auth-mode login
```

#### Step 4: Grant Service Principal Permissions

Replace `<SP_OBJECT_ID>`, `<SUBSCRIPTION_ID>`, and `<RESOURCE_GROUP>` with your values:

```bash
# 1. Contributor - to create resources
az role assignment create \
    --role "Contributor" \
    --assignee-object-id <SP_OBJECT_ID> \
    --assignee-principal-type ServicePrincipal \
    --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RESOURCE_GROUP>

# 2. User Access Administrator - to create role assignments for Function App MI
az role assignment create \
    --role "User Access Administrator" \
    --assignee-object-id <SP_OBJECT_ID> \
    --assignee-principal-type ServicePrincipal \
    --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RESOURCE_GROUP>

# 3. Storage Blob Data Contributor - for keyless storage operations (on app RG)
az role assignment create \
    --role "Storage Blob Data Contributor" \
    --assignee-object-id <SP_OBJECT_ID> \
    --assignee-principal-type ServicePrincipal \
    --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RESOURCE_GROUP>

# 4. Storage Blob Data Contributor - for Terraform state storage
az role assignment create \
    --role "Storage Blob Data Contributor" \
    --assignee-object-id <SP_OBJECT_ID> \
    --assignee-principal-type ServicePrincipal \
    --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/terraform-state-rg/providers/Microsoft.Storage/storageAccounts/<unique-storage-name>
```

#### Step 5: Update Backend Configuration

Edit `infra/terraform/backend.tf` with your storage account name:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "<unique-storage-name>"
    container_name       = "tfstate"
    key                  = "azure-func-demo.tfstate"
    use_oidc             = true
  }
}
```

#### Step 6: Run GitHub Actions with Terraform

1. Go to **Actions** → **Azure Functions CI/CD**
2. Click **Run workflow**
3. Select **terraform** from the dropdown
4. Click **Run workflow**

### Why These Permissions?

| Permission | Why Required |
|------------|--------------|
| **Contributor** | Create Azure resources (Storage, Function App, etc.) |
| **User Access Administrator** | Create RBAC role assignments for Function App's Managed Identity |
| **Storage Blob Data Contributor** | Terraform uses Azure AD auth for keyless storage (no shared keys) |

## Environment Variables Management

### How Environment Variables Are Injected

Environment variables are automatically injected into the Azure Function App through the **Bicep template's app settings**:

1. **Bicep Template** (`infra/main.bicep`):
   - Defines app settings in the Function App resource configuration
   - Creates app settings for:
     - `FUNCTIONS_WORKER_RUNTIME`: Set to `python`
     - `FUNCTIONS_EXTENSION_VERSION`: Set to `~4`
     - `AzureWebJobsStorage`: Connection string to the Storage Account (auto-generated)
     - `APPINSIGHTS_INSTRUMENTATIONKEY`: App Insights instrumentation key (auto-generated)
     - `WEBSITE_RUN_FROM_PACKAGE`: Set to `1` for deployment from zip
     - `SCM_DO_BUILD_DURING_DEPLOYMENT`: Set to `true` for Oryx build

2. **GitHub Actions Workflow** (`.github/workflows/azure-functions-ci-cd.yml`):
   - Deploys Bicep template which creates all resources with app settings
   - Enables Oryx build via app settings: `SCM_DO_BUILD_DURING_DEPLOYMENT=true` and `ENABLE_ORYX_BUILD=true`
   - Deploys the application package, which picks up all environment variables

3. **Function App Access**:
   - Your Python function (`function_app.py`) can access these variables using:
     ```python
     import os
     
     # Read environment variables
     runtime = os.environ.get('FUNCTIONS_WORKER_RUNTIME')
     storage_conn = os.environ.get('AzureWebJobsStorage')
     app_insights_key = os.environ.get('APPINSIGHTS_INSTRUMENTATIONKEY')
     
     # Return in HTTP response
     @app.function_name("HttpTrigger")
     def http_trigger(req: func.HttpRequest) -> func.HttpResponse:
         env_vars = {
             'FUNCTIONS_WORKER_RUNTIME': runtime,
             'AzureWebJobsStorage': storage_conn,
             'APPINSIGHTS_INSTRUMENTATIONKEY': app_insights_key
         }
         return func.HttpResponse(json.dumps(env_vars), status_code=200)
     ```

### Automation Flow

```
1. Git Push (main branch)
   ↓
2. GitHub Actions Triggered
   ↓
3. Deploy Bicep Template → Creates Resources + App Settings
   ↓
4. Enable Oryx Build Settings
   ↓
5. Deploy Application Package (config-zip)
   ↓
6. Oryx Automatically Builds Python Environment
   ↓
7. Function App Starts with Environment Variables Loaded
   ↓
8. HTTP Trigger Reads and Returns Environment Variables
```

## Oryx Build Configuration

Oryx automatically:
- Detects Python runtime from `runtime.txt` or latest available
- Installs dependencies from `requirements.txt`
- Prepares the application for serverless execution
- Optimizes build for cold start performance

**Key Files for Oryx**:
- `requirements.txt`: Python packages (required)
- `.funcignore`: Files to exclude from deployment

## Troubleshooting

### Function Not Responding

```bash
# Check function app logs
az webapp log tail --resource-group azure-func-rg --name <function-app-name>
```

### Deployment Failures

```bash
# Check deployment history
az deployment group list --resource-group azure-func-rg

# View detailed error
az deployment group show \
  --resource-group azure-func-rg \
  --name <deployment-name>
```

### Local Testing Issues

```bash
# Verify Azure Functions Core Tools
func --version

# Clear local cache
rm -r .azure .funcignore

# Reinstall dependencies
pip install -r requirements.txt --force-reinstall
```

## Additional Resources

- [Azure Functions Python Developer Guide](https://learn.microsoft.com/azure/azure-functions/functions-reference-python)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/overview)
- [Oryx Build Documentation](https://github.com/microsoft/Oryx)
- [Azure Functions Deployment Slots](https://learn.microsoft.com/azure/azure-functions/functions-deployment-slots)


