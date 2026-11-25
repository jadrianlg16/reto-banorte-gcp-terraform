terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

# Ejemplo mínimo: política de Cloud Armor con los conjuntos OWASP por defecto y un límite de tasa
# con bloqueo temporal. Valores de ejemplo únicamente.
module "cloud_armor" {
  source = "../.."

  project_id  = "example-prod-app"
  prefix      = "bnt"
  environment = "prod"
  name        = "web"

  rate_limit = {
    action           = "rate_based_ban"
    count            = 300
    interval_sec     = 60
    ban_duration_sec = 900
  }
}

output "policy_self_link" {
  description = "self_link de la política creada."
  value       = module.cloud_armor.policy_self_link
}
