# Fixture de integración del módulo network-hub: VPC hub con sus dos subredes (primaria y DR)
# y un Cloud Router por región, con los rangos del plan de §5.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {}

variable "project_id" {
  description = "Proyecto de la prueba."
  type        = string
}

variable "prefix" {
  description = "Prefijo único de la ejecución."
  type        = string
}

variable "region" {
  description = "Región primaria."
  type        = string
}

variable "dr_region" {
  description = "Región de DR."
  type        = string
}

module "network_hub" {
  source = "../../../modules/network-hub"

  project_id = var.project_id
  prefix     = var.prefix
  router_asn = 64514

  subnets = {
    hub    = { region = var.region, cidr = "10.0.0.0/24" }
    hub_dr = { region = var.dr_region, cidr = "10.0.1.0/24" }
  }
}

output "network_name" {
  description = "Nombre de la VPC hub."
  value       = module.network_hub.network_name
}

output "network_self_link" {
  description = "self_link de la VPC hub."
  value       = module.network_hub.network_self_link
}

output "routers" {
  description = "Cloud Router por región."
  value       = module.network_hub.routers
}

output "subnets" {
  description = "Subredes del hub."
  value       = module.network_hub.subnets
}
