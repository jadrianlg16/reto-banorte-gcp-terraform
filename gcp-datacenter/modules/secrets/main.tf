# Contenedores de Secret Manager con CMEK y replicación administrada por el usuario.
# No hay google_secret_manager_secret_version en este módulo, a propósito (ADR 0015).

locals {
  accessor_bindings = merge([
    for name in var.names : {
      for member in var.accessors : "${name}|${member}" => {
        name   = name
        member = member
      }
    }
  ]...)
}

resource "google_secret_manager_secret" "this" {
  for_each = var.names

  project   = var.project_id
  secret_id = "${var.prefix}-${var.environment}-sec-${each.key}"

  # VERIFICAR-EN-APPLY: el agente de servicio de Secret Manager del proyecto
  # (service-<número>@gcp-sa-secretmanager.iam.gserviceaccount.com) necesita
  # roles/cloudkms.cryptoKeyEncrypterDecrypter sobre cada llave de kms_keys antes de crear
  # los secretos; lo da la etapa que llama al módulo.
  replication {
    user_managed {
      dynamic "replicas" {
        for_each = var.kms_keys
        content {
          location = replicas.key
          customer_managed_encryption {
            kms_key_name = replicas.value
          }
        }
      }
    }
  }

  labels              = merge(var.labels, { secret = each.key })
  deletion_protection = var.deletion_protection
}

resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = local.accessor_bindings

  project   = var.project_id
  secret_id = google_secret_manager_secret.this[each.value.name].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}
