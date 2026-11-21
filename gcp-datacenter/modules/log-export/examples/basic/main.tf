terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

# Valores de ejemplo: proyecto, carpeta y llave son marcadores.
module "log_export" {
  source = "../.."

  project_id       = "example-logging-project"
  prefix           = "bnt"
  environment      = "prod"
  name             = "data-access-logs"
  location         = "us-central1"
  kms_key          = "projects/example-security-project/locations/us-central1/keyRings/example-ring/cryptoKeys/example-key"
  retention_days   = 365
  retention_locked = false
  parent           = "folders/000000000000"
  filter           = "logName:\"cloudaudit.googleapis.com%2Fdata_access\""

  labels = {
    env         = "prod"
    app         = "logging"
    owner       = "example-team"
    cost_center = "example-000"
    managed_by  = "terraform"
  }
}

output "bucket_name" {
  description = "Bucket de logs."
  value       = module.log_export.bucket_name
}
