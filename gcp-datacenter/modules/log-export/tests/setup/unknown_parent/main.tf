# Raíz auxiliar de la prueba: la carpeta padre se crea en el mismo plan, así que su número no
# se conoce en el plan. Comprueba que el módulo igual decide qué sink crear.
terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

resource "google_folder" "parent" {
  display_name = "prod"
  parent       = "organizations/000000000000"
}

module "log_export" {
  source = "../../.."

  project_id     = "bnt-common-logging"
  prefix         = "bnt"
  environment    = "prod"
  name           = "data-access-logs"
  location       = "us-central1"
  kms_key        = "projects/example-security/locations/us-central1/keyRings/example-ring/cryptoKeys/example-key"
  retention_days = 365
  parent         = "folders/${google_folder.parent.folder_id}"

  labels = {
    env         = "prod"
    app         = "logging"
    owner       = "example-team"
    cost_center = "example-000"
    managed_by  = "terraform"
  }
}

output "sink_name" {
  description = "Nombre del sink creado por el módulo."
  value       = module.log_export.sink_name
}
