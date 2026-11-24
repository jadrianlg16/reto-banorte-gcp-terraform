# Etapa 1-base (ADR 0029 §4 y §7): lo que existe una sola vez en el proyecto único y no es de la
# etapa 0. Aquí: auditoría del proyecto, sink y bucket de logs con su llave, alertas de
# auditoría, contactos esenciales y la notificación opcional de SCC. Las llaves y los secretos
# de cada entorno están en kms.tf; imágenes y Binary Authorization, en artifacts.tf; el IAM de
# personas y de agentes, en iam.tf; los controles que solo existen con organización, en org.tf.

locals {
  environment = "common"

  labels = merge(var.labels, {
    env        = local.environment
    managed_by = "terraform"
  })

  labels_by_env = {
    for e in var.environments : e => merge(var.labels, {
      env        = e
      managed_by = "terraform"
    })
  }

  # Agentes de servicio del proyecto: correos de formato fijo a partir del número del proyecto
  # (lo publica 0-bootstrap, así que se conocen en el plan). 0-bootstrap crea los que no existen
  # hasta el primer uso (google_project_service_identity).
  service_agents = {
    artifactregistry = "serviceAccount:service-${local.project_number}@gcp-sa-artifactregistry.iam.gserviceaccount.com"
    compute          = "serviceAccount:service-${local.project_number}@compute-system.iam.gserviceaccount.com"
    filestore        = "serviceAccount:service-${local.project_number}@cloud-filer.iam.gserviceaccount.com"
    gke              = "serviceAccount:service-${local.project_number}@container-engine-robot.iam.gserviceaccount.com"
    gkebackup        = "serviceAccount:service-${local.project_number}@gcp-sa-gkebackup.iam.gserviceaccount.com"
    pubsub           = "serviceAccount:service-${local.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
    redis            = "serviceAccount:service-${local.project_number}@cloud-redis.iam.gserviceaccount.com"
    run              = "serviceAccount:service-${local.project_number}@serverless-robot-prod.iam.gserviceaccount.com"
    secretmanager    = "serviceAccount:service-${local.project_number}@gcp-sa-secretmanager.iam.gserviceaccount.com"
    sql              = "serviceAccount:service-${local.project_number}@gcp-sa-cloud-sql.iam.gserviceaccount.com"
    storage          = "serviceAccount:service-${local.project_number}@gs-project-accounts.iam.gserviceaccount.com"
  }

  # Bucket de logs: mismo nombre que arma log-export (se necesita aquí para su exclusión).
  log_bucket_name = join("-", compact(["${var.prefix}-${local.environment}-ops-audit-logs", var.name_suffix]))

  # Servicios con registros de acceso a datos (ADR 0029 §7). Valen para los tres entornos.
  data_access_services = toset([
    "cloudkms.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
  ])
}

# --- Configuración de auditoría del proyecto (ADR 0029 §7, única por proyecto) ----------------

# ADMIN_READ para todos los servicios. La cuenta de 1-base la cambia con projectIamAdmin
# condicionado (0-bootstrap): una llamada que no cambia bindings pasa la condición.
# VERIFICAR-EN-APPLY: que tf-base pueda escribir la configuración de auditoría con la condición
# modifiedGrantsByRole (pendiente nuevo) y que los registros de acceso a datos aparezcan.
resource "google_project_iam_audit_config" "all_services" {
  project = local.project_id
  service = "allServices"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  lifecycle {
    # Un project_id distinto del de 0-bootstrap mezclaría el estado con otro proyecto.
    precondition {
      condition     = var.project_id == local.bootstrap.project_id
      error_message = "project_id no coincide con la salida project_id de 0-bootstrap."
    }
  }
}

resource "google_project_iam_audit_config" "data_access" {
  for_each = local.data_access_services

  project = local.project_id
  service = each.value

  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# --- Llaves comunes (ADR 0018) ------------------------------------------------------------------
# logs: CMEK del bucket de logs. pubsub: CMEK del tema de hallazgos de SCC.

module "common_kms" {
  source = "../../modules/kms"

  project_id           = local.project_id
  prefix               = var.prefix
  environment          = local.environment
  location             = var.primary_region
  location_short_codes = var.location_short_codes
  keys = {
    logs = {}
    pubsub = {
      encrypter_decrypters = [local.service_agents["pubsub"]]
    }
  }
  rotation_period = var.key_rotation_period
  labels          = merge(local.labels, { app = "logging" })
}

# --- Bucket de logs y sink de proyecto (ADR 0029 §7) -----------------------------------------------

module "audit_logs" {
  source = "../../modules/log-export"

  project_id       = local.project_id
  prefix           = var.prefix
  environment      = local.environment
  name             = "audit-logs"
  name_suffix      = var.name_suffix
  location         = var.primary_region
  kms_key          = module.common_kms.key_ids["logs"]
  retention_days   = var.log_retention_days
  retention_locked = var.log_retention_locked
  parent           = "projects/${local.project_id}"

  # Con DATA_WRITE de Cloud Storage activo, cada escritura del sink en el bucket genera una
  # entrada de acceso a datos que el sink volvería a exportar.
  exclusions = [{
    name        = "bucket-de-logs"
    description = "Registros de acceso a datos del propio bucket de logs."
    filter      = "logName:\"cloudaudit.googleapis.com%2Fdata_access\" AND resource.type=\"gcs_bucket\" AND resource.labels.bucket_name=\"${local.log_bucket_name}\""
  }]

  labels = merge(local.labels, { app = "logging" })
}

# --- Alertas de auditoría (CIS 2.5 a 2.12), una sola vez en el proyecto ------------------------

module "audit_alerts" {
  source = "../../modules/audit-alerts"

  project_id         = local.project_id
  prefix             = var.prefix
  environment        = local.environment
  notification_email = var.security_alert_email
  labels             = merge(local.labels, { app = "audit" })
}

# Canal de operaciones opcional (hallazgo H8 de R1): las alertas de los entornos (3-workloads)
# van aquí y no al canal de seguridad, que queda solo para las alertas de auditoría. Sin
# operations_alert_email no se crea y cada entorno avisa solo a sus notification_emails.
# VERIFICAR-EN-APPLY: que la lista acepte correo de Cloud Monitoring (como el de audit-alerts).
resource "google_monitoring_notification_channel" "operations" {
  for_each = var.operations_alert_email == null ? toset([]) : toset(["this"])

  project      = local.project_id
  display_name = "${var.prefix}-${local.environment}-ops-operations"
  description  = "Operaciones: alertas de disponibilidad, SLO y recursos de los entornos (3-workloads)."
  type         = "email"
  labels = {
    email_address = lower(var.operations_alert_email)
  }
  user_labels = merge(local.labels, { app = "operations" })
}

# --- Contactos esenciales del proyecto (CIS 1.17) --------------------------------------------------
# VERIFICAR-EN-APPLY: que la API acepte los contactos en el proyecto y el idioma
# essential_contacts_language (pendiente 57).

resource "google_essential_contacts_contact" "this" {
  for_each = var.essential_contacts

  parent                              = "projects/${local.project_id}"
  email                               = each.key
  language_tag                        = var.essential_contacts_language
  notification_category_subscriptions = sort(distinct(each.value))
}

# --- Security Command Center (opcional, ADR 0029 §7) -----------------------------------------------
# SCC se activa a mano en el proyecto (Standard o Premium); el proveedor no tiene recurso para
# activarlo. Que funcione en un proyecto sin organización es HYPOTHESIS.

resource "google_pubsub_topic" "scc_findings" {
  for_each = var.enable_scc_notification ? toset(["this"]) : toset([])

  project                    = local.project_id
  name                       = "${var.prefix}-${local.environment}-ops-scc-findings"
  kms_key_name               = module.common_kms.key_ids["pubsub"]
  message_retention_duration = "604800s"
  labels                     = merge(local.labels, { app = "scc" })

  # La llave pubsub es regional (primary_region): el almacenamiento de mensajes se limita a esa
  # región y se impone en tránsito, como pide la guía de CMEK de Pub/Sub para llaves regionales.
  # VERIFICAR-EN-APPLY: que SCC siga publicando en el tema con enforce_in_transit = true.
  message_storage_policy {
    allowed_persistence_regions = [var.primary_region]
    enforce_in_transit          = true
  }

  depends_on = [module.common_kms]
}

# VERIFICAR-EN-APPLY: que la notificación de proyecto se cree con roles/securitycenter.
# notificationConfigEditor en el proyecto y que la cuenta de servicio de SCC pueda publicar en
# el tema (la API da el permiso si quien la crea puede cambiar el IAM del tema).
resource "google_scc_v2_project_notification_config" "findings" {
  for_each = google_pubsub_topic.scc_findings

  project      = local.project_id
  location     = "global"
  config_id    = "${var.prefix}-${local.environment}-ops-scc-findings"
  description  = "Hallazgos activos de severidad alta o crítica hacia Pub/Sub."
  pubsub_topic = each.value.id

  streaming_config {
    filter = var.scc_notification_filter
  }
}
