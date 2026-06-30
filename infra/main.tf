# --- APIs ---
resource "google_project_service" "apis" {
  for_each = toset([
    "sqladmin.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "vpcaccess.googleapis.com",
    "servicenetworking.googleapis.com",
  ])
  service            = each.key
  disable_on_destroy = false
}

# --- VPC ---
resource "google_compute_network" "main" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.apis]
}

resource "google_compute_subnetwork" "main" {
  name          = "${var.name_prefix}-subnet"
  ip_cidr_range = "10.8.0.0/20"
  region        = var.gcp_region
  network       = google_compute_network.main.id
}

resource "google_compute_global_address" "private_ip_range" {
  name          = "${var.name_prefix}-sql-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_vpc" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
  depends_on              = [google_project_service.apis]
}

resource "google_vpc_access_connector" "main" {
  name   = "${var.name_prefix}-connector"
  region = var.gcp_region
  subnet { name = google_compute_subnetwork.main.name }
  min_instances = 2
  max_instances = 3
  depends_on    = [google_project_service.apis]
}

# --- Cloud SQL ---
resource "random_password" "db_password" {
  length  = 24
  special = false
}

resource "google_sql_database_instance" "pg" {
  name             = "${var.name_prefix}-db"
  database_version = "POSTGRES_16"
  region           = var.gcp_region
  depends_on       = [google_service_networking_connection.private_vpc]

  settings {
    tier            = var.db_tier
    disk_size       = var.db_disk_gb
    disk_autoresize = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.main.id
    }

    database_flags { name = "max_connections" value = "200" }
    backup_configuration { enabled = true }
  }

  deletion_protection = false
}

resource "google_sql_database" "app" {
  name     = var.db_name
  instance = google_sql_database_instance.pg.name
}

resource "google_sql_user" "app" {
  name     = var.db_username
  instance = google_sql_database_instance.pg.name
  password = random_password.db_password.result
}

# --- Secret Manager ---
resource "google_secret_manager_secret" "database_url" {
  secret_id  = "${var.name_prefix}-database-url"
  depends_on = [google_project_service.apis]
  replication { auto {} }
}

resource "google_secret_manager_secret_version" "database_url" {
  secret      = google_secret_manager_secret.database_url.id
  secret_data = "postgresql://${var.db_username}:${random_password.db_password.result}@${google_sql_database_instance.pg.private_ip_address}:5432/${var.db_name}"
}

# --- Artifact Registry ---
resource "google_artifact_registry_repository" "app" {
  location      = var.gcp_region
  repository_id = "${var.name_prefix}-repo"
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}

# --- Service Account (backend only needs DB access) ---
resource "google_service_account" "backend" {
  account_id   = "${var.name_prefix}-backend-sa"
  display_name = "Dashboard Backend SA"
}

resource "google_secret_manager_secret_iam_member" "backend_db_url" {
  secret_id = google_secret_manager_secret.database_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_project_iam_member" "backend_sql" {
  project = var.gcp_project
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.backend.email}"
}

# --- Cloud Run: Backend (Spring Boot) ---
resource "google_cloud_run_v2_service" "backend" {
  name       = "${var.name_prefix}-backend"
  location   = var.gcp_region
  depends_on = [google_artifact_registry_repository.app]

  template {
    service_account = google_service_account.backend.email

    vpc_access {
      connector = google_vpc_access_connector.main.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = var.backend_image != "" ? var.backend_image : "us-docker.pkg.dev/cloudrun/container/hello"
      ports { container_port = 8080 }
      resources { limits = { cpu = "2", memory = "1Gi" } }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }
    }

    scaling { min_instance_count = 1 max_instance_count = 5 }
  }

  traffic { type = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST" percent = 100 }
}

resource "google_cloud_run_v2_service_iam_member" "backend_public" {
  project  = var.gcp_project
  location = var.gcp_region
  name     = google_cloud_run_v2_service.backend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- Cloud Run: Frontend (nginx + React) ---
resource "google_cloud_run_v2_service" "frontend" {
  name       = "${var.name_prefix}-frontend"
  location   = var.gcp_region
  depends_on = [google_artifact_registry_repository.app]

  template {
    containers {
      image = var.frontend_image != "" ? var.frontend_image : "us-docker.pkg.dev/cloudrun/container/hello"
      ports { container_port = 80 }
      resources { limits = { cpu = "1", memory = "512Mi" } }

      env {
        name  = "BACKEND_URL"
        value = google_cloud_run_v2_service.backend.uri
      }
    }

    scaling { min_instance_count = 1 max_instance_count = 3 }
  }

  traffic { type = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST" percent = 100 }
}

resource "google_cloud_run_v2_service_iam_member" "frontend_public" {
  project  = var.gcp_project
  location = var.gcp_region
  name     = google_cloud_run_v2_service.frontend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
