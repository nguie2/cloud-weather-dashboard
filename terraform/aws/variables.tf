variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "cloud-weather-dashboard"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "openweather_api_key" {
  description = "OpenWeather API key"
  type        = string
  sensitive   = true
}

variable "weather_api_key" {
  description = "WeatherAPI key"
  type        = string
  sensitive   = true
}

variable "accuweather_api_key" {
  description = "AccuWeather API key"
  type        = string
  sensitive   = true
}

variable "azure_function_url" {
  description = "Azure Function URL for cross-cloud aggregation"
  type        = string
  default     = ""
}

variable "gcp_function_url" {
  description = "GCP Cloud Run URL for cross-cloud aggregation"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
} 