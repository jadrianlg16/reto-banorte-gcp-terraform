terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

# Valores de ejemplo: proyecto y llave son marcadores.
module "log_export" {
  source = "../.."

  project_id       = "example-project-id"
  prefix           = "bnt"
  environment      = "common"
  name             = "audit-logs"
  location         = "us-central1"
  kms_key          = "projects/example-project-id/locations/us-central1/keyRings/example-ring/cryptoKeys/example-key"
  retention_days   = 365
  retention_locked = false
  parent           = "projects/example-project-id"

  # Los registros de acceso a datos del propio bucket no vuelven al bucket.
  exclusions = [{
    name        = "bucket-de-logs"
    description = "Acceso a datos del bucket de logs."
    filter      = "logName:\"cloudaudit.googleapis.com%2Fdata_access\" AND resource.type=\"gcs_bucket\" AND resource.labels.bucket_name=\"bnt-common-ops-audit-logs\""
  }]

  labels = {
    env         = "common"
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
