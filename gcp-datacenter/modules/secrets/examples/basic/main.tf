# Ejemplo: dos contenedores de prod replicados en dos regiones con CMEK. Valores de ejemplo.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

module "secrets" {
  source = "../.."

  project_id  = "example-security-project"
  prefix      = "bnt"
  environment = "prod"
  names       = ["api-token", "partner-cert"]

  kms_keys = {
    "us-central1" = "projects/example-security-project/locations/us-central1/keyRings/bnt-prod-sec-keyring-usc1/cryptoKeys/bnt-prod-sec-secrets"
    "us-east4"    = "projects/example-security-project/locations/us-east4/keyRings/bnt-prod-sec-keyring-use4/cryptoKeys/bnt-prod-sec-secrets"
  }

  accessors = ["serviceAccount:bnt-prod-app-workload@example-app-project.iam.gserviceaccount.com"]

  labels = {
    env         = "prod"
    app         = "security"
    owner       = "example-team"
    cost_center = "cc-000"
    managed_by  = "terraform"
  }
}

output "secret_ids" {
  description = "IDs de los secretos por nombre."
  value       = module.secrets.secret_ids
}
