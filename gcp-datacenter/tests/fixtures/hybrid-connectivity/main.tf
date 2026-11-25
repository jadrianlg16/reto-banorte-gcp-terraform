# Fixture de integración del módulo hybrid-connectivity (TEST_ALLOW_EXPENSIVE=true): HA VPN
# entre dos VPC de la prueba ("hub" y "onprem-sim", ADR 0006), dos túneles y BGP. Cada punta
# es una instancia del módulo y apunta al gateway de la otra.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
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
  description = "Región de los gateways."
  type        = string
}

variable "labels" {
  description = "Etiquetas obligatorias de la prueba."
  type        = map(string)
}

# Secreto IKE generado: solo existe en el estado de la prueba, que vive en la carpeta temporal.
resource "random_password" "shared_secret" {
  length  = 32
  special = false
}

module "hub_net" {
  source = "../support/network"

  project_id = var.project_id
  name       = "${var.prefix}-vpn-hub"
  region     = var.region
  cidr       = "10.0.0.0/24"
}

module "onprem_net" {
  source = "../support/network"

  project_id = var.project_id
  name       = "${var.prefix}-vpn-onprem"
  region     = var.region
  cidr       = "192.168.0.0/24"
}

resource "google_compute_router" "hub" {
  project = var.project_id
  name    = "${var.prefix}-vpn-hub-router"
  region  = var.region
  network = module.hub_net.network_id

  bgp {
    asn = 64514
  }
}

resource "google_compute_router" "onprem" {
  project = var.project_id
  name    = "${var.prefix}-vpn-onprem-router"
  region  = var.region
  network = module.onprem_net.network_id

  bgp {
    asn = 65001
  }
}

module "vpn_hub" {
  source = "../../../modules/hybrid-connectivity"

  project_id      = var.project_id
  prefix          = var.prefix
  connection_name = "onprem"
  region          = var.region
  network         = module.hub_net.network_self_link
  router          = google_compute_router.hub.name
  shared_secret   = random_password.shared_secret.result
  labels          = var.labels

  peer = {
    type                  = "gcp"
    asn                   = 65001
    gcp_gateway_self_link = module.vpn_onprem.gateway_self_link
  }

  bgp_sessions = {
    if0 = { vpn_gateway_interface = 0, ip_range = "169.254.0.0/30" }
    if1 = { vpn_gateway_interface = 1, ip_range = "169.254.0.4/30" }
  }

  advertised_ranges = ["10.0.0.0/16", "35.199.192.0/19"]
}

module "vpn_onprem" {
  source = "../../../modules/hybrid-connectivity"

  project_id      = var.project_id
  prefix          = var.prefix
  connection_name = "onprem-sim"
  region          = var.region
  network         = module.onprem_net.network_self_link
  router          = google_compute_router.onprem.name
  shared_secret   = random_password.shared_secret.result
  labels          = var.labels

  peer = {
    type                  = "gcp"
    asn                   = 64514
    gcp_gateway_self_link = module.vpn_hub.gateway_self_link
  }

  bgp_sessions = {
    if0 = { vpn_gateway_interface = 0, ip_range = "169.254.0.0/30", router_ip = "169.254.0.2", peer_ip = "169.254.0.1" }
    if1 = { vpn_gateway_interface = 1, ip_range = "169.254.0.4/30", router_ip = "169.254.0.6", peer_ip = "169.254.0.5" }
  }

  advertised_ranges = ["192.168.0.0/24"]
}

output "hub_tunnel_names" {
  description = "Túneles del lado hub."
  value       = module.vpn_hub.tunnel_names
}

output "onprem_tunnel_names" {
  description = "Túneles del lado on-premises simulado."
  value       = module.vpn_onprem.tunnel_names
}

output "hub_gateway_ip_addresses" {
  description = "IP públicas de las dos interfaces del gateway del hub."
  value       = module.vpn_hub.gateway_ip_addresses
}

output "hub_router" {
  description = "Cloud Router del hub."
  value       = google_compute_router.hub.name
}

output "hub_bgp_peer_names" {
  description = "Pares BGP del hub."
  value       = module.vpn_hub.bgp_peer_names
}
