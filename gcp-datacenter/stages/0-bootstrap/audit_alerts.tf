# Métricas de log y alertas de auditoría del proyecto semilla (CIS 2.5 a 2.12; los detectores
# de Security Command Center revisan cada proyecto). Las crea esta etapa porque es la dueña del
# proyecto: la persona que corre la etapa 0 queda como owner del proyecto que crea, así que no
# hace falta ningún rol nuevo. Logging y Monitoring los habilita project-factory.
# VERIFICAR-EN-APPLY: que Cloud Monitoring acepte las credenciales de usuario de la etapa 0 sin
# proyecto de cuota explícito (pendientes 22 y 58; si no, el paso 3 del runbook 01).
module "seed_audit_alerts" {
  source = "../../modules/audit-alerts"

  project_id         = module.seed_project.project_id
  prefix             = var.prefix
  environment        = local.environment
  notification_email = var.security_alert_email
  labels             = merge(local.labels, { app = "seed" })
}
