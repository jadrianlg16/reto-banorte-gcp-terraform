# Fixture de integración del módulo backup-dr (TEST_ALLOW_EXPENSIVE=true): bóveda en la región
# de DR con retención mínima forzada de 30 días y planes diarios de VM y Cloud SQL en la
# primaria, sin recursos asociados (sin respaldos, la bóveda se puede borrar). Backup for GKE
# queda fuera: necesita un clúster (lo cubre la prueba de extremo a extremo en prod).

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
  description = "Región primaria (planes)."
  type        = string
}

variable "dr_region" {
  description = "Región de DR (bóveda)."
  type        = string
}

variable "labels" {
  description = "Etiquetas obligatorias de la prueba."
  type        = map(string)
}

module "backup_dr" {
  source = "../../../modules/backup-dr"

  project_id     = var.project_id
  prefix         = var.prefix
  environment    = "dev"
  region         = var.region
  dr_region      = var.dr_region
  retention_days = 30
  labels         = var.labels
}

output "vault_id" {
  description = "Bóveda."
  value       = module.backup_dr.vault_id
}

output "plan_ids" {
  description = "Planes."
  value       = module.backup_dr.plan_ids
}
