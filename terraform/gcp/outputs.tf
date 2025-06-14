output "cloud_run_url" {
  description = "URL of the Cloud Run service"
  value       = google_cloud_run_service.weather_function.status[0].url
}

output "cloud_run_service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_service.weather_function.name
}

output "project_id" {
  description = "GCP Project ID"
  value       = var.gcp_project_id
}

output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.weather_db.name
}

output "service_account_email" {
  description = "Email of the Cloud Run service account"
  value       = google_service_account.cloud_run_sa.email
}

output "artifact_registry_repository" {
  description = "Artifact Registry repository details"
  value = {
    name = google_artifact_registry_repository.weather_repo.name
    id   = google_artifact_registry_repository.weather_repo.repository_id
    url  = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.weather_repo.repository_id}"
  }
}

output "cloud_scheduler_job_name" {
  description = "Name of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.weather_scheduler.name
}

output "secret_manager_secrets" {
  description = "Secret Manager secret names"
  value = {
    openweather_api_key   = google_secret_manager_secret.openweather_api_key.secret_id
    weather_api_key       = google_secret_manager_secret.weather_api_key.secret_id
    accuweather_api_key   = google_secret_manager_secret.accuweather_api_key.secret_id
  }
}

output "cloud_build_trigger_name" {
  description = "Name of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.weather_function_build.name
} 