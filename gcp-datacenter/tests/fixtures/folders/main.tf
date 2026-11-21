# Fixture de integración del módulo folders. El módulo solo admite los nombres de entorno
# (bootstrap, common, dev, qa, prod), que chocarían entre corridas: se crea primero una
# carpeta contenedora única y el módulo crea dentro de ella dev y qa.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {}

variable "parent" {
  description = "Donde se crea la carpeta contenedora: folders/<n> u organizations/<n>."
  type        = string
}

variable "prefix" {
  description = "Prefijo único de la ejecución."
  type        = string
}

resource "google_folder" "container" {
  display_name        = "terratest-${var.prefix}"
  parent              = var.parent
  deletion_protection = false
}

module "folders" {
  source = "../../../modules/folders"

  parent = google_folder.container.name
  names  = ["dev", "qa"]

  # Solo para la prueba: permite el destroy.
  deletion_protection = false
}

output "container_id" {
  description = "Carpeta contenedora (folders/<n>)."
  value       = google_folder.container.name
}

output "ids" {
  description = "Carpetas creadas por el módulo."
  value       = module.folders.ids
}
