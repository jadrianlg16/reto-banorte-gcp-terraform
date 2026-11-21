# Fixture de integración del módulo compute-mig: MIG regional de una o dos VM Shielded, sin IP
# pública, con disco cifrado con CMEK y cuenta de servicio propia.

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
  description = "Número del proyecto (correo del agente de Compute Engine)."
  type        = string
}

variable "prefix" {
  description = "Prefijo único de la ejecución."
  type        = string
}

variable "region" {
  description = "Región del MIG."
  type        = string
}

variable "image" {
  description = "Imagen de las VM (en producción, una imagen endurecida)."
  type        = string
}

variable "labels" {
  description = "Etiquetas obligatorias de la prueba."
  type        = map(string)
}

module "network" {
  source = "../support/network"

  project_id = var.project_id
  name       = "${var.prefix}-mig"
  region     = var.region
}

# VERIFICAR-EN-APPLY: el agente compute-system existe al habilitar la API de Compute.
module "cmek" {
  source = "../support/cmek"

  project_id = var.project_id
  location   = var.region
  name       = "${var.prefix}-mig"
  members    = ["serviceAccount:service-${var.project_number}@compute-system.iam.gserviceaccount.com"]
}

resource "google_service_account" "vm" {
  project      = var.project_id
  account_id   = "${var.prefix}-mig-vm"
  display_name = "Terratest: VM del MIG"
}

module "mig" {
  source = "../../../modules/compute-mig"

  project_id  = var.project_id
  prefix      = var.prefix
  environment = "dev"
  region      = var.region

  subnet       = module.network.subnet_id
  image        = var.image
  machine_type = "e2-small"
  min_replicas = 1
  max_replicas = 2

  service_account = google_service_account.vm.email
  kms_key         = module.cmek.key_id

  named_ports = { http = 80 }
  health_check = {
    port         = 80
    request_path = "/"
  }

  labels = var.labels
}

output "instance_group_manager_name" {
  description = "MIG regional."
  value       = module.mig.instance_group_manager_name
}

output "instance_template_self_link" {
  description = "Plantilla regional."
  value       = module.mig.instance_template_self_link
}

output "health_check_id" {
  description = "Verificación de salud de autocuración."
  value       = module.mig.health_check_id
}

output "kms_key_id" {
  description = "Llave de los discos."
  value       = module.cmek.key_id
}

output "service_account" {
  description = "Cuenta de servicio de las VM."
  value       = google_service_account.vm.email
}
