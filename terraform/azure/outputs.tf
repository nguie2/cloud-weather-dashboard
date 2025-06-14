output "function_app_url" {
  description = "URL of the Azure Function App"
  value       = "https://${azurerm_linux_function_app.weather_function.default_hostname}"
}

output "function_app_name" {
  description = "Name of the Azure Function App"
  value       = azurerm_linux_function_app.weather_function.name
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "cosmos_account_name" {
  description = "Name of the CosmosDB account"
  value       = azurerm_cosmosdb_account.weather_db.name
}

output "cosmos_database_name" {
  description = "Name of the CosmosDB database"
  value       = azurerm_cosmosdb_sql_database.weather_data.name
}

output "cosmos_container_name" {
  description = "Name of the CosmosDB container"
  value       = azurerm_cosmosdb_sql_container.weather_records.name
}

output "cosmos_connection_string" {
  description = "CosmosDB connection string"
  value       = azurerm_cosmosdb_account.weather_db.connection_strings[0]
  sensitive   = true
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.functions.name
}

output "application_insights_name" {
  description = "Name of Application Insights"
  value       = azurerm_application_insights.main.name
}

output "logic_app_name" {
  description = "Name of the Logic App"
  value       = azurerm_logic_app_workflow.weather_scheduler.name
} 