variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
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

variable "github_owner" {
  description = "GitHub repository owner for Cloud Build trigger"
  type        = string
  default     = "nguieangoue"
}

variable "github_repo" {
  description = "GitHub repository name for Cloud Build trigger"
  type        = string
  default     = "cloud-weather-dashboard"
} 