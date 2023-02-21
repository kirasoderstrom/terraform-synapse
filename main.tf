resource "azurerm_resource_group" "example" {
  name     = "terraform-synapse-demo-resources"
  location = "West US"
}

resource "github_repo" "synapse-github" {
    account_name = "kirasoderstrom"
    branch_name = "collaboration"
    repository_name = "azure-synapse"
    root_folder = "/"
} 

resource "azurerm_storage_account" "example" {
  name                     = "examplestorageacc"
  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = "true"
}

resource "azurerm_storage_data_lake_gen2_filesystem" "example" {
  name               = "example"
  storage_account_id = azurerm_storage_account.example.id
}

resource "azurerm_key_vault" "example" {
  name                     = "example"
  location                 = azurerm_resource_group.example.location
  resource_group_name      = azurerm_resource_group.example.name
  tenant_id                = data.azurerm_client_config.current.tenant_id
  sku_name                 = "standard"
  purge_protection_enabled = true
}

resource "azurerm_key_vault_access_policy" "deployer" {
  key_vault_id = azurerm_key_vault.example.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Create", "Get", "Delete", "Purge"
  ]
}

resource "azurerm_key_vault_key" "example" {
  name         = "workspaceencryptionkey"
  key_vault_id = azurerm_key_vault.example.id
  key_type     = "RSA"
  key_size     = 2048
  key_opts = [
    "unwrapKey",
    "wrapKey"
  ]
  depends_on = [
    azurerm_key_vault_access_policy.deployer
  ]
}

resource "azurerm_synapse_workspace" "example" {
  name                                 = "example"
  resource_group_name                  = azurerm_resource_group.example.name
  location                             = azurerm_resource_group.example.location
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.example.id
  sql_administrator_login              = "sqladminuser"
  sql_administrator_login_password     = "H@Sh1CoR3!"

  customer_managed_key {
    key_versionless_id = azurerm_key_vault_key.example.versionless_id
    key_name           = "enckey"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Env = "production"
  }
}

resource "azurerm_key_vault_access_policy" "workspace_policy" {
  key_vault_id = azurerm_key_vault.example.id
  tenant_id    = azurerm_synapse_workspace.example.identity[0].tenant_id
  object_id    = azurerm_synapse_workspace.example.identity[0].principal_id

  key_permissions = [
    "Get", "WrapKey", "UnwrapKey"
  ]
}

resource "azurerm_synapse_workspace_key" "example" {
  customer_managed_key_versionless_id = azurerm_key_vault_key.example.versionless_id
  synapse_workspace_id                = azurerm_synapse_workspace.example.id
  active                              = true
  customer_managed_key_name           = "enckey"
  depends_on                          = [azurerm_key_vault_access_policy.workspace_policy]
}

resource "azurerm_synapse_workspace_aad_admin" "example" {
  synapse_workspace_id = azurerm_synapse_workspace.example.id
  login                = "AzureAD Admin"
  object_id            = "00000000-0000-0000-0000-000000000000"
  tenant_id            = "00000000-0000-0000-0000-000000000000"

  depends_on = [azurerm_synapse_workspace_key.example]
}