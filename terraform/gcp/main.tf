# GCP Provider Configuration
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudrun.googleapis.com",
    "firestore.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])

  service            = each.value
  disable_on_destroy = false
}

# Firestore Database
resource "google_firestore_database" "weather_db" {
  project     = var.gcp_project_id
  name        = "(default)"
  location_id = var.gcp_region
  type        = "FIRESTORE_NATIVE"

  depends_on = [google_project_service.required_apis]
}

# Secret Manager for API keys
resource "google_secret_manager_secret" "openweather_api_key" {
  secret_id = "openweather-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "openweather_api_key" {
  secret      = google_secret_manager_secret.openweather_api_key.id
  secret_data = var.openweather_api_key
}

resource "google_secret_manager_secret" "weather_api_key" {
  secret_id = "weather-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "weather_api_key" {
  secret      = google_secret_manager_secret.weather_api_key.id
  secret_data = var.weather_api_key
}

resource "google_secret_manager_secret" "accuweather_api_key" {
  secret_id = "accuweather-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "accuweather_api_key" {
  secret      = google_secret_manager_secret.accuweather_api_key.id
  secret_data = var.accuweather_api_key
}

# Service Account for Cloud Run
resource "google_service_account" "cloud_run_sa" {
  account_id   = "${var.project_name}-cloud-run-sa"
  display_name = "Cloud Run Service Account for ${var.project_name}"
  description  = "Service account for Cloud Run weather functions"
}

# IAM bindings for Service Account
resource "google_project_iam_member" "cloud_run_sa_firestore" {
  project = var.gcp_project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "cloud_run_sa_secrets" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "cloud_run_sa_logging" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Artifact Registry for container images
resource "google_artifact_registry_repository" "weather_repo" {
  location      = var.gcp_region
  repository_id = "${var.project_name}-repo"
  description   = "Container repository for weather functions"
  format        = "DOCKER"

  depends_on = [google_project_service.required_apis]
}

# Build and push container image using Cloud Build
resource "google_cloudbuild_trigger" "weather_function_build" {
  name        = "${var.project_name}-weather-function-build"
  description = "Build and deploy weather function container"

  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      branch = "^main$"
    }
  }

  build {
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t",
        "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.weather_repo.repository_id}/weather-function:$COMMIT_SHA",
        "-f",
        "docker/gcp/Dockerfile",
        "."
      ]
    }

    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.weather_repo.repository_id}/weather-function:$COMMIT_SHA"
      ]
    }

    step {
      name = "gcr.io/cloud-builders/gcloud"
      args = [
        "run",
        "deploy",
        "${var.project_name}-weather-function",
        "--image",
        "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.weather_repo.repository_id}/weather-function:$COMMIT_SHA",
        "--region",
        var.gcp_region,
        "--platform",
        "managed",
        "--allow-unauthenticated"
      ]
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Run Service
resource "google_cloud_run_service" "weather_function" {
  name     = "${var.project_name}-weather-function"
  location = var.gcp_region

  template {
    spec {
      service_account_name = google_service_account.cloud_run_sa.email
      
      containers {
        image = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.weather_repo.repository_id}/weather-function:latest"

        ports {
          container_port = 8080
        }

        env {
          name  = "GCP_PROJECT_ID"
          value = var.gcp_project_id
        }

        env {
          name  = "CLOUD_PROVIDER"
          value = "gcp"
        }

        env {
          name = "OPENWEATHER_API_KEY"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.openweather_api_key.secret_id
              key  = "latest"
            }
          }
        }

        env {
          name = "WEATHER_API_KEY"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.weather_api_key.secret_id
              key  = "latest"
            }
          }
        }

        env {
          name = "ACCUWEATHER_API_KEY"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.accuweather_api_key.secret_id
              key  = "latest"
            }
          }
        }

        resources {
          limits = {
            cpu    = "1000m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }

      timeout_seconds = 300
    }

    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale" = "10"
        "autoscaling.knative.dev/minScale" = "0"
        "run.googleapis.com/cpu-throttling" = "false"
        "run.googleapis.com/execution-environment" = "gen2"
      }

      labels = {
        environment = var.environment
        project     = var.project_name
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    google_project_service.required_apis,
    google_artifact_registry_repository.weather_repo
  ]

  lifecycle {
    ignore_changes = [
      template[0].spec[0].containers[0].image
    ]
  }
}

# Cloud Run IAM - Allow unauthenticated access
resource "google_cloud_run_service_iam_member" "public_access" {
  service  = google_cloud_run_service.weather_function.name
  location = google_cloud_run_service.weather_function.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Cloud Scheduler for periodic execution
resource "google_cloud_scheduler_job" "weather_scheduler" {
  name             = "${var.project_name}-weather-scheduler"
  description      = "Trigger weather data collection every 15 minutes"
  schedule         = "*/15 * * * *"
  time_zone        = "UTC"
  attempt_deadline = "300s"

  retry_config {
    retry_count = 3
  }

  http_target {
    http_method = "POST"
    uri         = "${google_cloud_run_service.weather_function.status[0].url}/weather"

    oidc_token {
      service_account_email = google_service_account.cloud_run_sa.email
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring - Log-based metrics
resource "google_logging_metric" "weather_function_errors" {
  name   = "${var.project_name}-weather-function-errors"
  filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_service.weather_function.name}\" AND severity>=ERROR"

  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Weather Function Errors"
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring - Alerting Policy
resource "google_monitoring_alert_policy" "weather_function_errors" {
  display_name = "${var.project_name} Weather Function Error Rate"
  combiner     = "OR"

  conditions {
    display_name = "Weather Function Error Rate"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.weather_function_errors.name}\" AND resource.type=\"cloud_run_revision\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 5

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = []

  documentation {
    content = "Weather function error rate has exceeded the threshold"
  }

  depends_on = [google_project_service.required_apis]
} 