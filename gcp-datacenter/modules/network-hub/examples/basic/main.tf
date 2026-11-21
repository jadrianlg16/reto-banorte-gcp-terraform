terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {}

# VPC hub con sus dos subredes (primaria y DR) y un Cloud Router por región.
module "network_hub" {
  source = "../.."

  project_id = "example-net-hub"
  prefix     = "bnt"
  router_asn = 64514

  subnets = {
    hub    = { region = "us-central1", cidr = "10.0.0.0/24" }
    hub_dr = { region = "us-east4", cidr = "10.0.1.0/24" }
  }
}

output "network_self_link" {
  description = "self_link de la VPC hub."
  value       = module.network_hub.network_self_link
}

output "routers" {
  description = "Cloud Router por región."
  value       = module.network_hub.routers
}
