# Etapa 0 (ADR 0029 §2): lo que existe una sola vez en el proyecto único y lo que protege al
# pipeline. Aquí: APIs, agentes de servicio, OS Login, cuenta de Compute por defecto sin Editor,
# llave KMS y bucket del estado y presupuesto. Las nueve cuentas del pipeline y sus permisos
# están en service_accounts.tf; los roles personalizados, en custom_roles.tf; WIF, en wif.tf;
# la etiqueta de protección y la política de denegación, en deny_policy.tf.
#
# La aplica una persona a mano, una vez (runbook 01). El proyecto ya existe: entra como
# project_id y ninguna raíz lo crea ni lo borra.

locals {
  environment = "bootstrap"

  labels = merge(var.labels, {
    env        = local.environment
    managed_by = "terraform"
  })

  project_number = data.google_project.this.number

  # <empresa>-<entorno>-<dominio>-<recurso>[-<sufijo>] (§4.2). El bucket es global: el sufijo
  # opcional lo hace único a nivel mundial.
  state_bucket_name = join("-", compact(["${var.prefix}-${local.environment}-ops-tfstate", var.name_suffix]))

  # El estado debe sobrevivir a la caída de primary_region (runbook de conmutación a DR): bucket
  # multirregional o de doble región, y su llave en la multirregión de KMS homónima.
  state_bucket_dual_region = length(var.state_bucket_dual_regions) == 2
  state_kms_location       = lower(var.state_bucket_location)

  # Todas las APIs del proyecto, una sola vez (ADR 0029 §2 y §4): ninguna otra raíz declara
  # google_project_service. Se agrupan por quién las usa.
  apis = setunion(var.additional_apis, [
    # Base del proyecto, estado, identidad del pipeline y cuota.
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "storage.googleapis.com",
    "cloudkms.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudbilling.googleapis.com",
    # 1-base: auditoría, avisos, secretos, imágenes, contactos, SCC y controles de organización.
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudasset.googleapis.com", # drift.yml y búsqueda de huérfanos (ADR 0029 §8)
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "binaryauthorization.googleapis.com",
    "essentialcontacts.googleapis.com",
    "pubsub.googleapis.com",
    "securitycenter.googleapis.com",
    "orgpolicy.googleapis.com",
    "accesscontextmanager.googleapis.com",
    # 2-networks: VPC, DNS, PSA, prueba de humo (Connectivity Tests) y secreto de la VPN real.
    "compute.googleapis.com",
    "dns.googleapis.com",
    "servicenetworking.googleapis.com",
    "networkmanagement.googleapis.com",
    # 3-workloads.
    "container.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "redis.googleapis.com",
    "file.googleapis.com",
    "backupdr.googleapis.com",
    "gkebackup.googleapis.com",
    "certificatemanager.googleapis.com",
    "cloudscheduler.googleapis.com", # apagado fuera de horario (ADR 0028)
    "cloudtrace.googleapis.com",
    "iap.googleapis.com",     # túneles de IAP para SSH
    "oslogin.googleapis.com", # OS Login fijo en compute-mig
  ])

  # Agentes de servicio que no existen hasta el primer uso del servicio y que 1-base necesita
  # para darles permisos sobre llaves KMS (y Pub/Sub para el tema de SCC). Se crean aquí para que
  # ninguna cuenta del pipeline necesite roles/serviceusage.serviceUsageAdmin.
  # VERIFICAR-EN-APPLY: que generateServiceIdentity acepte cada servicio de la lista y que los
  # agentes de container (container-engine-robot), compute (compute-system) y run
  # (serverless-robot-prod) existan justo después de habilitar sus APIs; si no, agregarlos aquí.
  service_identity_services = toset([
    "artifactregistry.googleapis.com",
    "file.googleapis.com",
    "gkebackup.googleapis.com",
    "pubsub.googleapis.com",
    "redis.googleapis.com",
    "secretmanager.googleapis.com",
    "sqladmin.googleapis.com",
  ])
}

# Número del proyecto: lo usan los correos de los agentes de servicio, los principales de WIF,
# las condiciones de IAM de Secret Manager y el presupuesto.
data "google_project" "this" {
  project_id = var.project_id
}

# --- APIs, agentes de servicio y valores del proyecto ------------------------------------------

resource "google_project_service" "this" {
  for_each = local.apis

  project = var.project_id
  service = each.value

  # Fijo (ADR 0029 §2): apagar una API al destruir rompería a las demás raíces del proyecto.
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service_identity" "this" {
  provider = google-beta
  for_each = local.service_identity_services

  project = var.project_id
  service = each.value

  depends_on = [google_project_service.this]
}

# OS Login en todo el proyecto (CIS 4.4; detector OS_LOGIN_DISABLED). En el diseño de varios
# proyectos lo ponía el módulo project-factory, ya retirado, en cada proyecto con Compute.
# VERIFICAR-EN-APPLY: que el detector OS_LOGIN_DISABLED no marque el proyecto y que IAP + OS
# Login sigan dando SSH a quien tenga roles/compute.osLogin (pendiente 59).
resource "google_compute_project_metadata_item" "os_login" {
  project = var.project_id
  key     = "enable-oslogin"
  value   = "TRUE"

  depends_on = [google_project_service.this]
}

# La cuenta de Compute por defecto recibe roles/editor al habilitar la API (ADR 0029 §4).
# DEPRIVILEGE le quita ese rol sin borrarla. Va aquí y no en 1-base: quitar un rol básico
# necesita resourcemanager.projects.setIamPolicy sin condición, y ninguna cuenta del pipeline lo
# tiene (desviación del ADR 0029 §4, que la ponía en 1-base).
# VERIFICAR-EN-APPLY: que la cuenta de Compute por defecto quede sin roles/editor después del
# apply (gcloud projects get-iam-policy) y que ninguna carga la use.
resource "google_project_default_service_accounts" "this" {
  project = var.project_id
  action  = "DEPRIVILEGE"

  depends_on = [google_project_service.this]
}

# --- Llave KMS del estado (ADR 0008) ------------------------------------------------------------

module "state_kms" {
  source = "../../modules/kms"

  project_id  = var.project_id
  prefix      = var.prefix
  environment = local.environment
  # Misma ubicación que el bucket (multirregión de KMS), no primary_region: una llave regional
  # dejaría el estado ilegible si cae la región.
  location             = local.state_kms_location
  location_short_codes = var.location_short_codes
  keys = {
    state = {}
  }
  labels = merge(local.labels, { app = "tfstate" })

  depends_on = [google_project_service.this]
}

# Leerla crea el agente de Cloud Storage del proyecto si todavía no existe.
data "google_storage_project_service_account" "this" {
  project = var.project_id
}

resource "google_kms_crypto_key_iam_member" "state_storage_agent" {
  crypto_key_id = module.state_kms.key_ids["state"]
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.this.email_address}"
}

# --- Bucket de estado (§6.1, ADR 0010 y 0022) ---------------------------------------------------

resource "google_storage_bucket" "state" {
  # checkov:skip=CKV_GCP_62: el registro de uso heredado de Cloud Storage necesitaría otro bucket que a su vez no tendría registro; el acceso al estado queda en los registros de acceso a datos de Cloud Storage de la configuración de auditoría del proyecto (1-base, ADR 0029 §7) y en el sink de proyecto
  project       = var.project_id
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
    # Borrar el bucket borra el estado de todas las raíces.
    prevent_destroy = true

    precondition {
      condition     = !local.state_bucket_dual_region || toset(var.state_bucket_dual_regions) == toset([var.primary_region, var.dr_region])
      error_message = "state_bucket_dual_regions debe ser primary_region y dr_region: el estado debe seguir disponible en la región de DR."
    }
  }

  # VERIFICAR-EN-APPLY: que las dos regiones de state_bucket_dual_regions formen una doble
  # región configurable válida dentro de state_bucket_location (la API lo valida al crear).

  # VERIFICAR-EN-APPLY: que el agente de Cloud Storage ya tenga el permiso sobre la llave al
  # crear el bucket (la propagación de IAM puede tardar unos segundos; si falla, repetir el apply).
  depends_on = [google_kms_crypto_key_iam_member.state_storage_agent]
}

# --- Presupuesto del proyecto (ADR 0029 §2) -----------------------------------------------------

# Filtrado al proyecto único. Lo aplica la persona de la etapa 0: necesita
# roles/billing.costsManager en la cuenta de facturación (ninguna cuenta del pipeline lo tiene).
# VERIFICAR-EN-APPLY: que el filtro projects/<número> limite el presupuesto al proyecto y que
# lleguen los correos a los administradores de la cuenta de facturación.
resource "google_billing_budget" "project" {
  billing_account = var.billing_account
  display_name    = "${var.prefix}-${local.environment}-ops-budget"

  budget_filter {
    projects               = ["projects/${local.project_number}"]
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

  # Sin all_updates_rule: los avisos van por correo a los administradores y usuarios de la
  # cuenta de facturación (destinatarios por defecto del presupuesto).

  depends_on = [google_project_service.this]
}
