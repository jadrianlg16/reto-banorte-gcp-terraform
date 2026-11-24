# Métricas de log y alertas de auditoría del proyecto net-spoke (CIS 2.5 a 2.12; los detectores
# de Security Command Center revisan cada proyecto). Las crea esta raíz porque crea el proyecto y
# su cuenta queda como dueña (pendiente 30), igual que para la red y el DNS: no hace falta un
# rol nuevo. El destino es el grupo security_admins, que publica 1-org (security_alert_email).
module "audit_alerts" {
  source = "../../../../modules/audit-alerts"

  project_id         = module.project.project_id
  prefix             = var.prefix
  environment        = var.environment
  notification_email = local.security_alert_email
  labels             = local.labels
}
