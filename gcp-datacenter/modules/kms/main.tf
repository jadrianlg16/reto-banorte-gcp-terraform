# Llavero y llaves simétricas de KMS. Las llaves rotan siempre (máximo 90 días) y no se
# pueden destruir desde Terraform (prevent_destroy).

locals {
  location_short = var.location_short_codes[var.location]
  keyring_name   = "${var.prefix}-${var.environment}-sec-keyring-${local.location_short}"

  # Una asignación por llave y miembro, con llave estable "uso|miembro".
  key_members = merge([
    for use, key in var.keys : {
      for member in key.encrypter_decrypters : "${use}|${member}" => {
        use    = use
        member = member
      }
    }
  ]...)
}

# Los llaveros no admiten etiquetas ni se pueden borrar en GCP.
resource "google_kms_key_ring" "this" {
  project  = var.project_id
  name     = local.keyring_name
  location = var.location
}

resource "google_kms_crypto_key" "this" {
  for_each = var.keys

  name     = "${var.prefix}-${var.environment}-sec-${each.key}"
  key_ring = google_kms_key_ring.this.id

  # Fijo: solo llaves simétricas, que son las que admiten rotación automática.
  purpose                    = "ENCRYPT_DECRYPT"
  rotation_period            = var.rotation_period
  destroy_scheduled_duration = each.value.destroy_scheduled_duration

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = each.value.protection_level
  }

  labels = merge(var.labels, { key_use = each.key })

  lifecycle {
    # Destruir una llave deja ilegibles los datos cifrados con ella. Para retirarla hay que
    # quitar este bloque a propósito en un PR revisado por seguridad.
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key_iam_member" "encrypter_decrypter" {
  for_each = local.key_members

  crypto_key_id = google_kms_crypto_key.this[each.value.use].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = each.value.member
}
