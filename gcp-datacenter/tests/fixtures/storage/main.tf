# Fixture de integración del módulo storage: bucket regional con CMEK propia de la prueba.

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

module "cmek" {
  source = "../support/cmek"

  project_id          = var.project_id
  location            = var.region
  name                = "${var.prefix}-storage"
  grant_storage_agent = true
}

module "storage" {
  source = "../../../modules/storage"

  project_id  = var.project_id
  prefix      = var.prefix
  environment = "dev"
  name        = "assets"
  location    = var.region
  kms_key     = module.cmek.key_id
  labels      = var.labels

  # Solo para la prueba: el bucket se vacía en el destroy.
  force_destroy = true
}

output "bucket_name" {
  description = "Nombre del bucket."
  value       = module.storage.bucket_name
}

output "kms_key_id" {
  description = "Llave con la que debe quedar cifrado el bucket."
  value       = module.cmek.key_id
}
