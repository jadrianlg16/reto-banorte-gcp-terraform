terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {}

# Spoke de prod con DR: subredes en las dos regiones, PSA, peering con el hub y NAT. El hub
# vive en el mismo proyecto (ADR 0029).
module "network_spoke" {
  source = "../.."

  project_id  = "example-landing-zone"
  prefix      = "bnt"
  environment = "prod"
  enable_dr   = true

  regions = {
    primary = "us-central1"
    dr      = "us-east4"
  }

  hub_network_self_link = "projects/example-landing-zone/global/networks/bnt-common-net-hub"

  subnet_cidrs = {
    app           = "10.30.0.0/20"
    app_dr        = "10.30.16.0/20"
    proxy         = "10.30.32.0/23"
    proxy_dr      = "10.30.34.0/23"
    run           = "10.30.36.0/24"
    run_dr        = "10.30.37.0/24"
    gke_master    = "10.30.38.0/28"
    gke_master_dr = "10.30.38.16/28"
    pods          = "10.30.64.0/18"
    services      = "10.30.128.0/20"
    services_dr   = "10.30.160.0/20"
    psa           = "10.30.176.0/20"
    pods_dr       = "10.30.192.0/18"
  }

  labels = {
    env         = "prod"
    app         = "network"
    owner       = "example-team"
    cost_center = "example-cc"
    managed_by  = "terraform"
  }
}

output "subnets" {
  description = "Subredes del spoke."
  value       = module.network_spoke.subnets
}

output "psa_range_name" {
  description = "Rango de Private Service Access."
  value       = module.network_spoke.psa_range_name
}
