terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

# Valores de ejemplo: organización, cliente de directorio, proyecto y llave son marcadores.
# El bucket lo crea log-export (sin sink propio) y el sink agregado lo crea org.
module "audit_bucket" {
  source = "../../../log-export"

  project_id     = "example-logging-project"
  prefix         = "bnt"
  environment    = "common"
  location       = "us-central1"
  kms_key        = "projects/example-security-project/locations/us-central1/keyRings/example-ring/cryptoKeys/example-key"
  retention_days = 365

  labels = {
    env         = "common"
    app         = "logging"
    owner       = "example-team"
    cost_center = "example-000"
    managed_by  = "terraform"
  }
}

module "org" {
  source = "../.."

  org_id                       = "000000000000"
  prefix                       = "bnt"
  allowed_regions              = ["us-central1", "us-east4"]
  additional_allowed_locations = ["us"]
  directory_customer_id        = "C00000000"
  log_sink_destination         = module.audit_bucket.destination
}

output "policy_names" {
  description = "Políticas de organización aplicadas."
  value       = module.org.policy_names
}
