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

  # El estado debe sobrevivir a la caída de primary_region: el runbook de conmutación a DR
  # corre terraform (init, bloqueo, terraform_remote_state) durante el incidente. Bucket
  # multirregional o de doble región, y su llave en la ubicación de KMS que exige la CMEK de
  # Cloud Storage: la multirregión homónima (us para US y para una doble región configurable
  # dentro de US).
  state_bucket_dual_region = length(var.state_bucket_dual_regions) == 2
  state_kms_location       = lower(var.state_bucket_location)

  # APIs del proyecto semilla. Además de las que usa esta etapa, las etapas 1 a 5 lo usan como
  # proyecto de cuota (billing_project con user_project_override) para las APIs de nivel
  # organización y facturación: por eso están aquí aunque sus recursos vivan en otros proyectos.
  # essentialcontacts: contactos de la organización (etapa 1, CIS 1.17). Cloud Asset, Logging y
  # Monitoring los agrega project-factory. Cloud Asset sirve además a drift.yml: su cuenta de
  # auditoría vive aquí (pipeline.md §2) y una cuenta de servicio cobra a su proyecto la cuota.
  # VERIFICAR-EN-APPLY: gcloud asset search-all-resources de drift.yml (pendiente 60).
  seed_apis = [
    "accesscontextmanager.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudbilling.googleapis.com",
    "cloudkms.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "essentialcontacts.googleapis.com",
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

  project_id  = module.seed_project.project_id
  prefix      = var.prefix
  environment = local.environment
  # Misma ubicación que el bucket (multirregión de KMS), no primary_region: una llave regional
  # dejaría el estado ilegible si cae la región.
  location             = local.state_kms_location
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
  location      = var.state_bucket_location
  storage_class = "STANDARD"
  labels        = merge(local.labels, { app = "tfstate" })

  # Doble región configurable (opcional): las dos regiones dentro de la multirregión, con
  # replicación turbo. Sin ella, el bucket es multirregional.
  dynamic "custom_placement_config" {
    for_each = local.state_bucket_dual_region ? [var.state_bucket_dual_regions] : []
    content {
      data_locations = [for r in custom_placement_config.value : upper(r)]
    }
  }
  rpo = local.state_bucket_dual_region ? "ASYNC_TURBO" : null

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

    precondition {
      condition     = !local.state_bucket_dual_region || contains(var.state_bucket_dual_regions, var.primary_region)
      error_message = "state_bucket_dual_regions debe incluir primary_region (y la región de DR)."
    }
  }

  # VERIFICAR-EN-APPLY: que las dos regiones de state_bucket_dual_regions formen una doble
  # región configurable válida dentro de state_bucket_location (la API lo valida al crear).

  # VERIFICAR-EN-APPLY: que el agente de Cloud Storage ya tenga el permiso sobre la llave al
  # crear el bucket (la propagación de IAM puede tardar unos segundos; si falla, repetir el apply).
  depends_on = [google_kms_crypto_key_iam_member.state_storage_agent]
}
