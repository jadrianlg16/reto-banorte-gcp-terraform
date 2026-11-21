# Fixture de integración del módulo observability: canal de correo, alertas base, SLO de 99.9 %
# y tablero; una verificación de disponibilidad solo si la prueba recibe un host.

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

variable "notification_email" {
  description = "Buzón que recibe las alertas de la prueba."
  type        = string
}

variable "uptime_host" {
  description = "Host para una verificación de disponibilidad (vacío: ninguna)."
  type        = string
  default     = ""
}

variable "labels" {
  description = "Etiquetas obligatorias de la prueba."
  type        = map(string)
}

module "observability" {
  source = "../../../modules/observability"

  project_id          = var.project_id
  prefix              = var.prefix
  environment         = "dev"
  notification_emails = [var.notification_email]
  slo_target          = 0.999

  uptime_checks = var.uptime_host == "" ? {} : {
    web = {
      host = var.uptime_host
      path = "/"
    }
  }

  labels = var.labels
}

output "notification_channel_ids" {
  description = "Canales de notificación."
  value       = module.observability.notification_channel_ids
}

output "dashboard_ids" {
  description = "Tableros."
  value       = module.observability.dashboard_ids
}

output "alert_policy_ids" {
  description = "Políticas de alerta."
  value       = module.observability.alert_policy_ids
}

output "slo_id" {
  description = "SLO de disponibilidad."
  value       = module.observability.slo_id
}
