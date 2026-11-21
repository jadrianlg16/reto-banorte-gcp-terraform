# Fixture de integración del módulo vpc-sc (alcance de organización: TEST_ALLOW_ORG=true).
# Una organización tiene una sola política de acceso de nivel organización, así que la prueba
# exige una existente (TEST_ACCESS_POLICY_ID) y crea en ella un perímetro único en dry-run con
# el proyecto de la prueba dentro. En dry-run no bloquea ningún tráfico.

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

variable "access_policy_id" {
  description = "Número de la política de Access Context Manager existente."
  type        = string
}

variable "project_number" {
  description = "Número del proyecto de la prueba (recurso del perímetro)."
  type        = string
}

variable "prefix" {
  description = "Prefijo único de la ejecución."
  type        = string
}

variable "project_id" {
  description = "Proyecto de la prueba (aloja la cuenta que simula al pipeline)."
  type        = string
}

# Cuenta que hace de "cuenta de servicio del pipeline" en la regla de entrada.
resource "google_service_account" "pipeline" {
  project      = var.project_id
  account_id   = "${var.prefix}-vpcsc-pipe"
  display_name = "Terratest: identidad de entrada del perímetro"
}

module "vpc_sc" {
  source = "../../../modules/vpc-sc"

  org_id              = var.org_id
  prefix              = var.prefix
  environment         = "dev"
  access_policy_id    = var.access_policy_id
  resources           = ["projects/${var.project_number}"]
  restricted_services = ["storage.googleapis.com", "bigquery.googleapis.com"]
  ingress_identities  = ["serviceAccount:${google_service_account.pipeline.email}"]
  enforced            = false
}

output "ingress_identity" {
  description = "Identidad admitida por la regla de entrada."
  value       = "serviceAccount:${google_service_account.pipeline.email}"
}

output "perimeter_name" {
  description = "Nombre completo del perímetro."
  value       = module.vpc_sc.perimeter_name
}

output "access_policy_id" {
  description = "Política usada."
  value       = module.vpc_sc.access_policy_id
}

output "enforced" {
  description = "Si el perímetro está forzado."
  value       = module.vpc_sc.enforced
}
