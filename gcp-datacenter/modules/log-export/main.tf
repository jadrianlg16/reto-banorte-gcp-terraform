locals {
  base_name   = "${var.prefix}-${var.environment}-ops-${var.name}"
  bucket_name = join("-", compact([local.base_name, var.name_suffix]))
  sink_name   = "${local.base_name}-sink"

  # Diseño de un solo proyecto (ADR 0029 §7): solo hay sink de proyecto. Sin parent solo se
  # crea el bucket.
  sinks = var.parent == null ? toset([]) : toset(["this"])

  destination = "storage.googleapis.com/${google_storage_bucket.this.name}"

  writer_identity = one([for s in google_logging_project_sink.this : s.writer_identity])
}

# --- CMEK ---------------------------------------------------------------------------------

# Con project_number (proyecto creado en el mismo plan) la lectura se pospone al apply.
# VERIFICAR-EN-APPLY: que el API de Cloud Storage acepte el número de proyecto.
data "google_storage_project_service_account" "this" {
  project = coalesce(var.project_number, var.project_id)
}

resource "google_kms_crypto_key_iam_member" "storage_agent" {
  for_each = var.grant_kms_to_storage_agent ? toset(["this"]) : toset([])

  crypto_key_id = var.kms_key
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.this.email_address}"
}

# --- Bucket de logs -------------------------------------------------------------------------

resource "google_storage_bucket" "this" {
  project       = var.project_id
  name          = local.bucket_name
  location      = var.location
  storage_class = var.storage_class
  labels        = var.labels

  # Valores fijos: acceso uniforme, sin acceso público, versionado y sin borrado forzado.
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = var.kms_key
  }

  # La retención siempre existe; solo su bloqueo depende de la variable (es irreversible).
  # VERIFICAR-EN-APPLY: que el bloqueo (is_locked = true) se aplique sobre un bucket ya creado
  # y que un plan posterior no intente desbloquearlo.
  retention_policy {
    retention_period = var.retention_days * 86400
    is_locked        = var.retention_locked
  }

  # Las versiones no actuales se borran cuando vence la retención (antes no se puede).
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      days_since_noncurrent_time = var.retention_days
      with_state                 = "ARCHIVED"
    }
  }

  dynamic "logging" {
    for_each = var.access_logs_bucket == null ? [] : [var.access_logs_bucket]
    content {
      log_bucket = logging.value
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.bucket_name) <= 63
      error_message = "El nombre del bucket <prefix>-<environment>-ops-<name>[-<name_suffix>] no puede pasar de 63 caracteres."
    }
  }

  # VERIFICAR-EN-APPLY: que el agente de Cloud Storage ya tenga permiso sobre la llave al crear
  # el bucket (la propagación de IAM puede tardar unos segundos).
  depends_on = [google_kms_crypto_key_iam_member.storage_agent]
}

# --- Sink -----------------------------------------------------------------------------------

# Sink de proyecto con identidad de escritura propia. Las exclusiones descartan entradas antes
# de exportarlas (por ejemplo, los registros de acceso a datos del propio bucket de logs, que
# de otro modo vuelven al bucket en cada escritura del sink).
# VERIFICAR-EN-APPLY: que las exclusiones del sink descarten las entradas indicadas y que la
# identidad del sink escriba en el bucket con CMEK.
resource "google_logging_project_sink" "this" {
  for_each = local.sinks

  name                   = local.sink_name
  project                = trimprefix(var.parent, "projects/")
  destination            = local.destination
  filter                 = var.filter
  unique_writer_identity = true

  dynamic "exclusions" {
    for_each = var.exclusions
    content {
      name        = exclusions.value.name
      filter      = exclusions.value.filter
      description = exclusions.value.description
      disabled    = exclusions.value.disabled
    }
  }
}

# La identidad del sink solo puede crear objetos: no lee ni borra.
resource "google_storage_bucket_iam_member" "writer" {
  for_each = local.sinks

  bucket = google_storage_bucket.this.name
  role   = "roles/storage.objectCreator"
  member = local.writer_identity
}
