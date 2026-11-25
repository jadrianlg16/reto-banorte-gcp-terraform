terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {}

# El secreto no tiene valor por defecto: en una raíz real llega de Secret Manager
# (on-premises real) o de random_password (on-premises simulado).
variable "shared_secret" {
  description = "Secreto compartido IKE de los túneles."
  type        = string
  sensitive   = true
}

locals {
  labels = {
    env         = "common"
    app         = "network"
    owner       = "example-team"
    cost_center = "example-cc"
    managed_by  = "terraform"
  }
}

# On-premises simulado (ADR 0006): HA VPN entre la VPC hub y la VPC onprem-sim. Cada punta
# es una instancia del módulo y apunta al gateway de la otra.
module "vpn_hub" {
  source = "../.."

  project_id      = "example-net-hub"
  prefix          = "bnt"
  connection_name = "onprem"
  region          = "us-central1"
  network         = "projects/example-net-hub/global/networks/bnt-common-net-hub"
  router          = "bnt-common-net-hub-router-usc1"
  shared_secret   = var.shared_secret
  labels          = local.labels

  peer = {
    type                  = "gcp"
    asn                   = 65001
    gcp_gateway_self_link = module.vpn_onprem_sim.gateway_self_link
  }

  bgp_sessions = {
    if0 = { vpn_gateway_interface = 0, ip_range = "169.254.0.0/30" }
    if1 = { vpn_gateway_interface = 1, ip_range = "169.254.0.4/30" }
  }

  advertised_ranges = ["10.0.0.0/16", "10.10.0.0/16", "10.20.0.0/16", "10.30.0.0/16", "35.199.192.0/19"]
}

module "vpn_onprem_sim" {
  source = "../.."

  project_id      = "example-net-hub"
  prefix          = "bnt"
  connection_name = "onprem-sim"
  region          = "us-central1"
  network         = "projects/example-net-hub/global/networks/bnt-common-net-onprem-sim"
  router          = "bnt-common-net-onprem-sim-router-usc1"
  shared_secret   = var.shared_secret
  labels          = local.labels

  peer = {
    type                  = "gcp"
    asn                   = 64514
    gcp_gateway_self_link = module.vpn_hub.gateway_self_link
  }

  # La punta simulada invierte las IP de cada /30.
  bgp_sessions = {
    if0 = { vpn_gateway_interface = 0, ip_range = "169.254.0.0/30", router_ip = "169.254.0.2", peer_ip = "169.254.0.1" }
    if1 = { vpn_gateway_interface = 1, ip_range = "169.254.0.4/30", router_ip = "169.254.0.6", peer_ip = "169.254.0.5" }
  }

  advertised_ranges = ["192.168.0.0/24"]
}

# On-premises real: gateway externo con dos IP.
module "vpn_onprem_real" {
  source = "../.."

  project_id      = "example-net-hub"
  prefix          = "bnt"
  connection_name = "dc1"
  region          = "us-central1"
  network         = "projects/example-net-hub/global/networks/bnt-common-net-hub"
  router          = "bnt-common-net-hub-router-usc1"
  shared_secret   = var.shared_secret
  labels          = local.labels

  peer = {
    type                 = "external"
    asn                  = 65001
    external_gateway_ips = ["203.0.113.10", "203.0.113.11"]
  }

  bgp_sessions = {
    if0 = { vpn_gateway_interface = 0, ip_range = "169.254.0.8/30" }
    if1 = { vpn_gateway_interface = 1, ip_range = "169.254.0.12/30" }
  }

  advertised_ranges = ["10.0.0.0/16", "35.199.192.0/19"]
}

output "hub_tunnel_names" {
  description = "Túneles del hub hacia la VPC simulada."
  value       = module.vpn_hub.tunnel_names
}

output "onprem_real_gateway" {
  description = "Gateway HA VPN hacia on-premises real."
  value       = module.vpn_onprem_real.gateway_self_link
}
