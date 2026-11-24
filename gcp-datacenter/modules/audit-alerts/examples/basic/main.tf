terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

# Ejemplo: métricas de log y alertas de auditoría (CIS 2.5 a 2.12) del proyecto logging de
# common, con aviso al grupo security_admins. Valores de ejemplo únicamente.
module "audit_alerts" {
  source = "../.."

  project_id         = "bnt-common-logging"
  prefix             = "bnt"
  environment        = "common"
  notification_email = "gcp-security-admins@example.com"

  labels = {
    env         = "common"
    app         = "logging"
    owner       = "seguridad"
    cost_center = "cc-0000"
    managed_by  = "terraform"
  }
}

output "metric_names" {
  description = "Métricas de log creadas."
  value       = module.audit_alerts.metric_names
}

output "alert_policy_ids" {
  description = "Políticas de alerta creadas."
  value       = module.audit_alerts.alert_policy_ids
}
