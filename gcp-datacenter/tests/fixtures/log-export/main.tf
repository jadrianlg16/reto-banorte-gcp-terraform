# Fixture de integración del módulo log-export: bucket de logs con CMEK y retención de 30
# días SIN bloqueo (un bloqueo es irreversible y dejaría el bucket imborrable), y un sink de
# proyecto (ADR 0029 §7) con la exclusión del propio bucket, cuyo filtro no coincide con ningún
# registro, para que el bucket quede vacío y el destroy funcione pese a la retención.

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
  # Como en 1-base: el sink no reexporta el acceso a datos de su propio bucket. El nombre es el
  # que arma el módulo (<prefix>-<environment>-ops-<name>); la salida bucket_name no se puede
  # usar aquí porque sería un ciclo.
  exclusions = [{
    name        = "bucket-de-logs"
    description = "Registros de acceso a datos del propio bucket de logs."
    filter      = "logName:\"cloudaudit.googleapis.com%2Fdata_access\" AND resource.type=\"gcs_bucket\" AND resource.labels.bucket_name=\"${var.prefix}-dev-ops-audit-logs\""
  }]
  labels = var.labels
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

output "exclusion_filter" {
  description = "Filtro que debe tener la exclusión bucket-de-logs del sink."
  value       = "logName:\"cloudaudit.googleapis.com%2Fdata_access\" AND resource.type=\"gcs_bucket\" AND resource.labels.bucket_name=\"${module.log_export.bucket_name}\""
}

output "kms_key_id" {
  description = "Llave con la que debe quedar cifrado el bucket."
  value       = module.cmek.key_id
}
