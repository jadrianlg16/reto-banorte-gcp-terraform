# Métricas de log y alertas de auditoría de cada proyecto de servicio (CIS 2.5 a 2.12; los
# detectores de Security Command Center revisan cada proyecto). Las crea esta etapa porque crea
# esos proyectos y su cuenta queda como dueña (igual que para Artifact Registry y Binary
# Authorization, pendiente 47): no hace falta un rol nuevo, y la cuenta de 5-workloads no recibe
# ningún permiso de Monitoring por esto. El destino es el grupo security_admins, que publica
# 1-org (security_alert_email).
module "audit_alerts" {
  source   = "../../../../modules/audit-alerts"
  for_each = var.applications

  project_id         = module.project[each.key].project_id
  prefix             = var.prefix
  environment        = var.environment
  notification_email = local.security_alert_email
  labels             = merge(local.labels, { app = each.key })
}
