# Fixture de integración del módulo cloud-sql (TEST_ALLOW_EXPENSIVE=true): instancia de dev
# (zonal, sin réplica) con IP privada por PSA, CMEK, PITR, SSL obligatorio y un usuario IAM.

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
  description = "Número del proyecto (correo del agente de Cloud SQL)."
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
  name       = "${var.prefix}-sql"
  region     = var.region
  enable_psa = true
}

module "cmek" {
  source = "../support/cmek"

  project_id        = var.project_id
  location          = var.region
  name              = "${var.prefix}-sql"
  identity_services = ["sqladmin.googleapis.com"]
  members           = ["serviceAccount:service-${var.project_number}@gcp-sa-cloud-sql.iam.gserviceaccount.com"]
}

resource "google_service_account" "workload" {
  project      = var.project_id
  account_id   = "${var.prefix}-sql-client"
  display_name = "Terratest: cliente IAM de Cloud SQL"
}

module "cloud_sql" {
  source = "../../../modules/cloud-sql"

  project_id         = var.project_id
  prefix             = var.prefix
  environment        = "dev"
  region             = var.region
  sql_tier           = "db-custom-1-3840"
  database_version   = "POSTGRES_16"
  network            = module.network.network_id
  allocated_ip_range = module.network.psa_range_name
  kms_key            = module.cmek.key_id
  databases          = ["app"]

  iam_users = [
    { email = "${var.prefix}-sql-client@${var.project_id}.iam.gserviceaccount.com", type = "CLOUD_IAM_SERVICE_ACCOUNT" },
  ]

  labels = var.labels

  # Solo para la prueba: permite el destroy (el módulo lo exige en prod).
  deletion_protection = false

  depends_on = [google_service_account.workload]
}

output "instance_name" {
  description = "Instancia."
  value       = module.cloud_sql.instance_name
}

output "connection_name" {
  description = "Nombre de conexión."
  value       = module.cloud_sql.connection_name
}

output "private_ip" {
  description = "IP privada."
  value       = module.cloud_sql.private_ip
}

output "database_names" {
  description = "Bases de datos."
  value       = module.cloud_sql.database_names
}

output "iam_user_names" {
  description = "Usuarios IAM."
  value       = module.cloud_sql.iam_user_names
}

output "kms_key_id" {
  description = "Llave de la instancia."
  value       = module.cmek.key_id
}
