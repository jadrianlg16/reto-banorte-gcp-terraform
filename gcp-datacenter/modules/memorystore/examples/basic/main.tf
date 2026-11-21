terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

# Ejemplo de prod (STANDARD_HA por defecto). Todos los valores son de ejemplo.
module "memorystore" {
  source = "../.."

  project_id        = "example-prod-app"
  prefix            = "bnt"
  environment       = "prod"
  region            = "us-central1"
  memory_gb         = 5
  network           = "projects/example-prod-net-spoke/global/networks/bnt-prod-net-vpc"
  reserved_ip_range = "bnt-prod-net-psa"
  kms_key           = "projects/example-common-security/locations/us-central1/keyRings/bnt-prod-sec-usc1/cryptoKeys/redis"

  labels = {
    env         = "prod"
    app         = "app"
    owner       = "example-team"
    cost_center = "example-cc"
    managed_by  = "terraform"
  }
}

output "host" {
  description = "IP privada de Redis."
  value       = module.memorystore.host
}

output "port" {
  description = "Puerto de Redis."
  value       = module.memorystore.port
}
