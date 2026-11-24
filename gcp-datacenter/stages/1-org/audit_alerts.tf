# Métricas de log y alertas de auditoría (CIS 2.5 a 2.12) en cada proyecto de common: los
# detectores de Security Command Center revisan proyecto por proyecto. Esta etapa crea esos
# proyectos y queda como dueña (README, "Roles que necesita la cuenta de la etapa"), igual que
# para las llaves y el tema de Pub/Sub del proyecto logging: no hace falta un rol nuevo.
# Logging y Monitoring los habilita project-factory en cada proyecto; las llamadas usan el
# semilla como proyecto de cuota, que también los tiene.
module "audit_alerts" {
  source   = "../../modules/audit-alerts"
  for_each = local.common_projects

  project_id         = module.common_project[each.key].project_id
  prefix             = var.prefix
  environment        = local.environment
  notification_email = var.groups["security_admins"]
  labels             = merge(local.labels, { app = each.value.name })
}
