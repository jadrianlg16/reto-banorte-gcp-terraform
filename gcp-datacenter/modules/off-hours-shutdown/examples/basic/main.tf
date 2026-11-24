# Ejemplo mínimo: apagado de qa de lunes a viernes de 20:00 a 07:00 (hora de Monterrey) para la
# instancia de Cloud SQL y un pool de GKE. Los valores son de ejemplo; en la etapa 5 llegan de
# los módulos cloud-sql y gke y de la cuenta del scheduler de la etapa 4.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

module "off_hours" {
  source = "../.."

  project_id  = "example-qa-app"
  prefix      = "bnt"
  environment = "qa"
  region      = "us-central1"

  time_zone      = "America/Monterrey"
  start_schedule = "0 7 * * 1-5"
  stop_schedule  = "0 20 * * 1-5"

  service_account_email = "bnt-qa-app-sched@example-qa-app.iam.gserviceaccount.com"

  sql_instances = {
    primary = "bnt-qa-data-sql-usc1"
  }
  gke_node_pools = {
    general = {
      location       = "us-central1"
      cluster        = "bnt-qa-app-gke-usc1"
      node_pool      = "bnt-qa-app-nps-general"
      min_node_count = 1
      max_node_count = 3
    }
  }
}

output "job_names" {
  description = "Trabajos de Cloud Scheduler del ejemplo."
  value       = module.off_hours.job_names
}
