# Azure Provider Configuration
terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# Data sources
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.project_name}-rg"
  location = var.azure_region

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# Storage Account for Function Apps
resource "azurerm_storage_account" "functions" {
  name                     = "${replace(var.project_name, "-", "")}funcst${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

resource "random_string" "storage_suffix" {
  length  = 4
  special = false
  upper   = false
}

# CosmosDB Account
resource "azurerm_cosmosdb_account" "weather_db" {
  name                = "${var.project_name}-cosmos-${random_string.cosmos_suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  enable_automatic_failover = true

  consistency_policy {
    consistency_level       = "BoundedStaleness"
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }

  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

resource "random_string" "cosmos_suffix" {
  length  = 4
  special = false
  upper   = false
}

# CosmosDB Database
resource "azurerm_cosmosdb_sql_database" "weather_data" {
  name                = "weather-data"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.weather_db.name
}

# CosmosDB Container
resource "azurerm_cosmosdb_sql_container" "weather_records" {
  name                  = "weather-records"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.weather_db.name
  database_name         = azurerm_cosmosdb_sql_database.weather_data.name
  partition_key_path    = "/location_id"
  partition_key_version = 1
  throughput            = 400

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/\"_etag\"/?"
    }
  }
}

# Key Vault for secrets
resource "azurerm_key_vault" "main" {
  name                        = "${var.project_name}-kv-${random_string.keyvault_suffix.result}"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Recover",
      "Backup",
      "Restore"
    ]
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

resource "random_string" "keyvault_suffix" {
  length  = 4
  special = false
  upper   = false
}

# Key Vault Secrets
resource "azurerm_key_vault_secret" "openweather_api_key" {
  name         = "openweather-api-key"
  value        = var.openweather_api_key
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "weather_api_key" {
  name         = "weather-api-key"
  value        = var.weather_api_key
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "accuweather_api_key" {
  name         = "accuweather-api-key"
  value        = var.accuweather_api_key
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "cosmos_connection_string" {
  name         = "cosmos-connection-string"
  value        = azurerm_cosmosdb_account.weather_db.connection_strings[0]
  key_vault_id = azurerm_key_vault.main.id
}

# App Service Plan
resource "azurerm_service_plan" "main" {
  name                = "${var.project_name}-asp"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1"

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# Application Insights
resource "azurerm_application_insights" "main" {
  name                = "${var.project_name}-appinsights"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "Node.JS"

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# Function App
resource "azurerm_linux_function_app" "weather_function" {
  name                = "${var.project_name}-func-${random_string.function_suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.functions.name
  storage_account_access_key = azurerm_storage_account.functions.primary_access_key
  service_plan_id            = azurerm_service_plan.main.id

  site_config {
    application_stack {
      node_version = "18"
    }

    cors {
      allowed_origins = ["*"]
    }
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"   = "~18"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key
    "COSMOS_CONNECTION_STRING"       = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=${azurerm_key_vault_secret.cosmos_connection_string.name})"
    "OPENWEATHER_API_KEY"           = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=${azurerm_key_vault_secret.openweather_api_key.name})"
    "WEATHER_API_KEY"               = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=${azurerm_key_vault_secret.weather_api_key.name})"
    "ACCUWEATHER_API_KEY"           = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=${azurerm_key_vault_secret.accuweather_api_key.name})"
    "CLOUD_PROVIDER"                = "azure"
    "COSMOS_DATABASE"               = azurerm_cosmosdb_sql_database.weather_data.name
    "COSMOS_CONTAINER"              = azurerm_cosmosdb_sql_container.weather_records.name
  }

  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

resource "random_string" "function_suffix" {
  length  = 4
  special = false
  upper   = false
}

# Grant Function App access to Key Vault
resource "azurerm_key_vault_access_policy" "function_app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_function_app.weather_function.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List"
  ]
}

# Logic App for scheduled execution (alternative to Azure Functions Timer)
resource "azurerm_logic_app_workflow" "weather_scheduler" {
  name                = "${var.project_name}-scheduler"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# Logic App Trigger (Recurrence every 15 minutes)
resource "azurerm_logic_app_trigger_recurrence" "weather_trigger" {
  name         = "weather-recurrence-trigger"
  logic_app_id = azurerm_logic_app_workflow.weather_scheduler.id
  frequency    = "Minute"
  interval     = 15
}

# Logic App Action (HTTP request to Function App)
resource "azurerm_logic_app_action_http" "call_weather_function" {
  name         = "call-weather-function"
  logic_app_id = azurerm_logic_app_workflow.weather_scheduler.id
  method       = "POST"
  uri          = "https://${azurerm_linux_function_app.weather_function.default_hostname}/api/weather"

  depends_on = [azurerm_logic_app_trigger_recurrence.weather_trigger]
} 