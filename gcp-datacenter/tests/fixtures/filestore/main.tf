# Fixture de integración del módulo filestore (TEST_ALLOW_EXPENSIVE=true): instancia ZONAL de
# 1 TiB (el mínimo del tier) con CMEK y red por PSA.

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
  description = "Número del proyecto (correo del agente de Filestore)."
  type        = string
}

variable "prefix" {
  description = "Prefijo único de la ejecución."
  type        = string
}

variable "region" {
  description = "Región de la llave; la instancia va en la zona <región>-a."
  type        = string
}

variable "labels" {
  description = "Etiquetas obligatorias de la prueba."
  type        = map(string)
}

module "network" {
  source = "../support/network"

  project_id = var.project_id
  name       = "${var.prefix}-nfs"
  region     = var.region
  enable_psa = true
}

module "cmek" {
  source = "../support/cmek"

  project_id        = var.project_id
  location          = var.region
  name              = "${var.prefix}-nfs"
  identity_services = ["file.googleapis.com"]
  members           = ["serviceAccount:service-${var.project_number}@cloud-filer.iam.gserviceaccount.com"]
}

module "filestore" {
  source = "../../../modules/filestore"

  project_id        = var.project_id
  prefix            = var.prefix
  environment       = "dev"
  tier              = "ZONAL"
  location          = "${var.region}-a"
  capacity_gb       = 1024
  network           = module.network.network_id
  reserved_ip_range = module.network.psa_range_name
  kms_key           = module.cmek.key_id
  labels            = var.labels

  # Solo para la prueba: permite el destroy.
  deletion_protection = false
}

output "instance_name" {
  description = "Instancia."
  value       = module.filestore.instance_name
}

output "instance_id" {
  description = "ID de la instancia."
  value       = module.filestore.instance_id
}

output "ip_address" {
  description = "IP del servidor NFS."
  value       = module.filestore.ip_address
}

output "location" {
  description = "Zona de la instancia."
  value       = "${var.region}-a"
}

output "kms_key_id" {
  description = "Llave de la instancia."
  value       = module.cmek.key_id
}
