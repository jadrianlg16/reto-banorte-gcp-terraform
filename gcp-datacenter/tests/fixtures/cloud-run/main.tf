# Fixture de integración del módulo cloud-run: servicio v2 con salida directa a una VPC de la
# prueba, cuenta de servicio propia y CMEK; entrada solo interna y del balanceador.

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
  description = "Número del proyecto (correo del agente de Cloud Run)."
  type        = string
}

variable "prefix" {
  description = "Prefijo único de la ejecución."
  type        = string
}

variable "region" {
  description = "Región del servicio."
  type        = string
}

variable "image" {
  description = "Imagen del contenedor (pública de muestra por defecto en la prueba)."
  type        = string
}

variable "labels" {
  description = "Etiquetas obligatorias de la prueba."
  type        = map(string)
}

module "network" {
  source = "../support/network"

  project_id = var.project_id
  name       = "${var.prefix}-run"
  region     = var.region
  cidr       = "10.10.36.0/24"
}

# VERIFICAR-EN-APPLY: que CMEK en Cloud Run acepte la imagen pública de muestra y que el agente
# serverless-robot-prod exista al habilitar la API.
module "cmek" {
  source = "../support/cmek"

  project_id = var.project_id
  location   = var.region
  name       = "${var.prefix}-run"
  members    = ["serviceAccount:service-${var.project_number}@serverless-robot-prod.iam.gserviceaccount.com"]
}

resource "google_service_account" "run" {
  project      = var.project_id
  account_id   = "${var.prefix}-run-svc"
  display_name = "Terratest: servicio de Cloud Run"
}

module "run" {
  source = "../../../modules/cloud-run"

  project_id  = var.project_id
  prefix      = var.prefix
  environment = "dev"
  region      = var.region

  image   = var.image
  network = module.network.network_id
  subnet  = module.network.subnet_id

  service_account = google_service_account.run.email
  kms_key         = module.cmek.key_id

  # Binary Authorization queda activa (valor por defecto del módulo); la política por defecto
  # de un proyecto nuevo admite la imagen de muestra.
  # VERIFICAR-EN-APPLY: que la política del proyecto de pruebas (TERRATEST_PROJECT_ID, o el
  # efímero con TEST_EPHEMERAL_PROJECTS) no bloquee la imagen. Si es el mismo proyecto de la
  # landing zone, manda la política única de 1-base (tests/README.md).

  labels = var.labels
}

output "service_name" {
  description = "Nombre del servicio."
  value       = module.run.service_name
}

output "location" {
  description = "Región del servicio."
  value       = module.run.location
}

output "neg_id" {
  description = "NEG sin servidor."
  value       = module.run.neg_id
}

output "service_account" {
  description = "Cuenta de servicio del servicio."
  value       = google_service_account.run.email
}

output "kms_key_id" {
  description = "Llave del servicio."
  value       = module.cmek.key_id
}
