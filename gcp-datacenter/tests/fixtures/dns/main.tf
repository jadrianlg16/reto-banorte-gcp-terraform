# Fixture de integración del módulo dns: zona privada del entorno, zona privada de
# googleapis.com hacia el VIP restringido, zona de reenvío a on-premises y política de
# servidor entrante, todo sobre una VPC de la prueba.

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
  description = "Región de la subred de apoyo (las IP de reenvío entrante salen de ella)."
  type        = string
}

variable "labels" {
  description = "Etiquetas obligatorias de la prueba."
  type        = map(string)
}

module "network" {
  source = "../support/network"

  project_id = var.project_id
  name       = "${var.prefix}-dns"
  region     = var.region
}

module "dns" {
  source = "../../../modules/dns"

  project_id  = var.project_id
  prefix      = var.prefix
  environment = "dev"
  networks    = [module.network.network_id]
  labels      = var.labels

  zones = {
    internal = {
      type   = "private"
      domain = "${var.prefix}.dev.empresa.internal."
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
    onprem = {
      type   = "forwarding"
      domain = "${var.prefix}.corp.example.internal."
      target_name_servers = [
        { ipv4_address = "192.168.0.10", forwarding_path = "private" },
      ]
    }
  }

  server_policy = {}
}

output "zone_names" {
  description = "Zonas creadas."
  value       = module.dns.zone_names
}

output "policy_name" {
  description = "Política de servidor."
  value       = module.dns.policy_name
}

output "inbound_forwarder_ips" {
  description = "IP de reenvío entrante."
  value       = module.dns.inbound_forwarder_ips
}

output "network_id" {
  description = "VPC de la prueba."
  value       = module.network.network_id
}
