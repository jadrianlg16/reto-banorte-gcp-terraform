# Fixture de integración del módulo firewall (política jerárquica; TEST_ALLOW_ORG=true). La
# política se crea y asocia a una carpeta contenedora vacía creada por la prueba, no a la
# organización, para no cambiar el tráfico de nada más.

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
  display_name        = "terratest-${var.prefix}-fw"
  parent              = var.parent
  deletion_protection = false
}

module "firewall" {
  source = "../../../modules/firewall"

  prefix      = var.prefix
  environment = "common"
  policy_type = "hierarchical"
  parent      = google_folder.container.name

  rules = {
    allow-health-checks = {
      priority       = 1000
      action         = "allow"
      src_ip_ranges  = ["35.191.0.0/16", "130.211.0.0/22"]
      layer4_configs = [{ ip_protocol = "tcp" }]
    }
    allow-iap = {
      priority       = 1010
      action         = "allow"
      src_ip_ranges  = ["35.235.240.0/20"]
      layer4_configs = [{ ip_protocol = "tcp", ports = ["22", "3389"] }]
    }
    delegate-internal = {
      priority      = 2000
      action        = "goto_next"
      src_ip_ranges = ["10.0.0.0/8", "192.168.0.0/16"]
    }
  }
}

output "policy_id" {
  description = "Política jerárquica."
  value       = module.firewall.policy_id
}

output "container_id" {
  description = "Carpeta asociada (folders/<n>)."
  value       = google_folder.container.name
}
