locals {
  region_code    = var.region_short_codes[var.region]
  dr_region_code = var.region_short_codes[var.dr_region]

  # §4.2: <empresa>-<entorno>-bkp-<recurso>-<región>.
  name = "${var.prefix}-${var.environment}-bkp"

  retention_seconds = var.retention_days * 86400

  gke = var.enable_gke_backup ? toset(["gke"]) : toset([])
}

# ---------------------------------------------------------------------------------------------
# Backup and DR Service: bóveda en la región secundaria y planes diarios en la región primaria
# ---------------------------------------------------------------------------------------------

# La bóveda vive en dr_region (región secundaria) y fija la retención mínima forzada: ningún
# respaldo se puede borrar antes de retention_days, ni siquiera por un administrador.
# VERIFICAR-EN-APPLY: la API backupdr.googleapis.com habilitada en el proyecto (0-bootstrap la
# activa) y que la bóveda en otra región acepte respaldos de VM y Cloud SQL de region.
# VERIFICAR-EN-APPLY: un destroy (dev) falla mientras la bóveda tenga respaldos dentro de la
# retención forzada; el runbook de destroy debe contemplarlo.
#
# Restricción de acceso (var.access_restriction, WITHIN_PROJECT por defecto): la bóveda, sus
# planes y los recursos que respalda están en el mismo proyecto (ADR 0029), así que respaldar y
# restaurar dentro del proyecto basta. La API usa WITHIN_ORGANIZATION si no se indica nada, y ese
# valor supone una organización que el proyecto puede no tener (enum AccessRestriction de
# https://docs.cloud.google.com/backup-disaster-recovery/docs/reference/rest/v1/projects.locations.backupVaults;
# sección "Backup vault access restriction" de
# https://docs.cloud.google.com/backup-disaster-recovery/docs/concepts/backup-vault, que además
# dice que el valor es permanente: cambiarlo después de crear la bóveda no está previsto).
# VERIFICAR-EN-APPLY: que la bóveda se cree con WITHIN_PROJECT en un proyecto sin organización y
# que los respaldos de VM y Cloud SQL del mismo proyecto entren en ella.
resource "google_backup_dr_backup_vault" "this" {
  project         = var.project_id
  location        = var.dr_region
  backup_vault_id = "${local.name}-vault-${local.dr_region_code}"
  description     = "Bóveda de respaldos de ${var.environment} en la región secundaria (${var.dr_region})."
  labels          = var.labels

  backup_minimum_enforced_retention_duration = "${local.retention_seconds}s"
  backup_retention_inheritance               = "INHERIT_VAULT_RETENTION"
  access_restriction                         = var.access_restriction
}

# VERIFICAR-EN-APPLY: el plan de Cloud SQL (sqladmin.googleapis.com/Instance) en provider 6.x y
# que la cuenta de servicio de la bóveda (salida vault_service_account) tenga los roles que pide
# Backup and DR sobre los recursos protegidos. Ninguna raíz los otorga todavía: la cuenta de la
# bóveda solo se conoce después de crearla (3-workloads) y la cuenta de cargas del entorno no
# asigna roles de proyecto.
resource "google_backup_dr_backup_plan" "this" {
  for_each = var.backup_plans

  project        = var.project_id
  location       = var.region
  backup_plan_id = "${local.name}-${each.key}-plan-${local.region_code}"
  description    = "Respaldo diario de ${each.value} con retención de ${var.retention_days} días."
  resource_type  = each.value
  backup_vault   = google_backup_dr_backup_vault.this.id

  # Solo Cloud SQL: días de registros de transacciones que guarda el plan. Con respaldos
  # mejorados el plan sobrescribe la configuración de respaldos de la instancia y define esta
  # retención ("Manage enhanced backups"), así que es la ventana de recuperación a un punto en
  # el tiempo. VERIFICAR-EN-APPLY: que la API acepte el valor y que PITR cubra esos días.
  log_retention_days = each.value == "sqladmin.googleapis.com/Instance" ? var.sql_log_retention_days : null

  backup_rules {
    rule_id               = "daily"
    backup_retention_days = var.retention_days

    standard_schedule {
      recurrence_type = "DAILY"
      time_zone       = var.backup_time_zone

      backup_window {
        start_hour_of_day = var.backup_window_start_hour
        end_hour_of_day   = var.backup_window_start_hour + 6
      }
    }
  }
}

resource "google_backup_dr_backup_plan_association" "this" {
  for_each = var.protected_resources

  project                    = var.project_id
  location                   = var.region
  backup_plan_association_id = "${local.name}-${each.key}-bpa-${local.region_code}"
  resource                   = each.value.resource
  resource_type              = var.backup_plans[each.value.plan]
  backup_plan                = google_backup_dr_backup_plan.this[each.value.plan].name
}

# ---------------------------------------------------------------------------------------------
# Backup for GKE: plan diario en la región secundaria, cifrado con CMEK
# ---------------------------------------------------------------------------------------------

# VERIFICAR-EN-APPLY: plan de Backup for GKE en una región distinta a la del clúster (respaldo
# entre regiones), el complemento Backup for GKE activo en el clúster y el permiso
# cryptoKeyEncrypterDecrypter del agente de servicio de gkebackup sobre gke_backup_kms_key.
resource "google_gke_backup_backup_plan" "this" {
  for_each = local.gke

  project     = var.project_id
  location    = var.dr_region
  name        = "${local.name}-gke-plan-${local.dr_region_code}"
  description = "Respaldo diario del clúster de GKE de ${var.environment} con retención de ${var.retention_days} días."
  cluster     = var.gke_cluster_id
  labels      = var.labels

  backup_schedule {
    cron_schedule = var.gke_backup_cron
  }

  retention_policy {
    backup_retain_days      = var.retention_days
    backup_delete_lock_days = var.gke_backup_delete_lock_days
  }

  backup_config {
    all_namespaces      = true
    include_volume_data = true
    include_secrets     = true

    encryption_key {
      gcp_kms_encryption_key = var.gke_backup_kms_key
    }
  }

  lifecycle {
    precondition {
      condition     = strcontains(coalesce(var.gke_backup_kms_key, "-"), "/locations/${var.dr_region}/")
      error_message = "gke_backup_kms_key debe estar en dr_region, la misma región del plan de Backup for GKE."
    }
  }
}
