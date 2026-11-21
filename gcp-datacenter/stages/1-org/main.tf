# Etapa 1 (§7.1): carpetas, proyectos de common, bucket de logs y sink agregado, políticas
# de organización, registros de Data Access en prod, SCC y presupuesto. El IAM por grupos y
# los permisos de carpeta y proyecto de las cuentas de etapa están en iam.tf.

locals {
  environment  = "common"
  environments = ["dev", "qa", "prod"]

  labels = merge(var.labels, {
    env        = local.environment
    managed_by = "terraform"
  })

  org_parent = "organizations/${var.org_id}"

  # Proyectos de common: llave de la salida → nombre en el ID y APIs (§4.2:
  # <prefix>-common-<name>[-<sufijo>]).
  common_projects = {
    net_hub = {
      name = "net-hub"
      apis = ["compute.googleapis.com", "dns.googleapis.com", "logging.googleapis.com", "monitoring.googleapis.com"]
    }
    logging = {
      name = "logging"
      apis = ["cloudkms.googleapis.com", "logging.googleapis.com", "pubsub.googleapis.com", "storage.googleapis.com"]
    }
    security = {
      name = "security"
      apis = [
        "accesscontextmanager.googleapis.com", "cloudkms.googleapis.com", "logging.googleapis.com",
        "secretmanager.googleapis.com", "securitycenter.googleapis.com",
      ]
    }
    backup = {
      name = "backup"
      apis = ["backupdr.googleapis.com", "cloudkms.googleapis.com", "logging.googleapis.com", "storage.googleapis.com"]
    }
  }
}

# --- Carpetas -----------------------------------------------------------------------------

module "folders" {
  source = "../../modules/folders"

  parent = local.org_parent
  names  = concat([local.environment], local.environments)
}

# --- Proyectos de common ------------------------------------------------------------------

module "common_project" {
  source   = "../../modules/project-factory"
  for_each = local.common_projects

  prefix          = var.prefix
  environment     = local.environment
  name            = each.value.name
  project_suffix  = var.project_suffix
  folder_id       = module.folders.ids[local.environment]
  billing_account = var.billing_account
  apis            = each.value.apis
  labels          = merge(local.labels, { app = each.value.name })
}

# --- Llaves del proyecto logging (ADR 0018) ------------------------------------------------
# logs: CMEK del bucket de logs de auditoría. pubsub: CMEK del tema de hallazgos de SCC.

module "logging_kms" {
  source = "../../modules/kms"

  project_id           = module.common_project["logging"].project_id
  prefix               = var.prefix
  environment          = local.environment
  location             = var.primary_region
  location_short_codes = var.location_short_codes
  keys = {
    logs   = {}
    pubsub = {}
  }
  labels = merge(local.labels, { app = "logging" })
}

# --- Bucket de logs y sink agregado (un solo sink: el del módulo org) ----------------------

module "audit_logs" {
  source = "../../modules/log-export"

  project_id       = module.common_project["logging"].project_id
  prefix           = var.prefix
  environment      = local.environment
  name_suffix      = var.project_suffix
  location         = var.primary_region
  kms_key          = module.logging_kms.key_ids["logs"]
  retention_days   = var.log_retention_days
  retention_locked = var.log_retention_locked
  # parent = null: el módulo solo crea el bucket; el sink agregado lo crea el módulo org.
  parent = null
  labels = merge(local.labels, { app = "logging" })
}

# --- Políticas de organización y sink agregado ---------------------------------------------

module "org" {
  source = "../../modules/org"

  org_id                       = var.org_id
  prefix                       = var.prefix
  allowed_regions              = [var.primary_region, var.dr_region]
  additional_allowed_locations = var.additional_allowed_locations
  directory_customer_id        = var.directory_customer_id
  log_sink_destination         = module.audit_logs.destination
}

# VERIFICAR-EN-APPLY: que iam.allowedPolicyMemberDomains (directory_customer_id) no rechace
# los principalSet:// de WIF que la etapa 0 asigna a las cuentas de etapa en cambios futuros.

# --- Registros de Data Access en la carpeta prod --------------------------------------------

resource "google_folder_iam_audit_config" "prod" {
  folder  = module.folders.ids["prod"]
  service = "allServices"

  audit_log_config {
    log_type = "ADMIN_READ"
  }
  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# --- Security Command Center ----------------------------------------------------------------
# VERIFICAR-EN-APPLY (pendiente 2): el proveedor 6.x no tiene recurso para ACTIVAR Security
# Command Center en la organización (nivel Standard o Premium); se activa en la consola como
# paso manual del runbook de la etapa 0. Lo que sí se configura aquí: la notificación continua
# de hallazgos a un tema de Pub/Sub con CMEK en el proyecto logging.

resource "google_project_service_identity" "pubsub" {
  provider = google-beta

  project = module.common_project["logging"].project_id
  service = "pubsub.googleapis.com"
}

# Directo y no con encrypter_decrypters del módulo kms: el correo del agente depende del
# número del proyecto, que no se conoce en el plan (sería la llave del for_each del módulo).
resource "google_kms_crypto_key_iam_member" "pubsub_agent" {
  crypto_key_id = module.logging_kms.key_ids["pubsub"]
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = google_project_service_identity.pubsub.member
}

resource "google_pubsub_topic" "scc_findings" {
  project                    = module.common_project["logging"].project_id
  name                       = "${var.prefix}-${local.environment}-ops-scc-findings"
  kms_key_name               = module.logging_kms.key_ids["pubsub"]
  message_retention_duration = "604800s"
  labels                     = merge(local.labels, { app = "scc" })

  message_storage_policy {
    allowed_persistence_regions = [var.primary_region, var.dr_region]
  }

  depends_on = [google_kms_crypto_key_iam_member.pubsub_agent]
}

# VERIFICAR-EN-APPLY: que la cuenta de servicio de SCC pueda publicar en el tema (la API da
# el permiso al crear la notificación si quien la crea puede cambiar el IAM del tema).
resource "google_scc_v2_organization_notification_config" "findings" {
  organization = var.org_id
  location     = "global"
  config_id    = "${var.prefix}-${local.environment}-ops-scc-findings"
  description  = "Hallazgos activos de severidad alta o crítica hacia Pub/Sub."
  pubsub_topic = google_pubsub_topic.scc_findings.id

  streaming_config {
    filter = var.scc_notification_filter
  }
}

# --- Presupuesto con alertas ---------------------------------------------------------------

resource "google_billing_budget" "org" {
  billing_account = var.billing_account
  display_name    = "${var.prefix}-${local.environment}-ops-budget"

  budget_filter {
    resource_ancestors     = [local.org_parent]
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
    calendar_period        = "MONTH"
  }

  amount {
    specified_amount {
      # Sin currency_code: se usa la moneda de la cuenta de facturación.
      units = tostring(var.budget_amount)
    }
  }

  dynamic "threshold_rules" {
    for_each = var.budget_alert_thresholds
    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "CURRENT_SPEND"
    }
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  # Sin all_updates_rule: el proveedor lo exige con un canal de Monitoring o un tema de
  # Pub/Sub; sin él, los avisos van por correo a los administradores y usuarios de la cuenta
  # de facturación (destinatarios por defecto del presupuesto).
}
