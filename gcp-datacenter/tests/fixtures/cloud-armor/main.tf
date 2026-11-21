# Fixture de integración del módulo cloud-armor: política con los conjuntos OWASP por defecto y
# un límite de tasa con bloqueo temporal.

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

module "cloud_armor" {
  source = "../../../modules/cloud-armor"

  project_id  = var.project_id
  prefix      = var.prefix
  environment = "dev"
  name        = "web"

  rate_limit = {
    action           = "rate_based_ban"
    count            = 300
    interval_sec     = 60
    ban_duration_sec = 900
  }
}

output "policy_name" {
  description = "Nombre de la política."
  value       = module.cloud_armor.policy_name
}

output "policy_self_link" {
  description = "self_link de la política."
  value       = module.cloud_armor.policy_self_link
}
