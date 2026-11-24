# Fixture de integración del módulo firewall (política de red, la única desde el ADR 0029 §6):
# política global asociada a una VPC de la prueba, con dos etiquetas seguras (una llave por
# etiqueta, con padre el proyecto de la VPC) y reglas por etiqueta.

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
  description = "Región de la subred de apoyo."
  type        = string
}

module "network" {
  source = "../support/network"

  project_id = var.project_id
  name       = "${var.prefix}-fw"
  region     = var.region
}

module "firewall" {
  source = "../../../modules/firewall"

  prefix      = var.prefix
  environment = "dev"
  parent      = module.network.network_id

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

output "policy_name" {
  description = "Nombre de la política de red."
  value       = module.firewall.policy_name
}

output "policy_id" {
  description = "ID de la política."
  value       = module.firewall.policy_id
}

output "secure_tag_ids" {
  description = "Valores de etiqueta segura por llave."
  value       = module.firewall.secure_tag_ids
}

output "secure_tag_key_ids" {
  description = "Llaves de etiqueta segura."
  value       = module.firewall.secure_tag_key_ids
}

output "network_name" {
  description = "VPC asociada."
  value       = module.network.network_name
}
