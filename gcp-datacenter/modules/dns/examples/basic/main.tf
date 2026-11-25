terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {}

locals {
  labels = {
    env         = "dev"
    app         = "network"
    owner       = "example-team"
    cost_center = "example-cc"
    managed_by  = "terraform"
  }
}

# Zonas de un spoke: privada del entorno, peering al hub para el dominio on-premises y la
# zona privada de googleapis.com hacia el VIP restringido.
module "dns_spoke" {
  source = "../.."

  project_id  = "example-dev-net-spoke"
  prefix      = "bnt"
  environment = "dev"
  networks    = ["projects/example-dev-net-spoke/global/networks/bnt-dev-net-spoke"]
  labels      = local.labels

  zones = {
    internal = {
      type   = "private"
      domain = "dev.empresa.internal."
    }
    onprem = {
      type         = "peering"
      domain       = "corp.example.internal."
      peer_network = "projects/example-net-hub/global/networks/bnt-common-net-hub"
    }
    googleapis = {
      type   = "private"
      domain = "googleapis.com."
      records = {
        restricted = {
          name    = "restricted"
          type    = "A"
          rrdatas = ["199.36.153.4", "199.36.153.5", "199.36.153.6", "199.36.153.7"]
        }
        wildcard = {
          name    = "*"
          type    = "CNAME"
          rrdatas = ["restricted.googleapis.com."]
        }
      }
    }
  }
}

# Hub: reenvío condicional a los servidores on-premises y política de reenvío entrante.
module "dns_hub" {
  source = "../.."

  project_id  = "example-net-hub"
  prefix      = "bnt"
  environment = "common"
  networks    = ["projects/example-net-hub/global/networks/bnt-common-net-hub"]
  labels      = merge(local.labels, { env = "common" })

  zones = {
    onprem = {
      type   = "forwarding"
      domain = "corp.example.internal."
      target_name_servers = [
        { ipv4_address = "192.168.0.10", forwarding_path = "private" },
        { ipv4_address = "192.168.0.11", forwarding_path = "private" },
      ]
    }
  }

  server_policy = {}
}

output "spoke_zone_names" {
  description = "Zonas del spoke."
  value       = module.dns_spoke.zone_names
}

output "hub_inbound_forwarder_ips" {
  description = "IP de reenvío entrante del hub."
  value       = module.dns_hub.inbound_forwarder_ips
}
