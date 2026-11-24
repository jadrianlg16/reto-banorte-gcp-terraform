# Apagado fuera de horario de dev y qa (ADR 0028), con off_hours_shutdown.enabled:
# - Cloud SQL y los pools de GKE: trabajos de Cloud Scheduler (módulo off-hours-shutdown) con la
#   cuenta <prefix>-<env>-<app>-sched (service_accounts.tf), que solo tiene el rol del apagado
#   que crea 1-base una vez para todo el proyecto (off_hours_role_id);
# - el MIG: programa de escalado de su autoescalador (business_hours en compute.tf);
# - Backup and DR: la ventana de respaldo se mueve al horario encendido (operations.tf).
# Sin deriva: Cloud SQL ignora activation_policy (módulo cloud-sql, allow_scheduled_stop) y los
# pools ignoran autoscaling (módulo gke, scheduled_scaling); el MIG es declarativo.

locals {
  off_hours_enabled = var.off_hours_shutdown.enabled

  # Horario encendido calculado por el módulo (zona horaria, crons, minutos del día y duración).
  off_hours_window = length(module.off_hours_shutdown) == 0 ? null : module.off_hours_shutdown["this"].window

  # MIG (compute.tf): el programa de escalado empieza con el cron de encendido y dura todo el
  # horario encendido.
  mig_business_hours = local.off_hours_window == null ? null : {
    schedule     = local.off_hours_window.start_schedule
    duration_sec = local.off_hours_window.duration_sec
    time_zone    = local.off_hours_window.time_zone
  }

  # Backup and DR (operations.tf): con Cloud SQL detenida no hay respaldo, así que la ventana de
  # 6 horas empieza en la primera hora cerrada desde el encendido, en su zona horaria (la
  # variable off_hours_shutdown valida que quepa en el horario encendido). Sin apagado, los
  # valores por defecto del módulo backup-dr.
  backup_window = local.off_hours_window == null ? {
    start_hour = 1
    time_zone  = "America/Mexico_City"
    } : {
    start_hour = ceil(local.off_hours_window.start_minute / 60)
    time_zone  = local.off_hours_window.time_zone
  }
}

module "off_hours_shutdown" {
  source   = "../../../../modules/off-hours-shutdown"
  for_each = local.off_hours_enabled ? toset(["this"]) : toset([])

  project_id   = var.project_id
  prefix       = var.prefix
  environment  = var.environment
  region       = var.primary_region
  region_codes = var.region_codes

  time_zone      = var.off_hours_shutdown.time_zone
  start_schedule = var.off_hours_shutdown.start_schedule
  stop_schedule  = var.off_hours_shutdown.stop_schedule

  service_account_email = local.scheduler_service_account

  # Solo la primaria: con off_hours_shutdown no hay réplica (se rechaza con enable_dr).
  sql_instances = { primary = module.cloud_sql.instance_name }

  # Solo el clúster primario: dr_active exige enable_dr, que el apagado rechaza.
  gke_node_pools = var.enable_gke ? {
    for k, p in module.gke["primary"].node_pools : k => {
      location       = p.location
      cluster        = p.cluster
      node_pool      = p.name
      min_node_count = p.min_node_count
      max_node_count = p.max_node_count
    }
  } : {}

  # La cuenta debe tener el rol antes de que corra el primer trabajo.
  depends_on = [terraform_data.upstream_checks, google_project_iam_member.scheduler]
}

# Aviso (no error) en cada plan con Cloud SQL detenida: no es deriva, pero un apply que cree
# bases o usuarios IAM en la instancia fallará hasta el encendido (HYPOTHESIS: la API rechaza
# esas operaciones con la instancia detenida). Para aplicar antes: lanzar el trabajo de
# encendido (salida off_hours_shutdown, job_ids["sql-primary-start"]) con gcloud scheduler jobs
# run.
check "cloud_sql_encendida" {
  assert {
    condition     = module.cloud_sql.activation_policy != "NEVER"
    error_message = "Cloud SQL está detenida (activation_policy NEVER) por el apagado fuera de horario (ADR 0028). El plan no la enciende: un apply que cree bases de datos o usuarios IAM fallará hasta la hora de encendido. Para encenderla antes, lance el trabajo de encendido (salida off_hours_shutdown) con gcloud scheduler jobs run."
  }
}
