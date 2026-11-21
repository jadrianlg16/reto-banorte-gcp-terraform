# Fixture de integración del módulo log-export: bucket de logs con CMEK y retención de 30
# días SIN bloqueo (un bloqueo es irreversible y dejaría el bucket imborrable), y un sink de
# proyecto cuyo filtro no coincide con ningún registro, para que el bucket quede vacío y el
# destroy funcione pese a la retención.

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

variable "prefix" {
  description = "Prefijo único de la ejecución."
  type        = string
}

variable "region" {
  description = "Región del bucket y de la llave."
  type        = string
}

variable "labels" {
  description = "Etiquetas obligatorias de la prueba."
  type        = map(string)
}

# El módulo da el permiso al agente de Cloud Storage (grant_kms_to_storage_agent = true).
module "cmek" {
  source = "../support/cmek"

  project_id = var.project_id
  location   = var.region
  name       = "${var.prefix}-logs"
}

module "log_export" {
  source = "../../../modules/log-export"

  project_id       = var.project_id
  prefix           = var.prefix
  environment      = "dev"
  location         = var.region
  kms_key          = module.cmek.key_id
  retention_days   = 30
  retention_locked = false
  parent           = "projects/${var.project_id}"
  filter           = "logName=\"projects/${var.project_id}/logs/terratest-sin-registros\""
  labels           = var.labels
}

output "bucket_name" {
  description = "Bucket de logs."
  value       = module.log_export.bucket_name
}

output "sink_name" {
  description = "Sink del proyecto."
  value       = module.log_export.sink_name
}

output "writer_identity" {
  description = "Identidad del sink."
  value       = module.log_export.writer_identity
}

output "destination" {
  description = "Destino del sink."
  value       = module.log_export.destination
}

output "kms_key_id" {
  description = "Llave con la que debe quedar cifrado el bucket."
  value       = module.cmek.key_id
}
