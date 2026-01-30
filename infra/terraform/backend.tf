# ------------------------------
# Terraform Backend Configuration
# Using local state by default
# For production, configure Azure Storage backend
# ------------------------------

# Uncomment below to use Azure Storage backend:
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "terraform-state-rg"
#     storage_account_name = "tfstateXXXXX"
#     container_name       = "tfstate"
#     key                  = "azure-func-demo.tfstate"
#   }
# }
