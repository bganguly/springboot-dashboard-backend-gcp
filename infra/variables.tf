variable "gcp_project"     { type = string }
variable "gcp_region"      { type = string; default = "us-central1" }
variable "name_prefix"     { type = string; default = "dash" }
variable "db_name"         { type = string; default = "app" }
variable "db_username"     { type = string; default = "appuser" }
variable "db_tier"         { type = string; default = "db-custom-4-15360" }
variable "db_disk_gb"      { type = number; default = 100 }
variable "backend_image"   { type = string; default = "" }
variable "frontend_image"  { type = string; default = "" }
