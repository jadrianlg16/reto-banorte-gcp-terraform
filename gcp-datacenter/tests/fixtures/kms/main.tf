# Fixture de integración del módulo kms: llavero regional con dos llaves, una con un
# miembro encrypter_decrypter (cuenta de servicio de la prueba).
# Las llaves del módulo llevan prevent_destroy: la prueba las saca del estado antes del
# destroy y programa la destrucción de sus versiones con gcloud.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {}

variable "project_id" {
  description = "Proyecto de la prueba."
  type        = string
}

variable "prefix" {
  description = "Prefijo único de la ejecución."
  type        = string
}

variable "region" {
  description = "Región del llavero."
  type        = string
}

variable "labels" {
  description = "Etiquetas obligatorias de la prueba."
  type        = map(string)
}

resource "google_service_account" "user" {
  project      = var.project_id
  account_id   = "${var.prefix}-kms-user"
  display_name = "Terratest: usuario de la llave"
}

module "kms" {
  source = "../../../modules/kms"

  project_id  = var.project_id
  prefix      = var.prefix
  environment = "dev"
  location    = var.region

  keys = {
    sql = {}
    storage = {
      encrypter_decrypters = ["serviceAccount:${var.prefix}-kms-user@${var.project_id}.iam.gserviceaccount.com"]
    }
  }

  labels = var.labels

  depends_on = [google_service_account.user]
}

output "key_ids" {
  description = "IDs de las llaves por uso."
  value       = module.kms.key_ids
}

output "keyring_id" {
  description = "ID del llavero."
  value       = module.kms.keyring_id
}

output "user_member" {
  description = "Miembro que debe tener cryptoKeyEncrypterDecrypter sobre la llave storage."
  value       = "serviceAccount:${google_service_account.user.email}"
}
