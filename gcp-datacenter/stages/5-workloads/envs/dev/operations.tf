# Observabilidad y respaldo del entorno.

module "observability" {
  source = "../../../../modules/observability"

  project_id          = local.project_id
  prefix              = var.prefix
  environment         = var.environment
  notification_emails = var.notification_emails

  # Verificación de disponibilidad sobre el primer dominio del balanceador externo (si existe).
  uptime_checks = local.external_lb_enabled ? {
    web = {
      host = var.domain_names[0]
      path = var.uptime_check_path
    }
  } : {}

  # SLO de disponibilidad del 99.9 % (§8) sobre las solicitudes del balanceador externo.
  slo_target      = 0.999
  lb_url_map_name = try(module.external_lb["external"].url_map_name, null)

  labels = local.labels

  depends_on = [terraform_data.upstream_checks]
}

locals {
  # Backup for GKE del clúster primario, en dr_region, solo con DR de datos (§7.6).
  enable_gke_backup = var.enable_backup && var.enable_gke && var.enable_dr
}

# Bóveda de Backup and DR en dr_region y plan diario de Cloud SQL (retención de 30 días). El MIG
# no lleva plan: sus VM no guardan estado y se recrean desde la plantilla; Filestore y
# Memorystore no están en Backup and DR del proveedor 6.x (Memorystore persiste con RDB).
module "backup" {
  source   = "../../../../modules/backup-dr"
  for_each = var.enable_backup ? toset(["this"]) : toset([])

  project_id         = local.project_id
  prefix             = var.prefix
  environment        = var.environment
  region             = var.primary_region
  dr_region          = var.dr_region
  region_short_codes = var.region_codes
  retention_days     = 30

  backup_plans = {
    sql = "sqladmin.googleapis.com/Instance"
  }
  # Ventana diaria de respaldo: con el apagado fuera de horario, dentro del horario encendido
  # (local.backup_window de off_hours.tf).
  # VERIFICAR-EN-APPLY: que el respaldo diario de Cloud SQL se tome dentro de esa ventana con la
  # instancia encendida, y qué pasa los días sin horario encendido (fin de semana con 1-5):
  # respaldo omitido o fallido y si eso dispara alertas de Backup and DR.
  backup_window_start_hour = local.backup_window.start_hour
  backup_time_zone         = local.backup_window.time_zone
  # Ventana de PITR de Cloud SQL con respaldos mejorados: 7 días, la misma que el módulo
  # cloud-sql fija sin plan (transaction_log_retention_days).
  sql_log_retention_days = 7
  # VERIFICAR-EN-APPLY: formato del recurso de Cloud SQL que acepta la asociación de Backup and DR (projects/<p>/instances/<instancia>) y roles de la cuenta de servicio de la bóveda sobre la instancia.
  protected_resources = {
    sql = {
      resource = "projects/${local.project_id}/instances/${module.cloud_sql.instance_name}"
      plan     = "sql"
    }
  }

  enable_gke_backup  = local.enable_gke_backup
  gke_cluster_id     = local.enable_gke_backup ? module.gke["primary"].cluster_id : null
  gke_backup_kms_key = local.enable_gke_backup ? local.kms_key_ids[var.dr_region]["backup"] : null

  labels = local.labels

  depends_on = [terraform_data.upstream_checks]
}
