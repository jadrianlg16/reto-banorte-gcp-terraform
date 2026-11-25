terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {}

# Política de red de la VPC hub: sin reglas propias, solo la denegación por defecto de la
# entrada que crea el módulo (el hub no tiene cargas).
module "firewall_hub" {
  source = "../.."

  prefix      = "bnt"
  environment = "common"
  name_suffix = "hub"
  parent      = "projects/example-landing-zone/global/networks/bnt-common-net-hub"
}

# Política de red de un spoke con etiquetas seguras, en el mismo proyecto.
module "firewall_spoke" {
  source = "../.."

  prefix      = "bnt"
  environment = "dev"
  parent      = "projects/example-landing-zone/global/networks/bnt-dev-net-spoke"

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

output "hub_policy_id" {
  description = "Política de red de la VPC hub."
  value       = module.firewall_hub.policy_id
}

output "spoke_secure_tag_ids" {
  description = "Valores de etiquetas seguras del spoke."
  value       = module.firewall_spoke.secure_tag_ids
}

output "spoke_secure_tag_key_ids" {
  description = "Llaves de etiquetas seguras del spoke (una por etiqueta)."
  value       = module.firewall_spoke.secure_tag_key_ids
}
