# Llave CMEK de apoyo para los fixtures: llavero, llave con rotación de 90 días y permiso de
# cifrado para los agentes de servicio que la usan. A diferencia del módulo kms, no lleva
# prevent_destroy: al destruir el fixture se programan para destrucción sus versiones (la llave
# y el llavero no se pueden borrar en GCP; desaparecen con el proyecto efímero).

terraform {
  required_version = ">= 1.9"
  required_providers {
    google      = { source = "hashicorp/google", version = "~> 6.0" }
    google-beta = { source = "hashicorp/google-beta", version = "~> 6.0" }
  }
}

variable "project_id" {
  description = "Proyecto de la prueba."
  type        = string
}

variable "location" {
  description = "Ubicación del llavero (región o multirregión)."
  type        = string
}

variable "name" {
  description = "Nombre único del llavero y de la llave."
  type        = string
}

variable "identity_services" {
  description = "Servicios cuyo agente se crea con generateServiceIdentity antes de darle permiso (por ejemplo sqladmin.googleapis.com)."
  type        = set(string)
  default     = []
}

variable "members" {
  description = "Miembros (serviceAccount:…) que reciben roles/cloudkms.cryptoKeyEncrypterDecrypter. Deben ser conocidos en el plan (armados con el número del proyecto)."
  type        = set(string)
  default     = []
}

variable "grant_storage_agent" {
  description = "Si es true, también recibe permiso el agente de Cloud Storage del proyecto."
  type        = bool
  default     = false
}

# VERIFICAR-EN-APPLY: que generateServiceIdentity acepte cada servicio de identity_services
# (mismo criterio que stages/4-projects/envs/<env>/service_agents.tf).
resource "google_project_service_identity" "this" {
  provider = google-beta
  for_each = var.identity_services

  project = var.project_id
  service = each.value
}

resource "google_kms_key_ring" "this" {
  project  = var.project_id
  name     = var.name
  location = var.location
}

resource "google_kms_crypto_key" "this" {
  name            = var.name
  key_ring        = google_kms_key_ring.this.id
  rotation_period = "7776000s"
  purpose         = "ENCRYPT_DECRYPT"

  # Destrucción programada mínima (1 día) para no dejar material de llave de pruebas.
  destroy_scheduled_duration = "86400s"
}

data "google_storage_project_service_account" "this" {
  count   = var.grant_storage_agent ? 1 : 0
  project = var.project_id
}

resource "google_kms_crypto_key_iam_member" "members" {
  for_each = var.members

  crypto_key_id = google_kms_crypto_key.this.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = each.value

  depends_on = [google_project_service_identity.this]
}

resource "google_kms_crypto_key_iam_member" "storage_agent" {
  count = var.grant_storage_agent ? 1 : 0

  crypto_key_id = google_kms_crypto_key.this.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.this[0].email_address}"
}

output "key_id" {
  description = "ID completo de la llave (projects/…/cryptoKeys/…). Disponible solo después de los permisos."
  value       = google_kms_crypto_key.this.id

  depends_on = [
    google_kms_crypto_key_iam_member.members,
    google_kms_crypto_key_iam_member.storage_agent,
  ]
}
