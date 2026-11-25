# Fixture de integración del módulo iam: asignaciones aditivas a una cuenta de servicio de la
# prueba en el proyecto y, con condición, en un bucket de la prueba.

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
  description = "Región del bucket."
  type        = string
}

variable "labels" {
  description = "Etiquetas obligatorias de la prueba."
  type        = map(string)
}

resource "google_service_account" "subject" {
  project      = var.project_id
  account_id   = "${var.prefix}-iam-subject"
  display_name = "Terratest: sujeto de las asignaciones"
}

resource "google_storage_bucket" "target" {
  project                     = var.project_id
  name                        = "${var.project_id}-${var.prefix}-iam"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true
  labels                      = var.labels
}

locals {
  member = "serviceAccount:${var.prefix}-iam-subject@${var.project_id}.iam.gserviceaccount.com"
}

module "iam" {
  source = "../../../modules/iam"

  bindings = [
    {
      scope    = "project"
      resource = var.project_id
      role     = "roles/logging.viewer"
      member   = local.member
    },
    {
      key      = "bucket-prefix-reader"
      scope    = "storage_bucket"
      resource = google_storage_bucket.target.name
      role     = "roles/storage.objectViewer"
      member   = local.member
      condition = {
        title      = "solo-prefijo-datos"
        expression = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.target.name}/objects/datos/\")"
      }
    },
  ]

  depends_on = [google_service_account.subject]
}

output "members" {
  description = "Miembros con algún rol."
  value       = module.iam.members
}

output "member" {
  description = "Miembro de la prueba."
  value       = local.member
}

output "bucket_name" {
  description = "Bucket con la asignación condicionada."
  value       = google_storage_bucket.target.name
}
