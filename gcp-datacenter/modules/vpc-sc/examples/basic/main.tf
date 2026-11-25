# Ejemplo: perímetro en dry-run alrededor del proyecto único (ADR 0029 §1), sobre la política de
# acceso que ya existe en la organización. Valores de ejemplo.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

module "vpc_sc" {
  source = "../.."

  prefix           = "bnt"
  environment      = "common"
  access_policy_id = "000000000000"

  resources = ["projects/111111111111"]
  restricted_services = [
    "storage.googleapis.com",
    "sqladmin.googleapis.com",
    "cloudkms.googleapis.com",
    "secretmanager.googleapis.com",
  ]
  # Regla de entrada del pipeline: el módulo la crea como recurso aparte
  # (..._dry_run_ingress_policy en dry-run, ..._ingress_policy forzado); otra raíz puede
  # agregar sus propias reglas al mismo perímetro sin que este módulo las quite.
  ingress_identities = [
    "serviceAccount:bnt-tf-base@example-project-id.iam.gserviceaccount.com",
    "serviceAccount:bnt-tf-wl-prod@example-project-id.iam.gserviceaccount.com",
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
