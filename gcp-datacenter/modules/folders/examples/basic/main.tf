terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

# Valores de ejemplo: el número de organización es un marcador.
module "folders" {
  source = "../.."

  parent = "organizations/000000000000"
  names  = ["common", "dev", "qa", "prod"]
}

output "folder_ids" {
  description = "Carpetas creadas por entorno."
  value       = module.folders.ids
}
