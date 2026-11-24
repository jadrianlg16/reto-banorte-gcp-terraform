# Fixture de integración del módulo off-hours-shutdown: los trabajos de Cloud Scheduler de una
# instancia de Cloud SQL y un pool de GKE, con la cuenta de servicio que firma sus tokens. La
# instancia y el pool no existen (crearlos cuesta y tarda): la prueba revisa los trabajos en la
# API de Cloud Scheduler, no su efecto. Si un horario se cumple durante la prueba, el trabajo
# recibe un 404 o un 403 y no cambia nada.

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
  description = "Región de los trabajos."
  type        = string
}

resource "google_service_account" "scheduler" {
  project      = var.project_id
  account_id   = "${var.prefix}-sched"
  display_name = "Terratest: trabajos del apagado fuera de horario"
}

module "off_hours" {
  source = "../../../modules/off-hours-shutdown"

  project_id  = var.project_id
  prefix      = var.prefix
  environment = "dev"
  region      = var.region

  time_zone      = "America/Monterrey"
  start_schedule = "0 7 * * 1-5"
  stop_schedule  = "0 20 * * 1-5"

  service_account_email = google_service_account.scheduler.email

  sql_instances = {
    primary = "${var.prefix}-sql-inexistente"
  }
  gke_node_pools = {
    general = {
      location       = var.region
      cluster        = "${var.prefix}-gke-inexistente"
      node_pool      = "${var.prefix}-nps-general"
      min_node_count = 0
      max_node_count = 3
    }
  }
}

output "job_ids" {
  description = "IDs de los trabajos por llave."
  value       = module.off_hours.job_ids
}

output "scheduler_email" {
  description = "Cuenta que debe firmar el token OAuth de cada trabajo."
  value       = google_service_account.scheduler.email
}

output "sql_instance" {
  description = "Instancia a la que apuntan los trabajos de Cloud SQL."
  value       = "${var.prefix}-sql-inexistente"
}

output "node_pool_path" {
  description = "Ruta del pool (locations/<l>/clusters/<c>/nodePools/<np>) de los trabajos de GKE."
  value       = "locations/${var.region}/clusters/${var.prefix}-gke-inexistente/nodePools/${var.prefix}-nps-general"
}
