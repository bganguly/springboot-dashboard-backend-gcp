output "cloud_sql_instance" {
  value = google_sql_database_instance.pg.connection_name
}

output "cloud_sql_private_ip" {
  value = google_sql_database_instance.pg.private_ip_address
}

output "database_url" {
  value     = "postgresql://${var.db_username}:${random_password.db_password.result}@${google_sql_database_instance.pg.private_ip_address}:5432/${var.db_name}"
  sensitive = true
}

output "artifact_registry" {
  value = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project}/${google_artifact_registry_repository.app.repository_id}"
}

output "backend_url" {
  value = google_cloud_run_v2_service.backend.uri
}

output "frontend_url" {
  value = google_cloud_run_v2_service.frontend.uri
}
