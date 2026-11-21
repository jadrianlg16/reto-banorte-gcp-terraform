# Fixture de integración del módulo memorystore (TEST_ALLOW_EXPENSIVE=true): Redis de dev
# (BASIC, 1 GB) con IP privada por PSA y CMEK.

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
  description = "Número del proyecto (correo del agente de Memorystore)."
  type        = string
}

variable "prefix" {
  description = "Prefijo único de la ejecución."
  type        = string
}

variable "region" {
  description = "Región de la instancia."
  type        = string
}

variable "labels" {
  description = "Etiquetas obligatorias de la prueba."
  type        = map(string)
}

module "network" {
  source = "../support/network"

  project_id = var.project_id
  name       = "${var.prefix}-redis"
  region     = var.region
  enable_psa = true
}

module "cmek" {
  source = "../support/cmek"

  project_id        = var.project_id
  location          = var.region
  name              = "${var.prefix}-redis"
  identity_services = ["redis.googleapis.com"]
  members           = ["serviceAccount:service-${var.project_number}@cloud-redis.iam.gserviceaccount.com"]
}

module "memorystore" {
  source = "../../../modules/memorystore"

  project_id        = var.project_id
  prefix            = var.prefix
  environment       = "dev"
  region            = var.region
  tier              = "BASIC"
  memory_gb         = 1
  network           = module.network.network_id
  reserved_ip_range = module.network.psa_range_name
  kms_key           = module.cmek.key_id
  labels            = var.labels
}

output "instance_name" {
  description = "Instancia."
  value       = module.memorystore.instance_name
}

output "instance_id" {
  description = "ID de la instancia."
  value       = module.memorystore.instance_id
}

output "host" {
  description = "IP privada."
  value       = module.memorystore.host
}

output "port" {
  description = "Puerto."
  value       = module.memorystore.port
}

output "kms_key_id" {
  description = "Llave de la instancia."
  value       = module.cmek.key_id
}

output "network_id" {
  description = "VPC autorizada."
  value       = module.network.network_id
}
