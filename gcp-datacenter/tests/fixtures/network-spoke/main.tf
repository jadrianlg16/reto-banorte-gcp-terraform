# Fixture de integración del módulo network-spoke: spoke de dev (sin DR) con las subredes de
# §5, PSA, NAT y peering en ambos sentidos con un hub mínimo creado en el mismo proyecto.

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
  description = "Región de DR (reservada; enable_dr = false)."
  type        = string
}

variable "labels" {
  description = "Etiquetas obligatorias de la prueba."
  type        = map(string)
}

# Hub mínimo: solo la VPC, para que el peering tenga contraparte.
resource "google_compute_network" "hub" {
  project                 = var.project_id
  name                    = "${var.prefix}-hub"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

module "network_spoke" {
  source = "../../../modules/network-spoke"

  project_id  = var.project_id
  prefix      = var.prefix
  environment = "dev"
  enable_dr   = false

  regions = {
    primary = var.region
    dr      = var.dr_region
  }

  hub_network_self_link = google_compute_network.hub.self_link

  subnet_cidrs = {
    app        = "10.10.0.0/20"
    proxy      = "10.10.32.0/23"
    run        = "10.10.36.0/24"
    gke_master = "10.10.38.0/28"
    pods       = "10.10.64.0/18"
    services   = "10.10.128.0/20"
    psa        = "10.10.176.0/20"
  }

  labels = var.labels
}

output "network_name" {
  description = "Nombre de la VPC spoke."
  value       = module.network_spoke.network_name
}

output "hub_network_name" {
  description = "Nombre de la VPC hub mínima."
  value       = google_compute_network.hub.name
}

output "subnets" {
  description = "Subredes del spoke."
  value       = module.network_spoke.subnets
}

output "psa_range_name" {
  description = "Rango de Private Service Access."
  value       = module.network_spoke.psa_range_name
}

output "routers" {
  description = "Cloud Router por región."
  value       = module.network_spoke.routers
}

output "nat_names" {
  description = "Cloud NAT por región."
  value       = module.network_spoke.nat_names
}
