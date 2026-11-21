# Fixture de integración del módulo org (alcance de organización: TEST_ALLOW_ORG=true).
# Para no afectar a la organización real, las nueve políticas se aplican en una carpeta
# contenedora vacía creada por la prueba (policy_parent) y el sink agregado de la organización
# usa un filtro que no coincide con ningún registro. El sink sí es de organización: el módulo
# no admite otro tipo.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {}

variable "org_id" {
  description = "Número de la organización."
  type        = string
}

variable "parent" {
  description = "Donde se crea la carpeta contenedora: folders/<n> u organizations/<n>."
  type        = string
}

variable "project_id" {
  description = "Proyecto de la prueba (aloja el bucket destino del sink)."
  type        = string
}

variable "prefix" {
  description = "Prefijo único de la ejecución."
  type        = string
}

variable "region" {
  description = "Región del bucket destino y región permitida."
  type        = string
}

variable "dr_region" {
  description = "Segunda región permitida."
  type        = string
}

variable "directory_customer_id" {
  description = "Cliente de Cloud Identity (Cxxxxxxxx) para iam.allowedPolicyMemberDomains."
  type        = string
}

variable "labels" {
  description = "Etiquetas obligatorias de la prueba."
  type        = map(string)
}

resource "google_folder" "container" {
  display_name        = "terratest-${var.prefix}-org"
  parent              = var.parent
  deletion_protection = false
}

resource "google_storage_bucket" "sink" {
  project                     = var.project_id
  name                        = "${var.project_id}-${var.prefix}-sink"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true
  labels                      = var.labels
}

module "org" {
  source = "../../../modules/org"

  org_id                       = var.org_id
  prefix                       = var.prefix
  policy_parent                = google_folder.container.name
  allowed_regions              = [var.region, var.dr_region]
  additional_allowed_locations = ["us"]
  directory_customer_id        = var.directory_customer_id
  log_sink_destination         = "storage.googleapis.com/${google_storage_bucket.sink.name}"
  log_sink_filter              = "logName=\"organizations/${var.org_id}/logs/terratest-sin-registros\""
}

output "policy_names" {
  description = "Políticas aplicadas."
  value       = module.org.policy_names
}

output "policy_parent" {
  description = "Carpeta donde se aplicaron."
  value       = module.org.policy_parent
}

output "sink_name" {
  description = "Sink agregado."
  value       = module.org.sink_name
}

output "sink_writer_identity" {
  description = "Identidad del sink."
  value       = module.org.sink_writer_identity
}

output "sink_bucket" {
  description = "Bucket destino."
  value       = google_storage_bucket.sink.name
}
