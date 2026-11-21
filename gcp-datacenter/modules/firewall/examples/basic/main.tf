terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {}

# Política jerárquica en la organización: permite verificaciones de salud e IAP, delega en
# la política de red el tráfico interno y on-premises (goto_next) y deniega el resto.
module "firewall_org" {
  source = "../.."

  prefix      = "bnt"
  environment = "common"
  policy_type = "hierarchical"
  parent      = "organizations/000000000000"

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

# Política de red de un spoke con etiquetas seguras.
module "firewall_spoke" {
  source = "../.."

  prefix      = "bnt"
  environment = "dev"
  policy_type = "network"
  parent      = "projects/example-dev-net-spoke/global/networks/bnt-dev-net-spoke"

  secure_tags = {
    lb_backend = { description = "Backends del balanceador." }
    iap_ssh    = { description = "VM con SSH por IAP." }
  }

  rules = {
    allow-lb-to-backends = {
      priority           = 1000
      action             = "allow"
      src_ip_ranges      = ["35.191.0.0/16", "130.211.0.0/22"]
      target_secure_tags = ["lb_backend"]
      layer4_configs     = [{ ip_protocol = "tcp", ports = ["80", "443", "8080"] }]
    }
    allow-iap-ssh = {
      priority           = 1010
      action             = "allow"
      src_ip_ranges      = ["35.235.240.0/20"]
      target_secure_tags = ["iap_ssh"]
      layer4_configs     = [{ ip_protocol = "tcp", ports = ["22"] }]
    }
  }
}

output "org_policy_id" {
  description = "Política jerárquica."
  value       = module.firewall_org.policy_id
}

output "spoke_secure_tag_ids" {
  description = "Valores de etiquetas seguras del spoke."
  value       = module.firewall_spoke.secure_tag_ids
}
