# Etapa 0 (§7.0): carpeta bootstrap, proyecto semilla, llave KMS y bucket del estado.
# Las cuentas de servicio de las etapas y sus permisos están en service_accounts.tf; la
# federación de identidades de GitHub, en wif.tf.

locals {
  environment = "bootstrap"

  labels = merge(var.labels, {
    env        = local.environment
    managed_by = "terraform"
  })

  # <empresa>-<entorno>-<dominio>-<recurso>[-<sufijo>] (§4.2). El bucket es global: lleva el
  # mismo sufijo que el proyecto para ser único a nivel mundial.
  state_bucket_name = join("-", compact(["${var.prefix}-${local.environment}-ops-tfstate", var.project_suffix]))

  # APIs del proyecto semilla. Además de las que usa esta etapa, las etapas 1 a 5 lo usan como
  # proyecto de cuota (billing_project con user_project_override) para las APIs de nivel
  # organización y facturación: por eso están aquí aunque sus recursos vivan en otros proyectos.
  seed_apis = [
    "accesscontextmanager.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudbilling.googleapis.com",
    "cloudkms.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "orgpolicy.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
    "securitycenter.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
  ]
}

# --- Carpeta y proyecto semilla -----------------------------------------------------------

module "bootstrap_folder" {
  source = "../../modules/folders"

  parent = "organizations/${var.org_id}"
  names  = [local.environment]
}

module "seed_project" {
  source = "../../modules/project-factory"

  prefix          = var.prefix
  environment     = local.environment
  name            = "seed"
  project_suffix  = var.project_suffix
  folder_id       = module.bootstrap_folder.ids[local.environment]
  billing_account = var.billing_account
  apis            = local.seed_apis
  labels          = merge(local.labels, { app = "seed" })
}

# Registros de acceso a datos de todos los servicios del proyecto semilla: quién lee o
# escribe el estado (y el resto de la actividad del proyecto) queda auditado. Reemplaza al
# registro de uso heredado del bucket (ver la omisión de CKV_GCP_62 abajo).
resource "google_project_iam_audit_config" "seed" {
  project = module.seed_project.project_id
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

# --- Llave KMS del estado (ADR 0008) ------------------------------------------------------

module "state_kms" {
  source = "../../modules/kms"

  project_id           = module.seed_project.project_id
  prefix               = var.prefix
  environment          = local.environment
  location             = var.primary_region
  location_short_codes = var.location_short_codes
  # La rotación de 90 días es el valor por defecto del módulo (7776000s).
  keys = {
    state = {}
  }
  labels = merge(local.labels, { app = "tfstate" })
}

# El permiso del agente de Cloud Storage se asigna aquí y no con encrypter_decrypters del
# módulo kms: ese mapa usa el miembro como llave del for_each, y el correo del agente depende
# del número del proyecto semilla, que no se conoce en el plan de la primera ejecución.
#
# Se consulta con el NÚMERO del proyecto y no con su ID: el ID se conoce en el plan y Terraform
# leería la fuente de datos durante el plan del primer apply, cuando el proyecto todavía no
# existe (falla). El número solo se conoce al crearlo, así que la lectura se pospone al apply,
# después de habilitar las APIs (la salida project_number depende de ellas).
# VERIFICAR-EN-APPLY: que el API de Cloud Storage acepte el número de proyecto en
# projects/<proyecto>/serviceAccount.
data "google_storage_project_service_account" "seed" {
  project = module.seed_project.project_number
}

resource "google_kms_crypto_key_iam_member" "state_storage_agent" {
  crypto_key_id = module.state_kms.key_ids["state"]
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.seed.email_address}"
}

# --- Bucket de estado (§6.1) --------------------------------------------------------------

resource "google_storage_bucket" "state" {
  # checkov:skip=CKV_GCP_62: el registro de uso heredado de Cloud Storage necesitaría otro bucket que a su vez no tendría registro; el acceso al estado queda en los registros de auditoría de acceso a datos del proyecto semilla (google_project_iam_audit_config.seed) y en el sink agregado de la etapa 1
  project       = module.seed_project.project_id
  name          = local.state_bucket_name
  location      = upper(var.primary_region)
  storage_class = "STANDARD"
  labels        = merge(local.labels, { app = "tfstate" })

  # Valores fijos (§6.1): acceso uniforme, sin acceso público, versionado, sin borrado forzado.
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = module.state_kms.key_ids["state"]
  }

  # Solo se borran versiones viejas (no actuales) del estado; la versión vigente nunca.
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      num_newer_versions = var.state_versions_to_keep
      with_state         = "ARCHIVED"
    }
  }

  lifecycle_rule {
    action {
      type = "AbortIncompleteMultipartUpload"
    }
    condition {
      age = 1
    }
  }

  lifecycle {
    # Borrar el bucket borra el estado de todas las etapas.
    prevent_destroy = true
  }

  # VERIFICAR-EN-APPLY: que el agente de Cloud Storage ya tenga el permiso sobre la llave al
  # crear el bucket (la propagación de IAM puede tardar unos segundos; si falla, repetir el apply).
  depends_on = [google_kms_crypto_key_iam_member.state_storage_agent]
}
