# Fixture de integración del módulo load-balancer (externo): balanceador HTTPS global con
# certificado administrado, redirección de HTTP y política de Cloud Armor, con un servicio de
# Cloud Run de muestra como backend (NEG sin servidor). El certificado no llega a ACTIVE sin el
# registro DNS del dominio: la prueba no lo espera.

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
  description = "Región del servicio de muestra."
  type        = string
}

variable "domain" {
  description = "Dominio del certificado administrado."
  type        = string
}

variable "image" {
  description = "Imagen del servicio de muestra."
  type        = string
}

variable "labels" {
  description = "Etiquetas obligatorias de la prueba."
  type        = map(string)
}

# Backend de muestra construido sin el módulo cloud-run, para probar solo el balanceador.
resource "google_cloud_run_v2_service" "backend" {
  project             = var.project_id
  name                = "${var.prefix}-lb-backend"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  deletion_protection = false
  labels              = var.labels

  template {
    containers {
      image = var.image
    }
  }
}

resource "google_compute_region_network_endpoint_group" "backend" {
  project               = var.project_id
  name                  = "${var.prefix}-lb-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.backend.name
  }
}

resource "google_compute_security_policy" "armor" {
  project = var.project_id
  name    = "${var.prefix}-lb-armor"
}

module "external_lb" {
  source = "../../../modules/load-balancer"

  project_id      = var.project_id
  prefix          = var.prefix
  environment     = "dev"
  name            = "web"
  type            = "external"
  labels          = var.labels
  domain_names    = [var.domain]
  security_policy = google_compute_security_policy.armor.self_link

  default_backend = "web"
  backends = {
    web = {
      serverless = true
      groups     = [{ group = google_compute_region_network_endpoint_group.backend.id }]
    }
  }
}

output "ip_address" {
  description = "IP pública."
  value       = module.external_lb.ip_address
}

output "backend_service_ids" {
  description = "Servicios de backend."
  value       = module.external_lb.backend_service_ids
}

output "url_map_name" {
  description = "Mapa de URL HTTPS."
  value       = module.external_lb.url_map_name
}

output "forwarding_rule_names" {
  description = "Reglas de reenvío (https y http)."
  value       = module.external_lb.forwarding_rule_names
}

output "security_policy" {
  description = "Política de Cloud Armor esperada en el backend."
  value       = google_compute_security_policy.armor.self_link
}
