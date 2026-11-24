# Fixture de integración del módulo audit-alerts: las nueve métricas de log de auditoría
# (CIS 2.5 a 2.12 y políticas de firewall de red), sus alertas y el canal de correo.

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

variable "labels" {
  description = "Etiquetas obligatorias de la prueba."
  type        = map(string)
}

module "audit_alerts" {
  source = "../../../modules/audit-alerts"

  project_id         = var.project_id
  prefix             = var.prefix
  environment        = "dev"
  notification_email = var.notification_email
  labels             = var.labels
}

output "metric_names" {
  description = "Métricas de log por control."
  value       = module.audit_alerts.metric_names
}

output "metric_filters" {
  description = "Filtros de las métricas por control."
  value       = module.audit_alerts.metric_filters
}

output "alert_policy_ids" {
  description = "Políticas de alerta por control."
  value       = module.audit_alerts.alert_policy_ids
}

output "notification_channel_id" {
  description = "Canal de correo."
  value       = module.audit_alerts.notification_channel_id
}
