# Fixture de integración del módulo secrets: dos contenedores sin valores, replicados en la
# región de la prueba con CMEK, y una cuenta de servicio con acceso de lectura.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google      = { source = "hashicorp/google", version = "~> 6.0" }
    google-beta = { source = "hashicorp/google-beta", version = "~> 6.0" }
  }
}

provider "google" {}
provider "google-beta" {}

variable "project_id" {
  description = "Proyecto de la prueba."
  type        = string
}

variable "project_number" {
  description = "Número del proyecto (correo del agente de Secret Manager)."
  type        = string
}

variable "prefix" {
  description = "Prefijo único de la ejecución."
  type        = string
}

variable "region" {
  description = "Región de la réplica y de la llave."
  type        = string
}

variable "labels" {
  description = "Etiquetas obligatorias de la prueba."
  type        = map(string)
}

module "cmek" {
  source = "../support/cmek"

  project_id        = var.project_id
  location          = var.region
  name              = "${var.prefix}-secrets"
  identity_services = ["secretmanager.googleapis.com"]
  members           = ["serviceAccount:service-${var.project_number}@gcp-sa-secretmanager.iam.gserviceaccount.com"]
}

resource "google_service_account" "reader" {
  project      = var.project_id
  account_id   = "${var.prefix}-sec-reader"
  display_name = "Terratest: lector de secretos"
}

module "secrets" {
  source = "../../../modules/secrets"

  project_id  = var.project_id
  prefix      = var.prefix
  environment = "dev"
  names       = ["api-token", "partner-cert"]
  kms_keys    = { (var.region) = module.cmek.key_id }
  accessors   = ["serviceAccount:${var.prefix}-sec-reader@${var.project_id}.iam.gserviceaccount.com"]
  labels      = var.labels

  # Solo para la prueba: permite el destroy.
  deletion_protection = false

  depends_on = [google_service_account.reader]
}

output "secret_ids" {
  description = "IDs de los secretos por nombre."
  value       = module.secrets.secret_ids
}

output "kms_key_id" {
  description = "Llave con la que debe quedar cifrada la réplica."
  value       = module.cmek.key_id
}

output "reader_member" {
  description = "Miembro que debe tener roles/secretmanager.secretAccessor."
  value       = "serviceAccount:${google_service_account.reader.email}"
}
