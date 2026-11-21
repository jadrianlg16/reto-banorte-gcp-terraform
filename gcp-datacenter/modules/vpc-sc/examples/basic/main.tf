# Ejemplo: perímetro de prod en dry-run, creando la política de acceso de la organización.
# Valores de ejemplo.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

module "vpc_sc" {
  source = "../.."

  org_id      = "000000000000"
  prefix      = "bnt"
  environment = "prod"

  resources = ["projects/111111111111"]
  restricted_services = [
    "storage.googleapis.com",
    "sqladmin.googleapis.com",
    "bigquery.googleapis.com",
  ]
  # Regla de entrada del pipeline: el módulo la crea como recurso aparte
  # (..._dry_run_ingress_policy en dry-run, ..._ingress_policy forzado); otras etapas pueden
  # agregar sus propias reglas al mismo perímetro sin que este módulo las quite.
  ingress_identities = [
    "serviceAccount:bnt-tf-2-security@example-seed-project.iam.gserviceaccount.com",
    "serviceAccount:bnt-tf-4-projects@example-seed-project.iam.gserviceaccount.com",
  ]

  enforced = false
}

output "perimeter_name" {
  description = "Nombre completo del perímetro."
  value       = module.vpc_sc.perimeter_name
}

output "pipeline_ingress_dry_run" {
  description = "Regla de entrada del pipeline en dry-run (spec), administrada por el módulo."
  value       = module.vpc_sc.spec_ingress_policies
}
