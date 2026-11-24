locals {
  instance_name = "${var.prefix}-${var.environment}-data-${var.name}-${var.region_short_codes[var.region]}"
  replica_name  = var.enable_dr ? "${var.prefix}-${var.environment}-data-${var.name}-${var.region_short_codes[var.dr_region]}" : null

  # En prod siempre REGIONAL (la validación de availability_type rechaza ZONAL en prod).
  availability_type = coalesce(var.availability_type, var.environment == "prod" ? "REGIONAL" : "ZONAL")

  # Banderas obligatorias (autenticación IAM y auditoría de PostgreSQL). Van como bloques fijos
  # en cada instancia; las adicionales con el mismo nombre se descartan para que no las reemplacen.
  # VERIFICAR-EN-APPLY: la API acepta pgaudit.log con varias clases separadas por coma
  # (ddl,role,write) y la réplica acepta las mismas banderas que la primaria.
  mandatory_flag_names = [
    "cloudsql.iam_authentication",
    "cloudsql.enable_pgaudit",
    "pgaudit.log",
    "log_checkpoints",
    "log_connections",
    "log_disconnections",
    "log_duration",
    "log_hostname",
    "log_lock_waits",
    "log_statement",
    "log_error_verbosity",
    "log_min_messages",
    "log_min_error_statement",
    "log_min_duration_statement",
    "log_temp_files",
  ]
  additional_flags = {
    for k, v in var.additional_database_flags : k => v if !contains(local.mandatory_flag_names, k)
  }

  # Para cuentas de servicio, PostgreSQL usa el correo sin el sufijo .gserviceaccount.com.
  iam_users = {
    for u in var.iam_users : lower(u.email) => {
      type = u.type
      name = u.type == "CLOUD_IAM_SERVICE_ACCOUNT" ? trimsuffix(lower(u.email), ".gserviceaccount.com") : lower(u.email)
      member = (
        u.type == "CLOUD_IAM_SERVICE_ACCOUNT" ? "serviceAccount:${lower(u.email)}" :
        u.type == "CLOUD_IAM_GROUP" ? "group:${lower(u.email)}" : null
      )
    }
  }

  # Roles para entrar con IAM. Los CLOUD_IAM_USER no reciben roles directos: ningún rol se
  # asigna a user: (§7.1); los obtienen por su grupo.
  login_roles = ["roles/cloudsql.client", "roles/cloudsql.instanceUser"]
  login_bindings = var.grant_iam_login_roles ? {
    for pair in setproduct(keys(local.iam_users), local.login_roles) :
    "${pair[0]}|${pair[1]}" => { member = local.iam_users[pair[0]].member, role = pair[1] }
    if local.iam_users[pair[0]].member != null
  } : {}

  # La condición limita los roles a esta instancia y a su réplica (para la conmutación).
  condition_instances = compact([local.instance_name, local.replica_name])
  login_condition = join(" || ", [
    for n in local.condition_instances :
    "resource.name == \"projects/${var.project_id}/instances/${n}\""
  ])
}

resource "google_sql_database_instance" "this" {
  # checkov:skip=CKV_GCP_79: la versión mayor de PostgreSQL llega por la variable database_version (por defecto POSTGRES_16); la elige 3-workloads.
  project             = var.project_id
  name                = local.instance_name
  region              = var.region
  database_version    = var.database_version
  encryption_key_name = var.kms_key
  deletion_protection = var.deletion_protection

  # Sin root_password: el usuario predeterminado postgres queda sin contraseña y el acceso es
  # solo por IAM (ADR 0015).

  settings {
    tier                        = var.sql_tier
    edition                     = var.edition
    availability_type           = local.availability_type
    disk_type                   = "PD_SSD"
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    disk_autoresize_limit       = var.disk_autoresize_limit_gb
    deletion_protection_enabled = var.deletion_protection
    retain_backups_on_delete    = true
    user_labels                 = var.labels

    # Encendida al crear. Terraform no la vuelve a imponer (lifecycle): con
    # allow_scheduled_stop la detiene y enciende el apagado fuera de horario (ADR 0028); sin él,
    # la postcondición rechaza el plan si alguien la detuvo.
    activation_policy = "ALWAYS"

    ip_configuration {
      ipv4_enabled       = false
      private_network    = var.network
      allocated_ip_range = var.allocated_ip_range
      ssl_mode           = var.ssl_mode
    }

    # Respaldos automáticos y PITR siempre encendidos al crear la instancia. Con
    # backup_plan_managed = true (respaldos mejorados de Backup and DR), el plan define el horario
    # y la retención de respaldos y de registros ("Manage enhanced backups": la configuración
    # existente se sobrescribe con el plan); el módulo deja de declarar horario, retención y días
    # de registros (atributos calculados) para no pelear con el plan en cada apply.
    # VERIFICAR-EN-APPLY: después de asociar el plan, un segundo plan de Terraform no muestra
    # cambios en settings.backup_configuration (enabled y point_in_time_recovery_enabled siguen
    # en true en la API). Si aparecen, agregar ignore_changes sobre ese bloque.
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = var.backup_plan_managed ? null : var.backup_start_time
      location                       = var.backup_location
      transaction_log_retention_days = var.backup_plan_managed ? null : var.transaction_log_retention_days

      dynamic "backup_retention_settings" {
        for_each = var.backup_plan_managed ? [] : [1]
        content {
          retained_backups = var.retained_backups
          retention_unit   = "COUNT"
        }
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = var.maintenance_window.update_track
    }

    insights_config {
      query_insights_enabled  = true
      record_application_tags = false
      record_client_address   = false
    }

    # Banderas obligatorias escritas una por una (no en un bloque dinámico) para que se vean en
    # la revisión estática. local.mandatory_flag_names debe listar las mismas.
    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
    database_flags {
      name  = "cloudsql.enable_pgaudit"
      value = "on"
    }
    database_flags {
      name  = "pgaudit.log"
      value = var.pgaudit_log
    }
    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }
    database_flags {
      name  = "log_connections"
      value = "on"
    }
    database_flags {
      name  = "log_disconnections"
      value = "on"
    }
    database_flags {
      name  = "log_duration"
      value = "on"
    }
    database_flags {
      name  = "log_hostname"
      value = "on"
    }
    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }
    database_flags {
      name  = "log_statement"
      value = "ddl"
    }
    database_flags {
      name  = "log_error_verbosity"
      value = "default"
    }
    database_flags {
      name  = "log_min_messages"
      value = "warning"
    }
    database_flags {
      name  = "log_min_error_statement"
      value = "error"
    }
    database_flags {
      name  = "log_min_duration_statement"
      value = "-1"
    }
    database_flags {
      name  = "log_temp_files"
      value = "0"
    }

    dynamic "database_flags" {
      for_each = local.additional_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  # VERIFICAR-EN-APPLY: el agente de servicio de Cloud SQL del proyecto existe y tiene
  # roles/cloudkms.cryptoKeyEncrypterDecrypter sobre kms_key (lo otorga 1-base, kms.tf).
  # VERIFICAR-EN-APPLY: la conexión de Private Service Access de la red existe antes del create.

  lifecycle {
    # La política de activación la cambian los trabajos del apagado fuera de horario de dev y
    # qa: sin esto, cada plan de la noche (drift.yml, pr.yml) propondría encender la instancia.
    # Se ignora en todos los entornos (ignore_changes no puede depender de una variable); lo que
    # se deja de ver en prod lo compensa la postcondición (ADR 0028).
    ignore_changes = [settings[0].activation_policy]

    # VERIFICAR-EN-APPLY: con la instancia detenida a mano (gcloud sql instances patch
    # --activation-policy=NEVER) y allow_scheduled_stop = false, el plan falla con este mensaje
    # (la postcondición se evalúa con el valor leído en el refresh).
    postcondition {
      condition     = var.allow_scheduled_stop || self.settings[0].activation_policy == "ALWAYS"
      error_message = "La instancia de Cloud SQL no está en activation_policy ALWAYS (detenida o encendida solo bajo demanda) y allow_scheduled_stop = false. Enciéndala con gcloud sql instances patch <instancia> --activation-policy=ALWAYS, o active el apagado fuera de horario si es dev o qa (ADR 0028)."
    }
  }
}

# Réplica de lectura entre regiones (DR). Junto con PITR en la primaria sostiene el objetivo de
# RPO <= 15 min: la replicación es asíncrona y su retraso real se mide en el apply.
resource "google_sql_database_instance" "replica" {
  # checkov:skip=CKV_GCP_79: la versión mayor la fija la primaria (variable database_version).
  # checkov:skip=CKV_GCP_14: Cloud SQL no admite respaldos automáticos en réplicas de lectura; los respalda la primaria y la réplica se promueve en una conmutación.
  for_each = var.enable_dr ? { dr = local.replica_name } : {}

  project              = var.project_id
  name                 = each.value
  region               = var.dr_region
  database_version     = var.database_version
  master_instance_name = google_sql_database_instance.this.name
  encryption_key_name  = var.dr_kms_key
  deletion_protection  = var.deletion_protection

  # Sin replica_configuration: failover_target no aplica a PostgreSQL (esquema del proveedor) y
  # la promoción es manual (runbook de conmutación).

  settings {
    tier                        = var.sql_tier
    edition                     = var.edition
    availability_type           = local.availability_type
    disk_type                   = "PD_SSD"
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    disk_autoresize_limit       = var.disk_autoresize_limit_gb
    deletion_protection_enabled = var.deletion_protection
    user_labels                 = var.labels

    ip_configuration {
      ipv4_enabled       = false
      private_network    = var.network
      allocated_ip_range = var.allocated_ip_range
      ssl_mode           = var.ssl_mode
    }

    backup_configuration {
      enabled = false
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = var.maintenance_window.update_track
    }

    insights_config {
      query_insights_enabled  = true
      record_application_tags = false
      record_client_address   = false
    }

    # Banderas obligatorias escritas una por una (no en un bloque dinámico) para que se vean en
    # la revisión estática. local.mandatory_flag_names debe listar las mismas.
    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
    database_flags {
      name  = "cloudsql.enable_pgaudit"
      value = "on"
    }
    database_flags {
      name  = "pgaudit.log"
      value = var.pgaudit_log
    }
    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }
    database_flags {
      name  = "log_connections"
      value = "on"
    }
    database_flags {
      name  = "log_disconnections"
      value = "on"
    }
    database_flags {
      name  = "log_duration"
      value = "on"
    }
    database_flags {
      name  = "log_hostname"
      value = "on"
    }
    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }
    database_flags {
      name  = "log_statement"
      value = "ddl"
    }
    database_flags {
      name  = "log_error_verbosity"
      value = "default"
    }
    database_flags {
      name  = "log_min_messages"
      value = "warning"
    }
    database_flags {
      name  = "log_min_error_statement"
      value = "error"
    }
    database_flags {
      name  = "log_min_duration_statement"
      value = "-1"
    }
    database_flags {
      name  = "log_temp_files"
      value = "0"
    }

    dynamic "database_flags" {
      for_each = local.additional_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  # VERIFICAR-EN-APPLY: réplica REGIONAL (alta disponibilidad) entre regiones con CMEK en
  # dr_region; el rango de PSA cubre ambas regiones (es global) y el retraso de replicación
  # observado queda por debajo de 15 min.
}

resource "google_sql_database" "this" {
  for_each = toset(var.databases)

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.key
}

resource "google_sql_user" "iam" {
  for_each = local.iam_users

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value.name
  type     = each.value.type
  # Sin password: los usuarios IAM se autentican con un token de acceso (ADR 0015).
}

resource "google_project_iam_member" "login" {
  for_each = local.login_bindings

  project = var.project_id
  role    = each.value.role
  member  = each.value.member

  condition {
    title       = "solo-${local.instance_name}"
    description = "Limita el rol a la instancia ${local.instance_name} y su réplica."
    expression  = "resource.type == \"sqladmin.googleapis.com/Instance\" && (${local.login_condition})"
  }

  # VERIFICAR-EN-APPLY: roles/cloudsql.client y roles/cloudsql.instanceUser aceptan la condición
  # por resource.name de la instancia y permiten entrar con un token IAM.
}
