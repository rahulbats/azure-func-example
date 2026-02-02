# ------------------------------
# Terraform Backend Configuration
# State stored in Azure Storage for CI/CD persistence
# ------------------------------

terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstaterahul2026"
    container_name       = "tfstate"
    key                  = "azure-func-demo.tfstate"
    use_oidc             = true
  }
}
