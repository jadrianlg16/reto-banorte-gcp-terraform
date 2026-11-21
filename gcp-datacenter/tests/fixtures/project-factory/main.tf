# Fixture de integración del módulo project-factory: un proyecto host de Shared VPC y un
# proyecto de servicio unido a él, ambos con deletion_policy = "DELETE" para el destroy.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {}

variable "prefix" {
  description = "Prefijo único de la ejecución."
  type        = string
}

variable "folder_id" {
  description = "Carpeta de los proyectos (número o folders/<n>)."
  type        = string
}

variable "billing_account" {
  description = "Cuenta de facturación de los proyectos."
  type        = string
}

variable "labels" {
  description = "Etiquetas obligatorias de la prueba."
  type        = map(string)
}

module "host" {
  source = "../../../modules/project-factory"

  prefix          = var.prefix
  environment     = "dev"
  name            = "net-spoke"
  folder_id       = var.folder_id
  billing_account = var.billing_account
  apis            = ["compute.googleapis.com", "dns.googleapis.com"]
  shared_vpc_host = true
  deletion_policy = "DELETE"
  labels          = var.labels
}

module "service" {
  source = "../../../modules/project-factory"

  prefix                  = var.prefix
  environment             = "dev"
  name                    = "app"
  folder_id               = var.folder_id
  billing_account         = var.billing_account
  apis                    = ["compute.googleapis.com", "run.googleapis.com"]
  shared_vpc_host_project = module.host.project_id
  deletion_policy         = "DELETE"
  labels                  = var.labels
}

output "host_project_id" {
  description = "Proyecto host."
  value       = module.host.project_id
}

output "service_project_id" {
  description = "Proyecto de servicio."
  value       = module.service.project_id
}

output "service_enabled_apis" {
  description = "APIs habilitadas en el proyecto de servicio."
  value       = module.service.enabled_apis
}

output "service_shared_vpc_host_project" {
  description = "Host al que quedó unido el proyecto de servicio."
  value       = module.service.shared_vpc_host_project
}
