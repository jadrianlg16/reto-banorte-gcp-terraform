terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

# Ejemplo de prod con tier REGIONAL. Todos los valores son de ejemplo.
module "filestore" {
  source = "../.."

  project_id        = "example-prod-app"
  prefix            = "bnt"
  environment       = "prod"
  tier              = "REGIONAL"
  location          = "us-central1"
  capacity_gb       = 1024
  network           = "projects/example-prod-net-spoke/global/networks/bnt-prod-net-vpc"
  reserved_ip_range = "bnt-prod-net-psa"
  kms_key           = "projects/example-common-security/locations/us-central1/keyRings/bnt-prod-sec-usc1/cryptoKeys/filestore"

  nfs_export_options = [
    { ip_ranges = ["10.30.0.0/20"] },
  ]

  labels = {
    env         = "prod"
    app         = "app"
    owner       = "example-team"
    cost_center = "example-cc"
    managed_by  = "terraform"
  }
}

output "ip_address" {
  description = "IP privada del servidor NFS."
  value       = module.filestore.ip_address
}
