terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

# Ejemplo: bóveda en la región de DR, planes diarios de VM y Cloud SQL en la primaria con una
# instancia asociada, y plan de Backup for GKE con CMEK. Valores de ejemplo únicamente.
module "backup_dr" {
  source = "../.."

  project_id     = "example-prod-app"
  prefix         = "bnt"
  environment    = "prod"
  region         = "us-central1"
  dr_region      = "us-east4"
  retention_days = 30

  # Bóveda, planes y recursos en el mismo proyecto (valor por defecto, ADR 0029).
  access_restriction = "WITHIN_PROJECT"

  protected_resources = {
    sql = {
      resource = "projects/example-prod-app/instances/bnt-prod-data-sql-usc1"
      plan     = "sql"
    }
  }

  enable_gke_backup  = true
  gke_cluster_id     = "projects/example-prod-app/locations/us-central1/clusters/bnt-prod-app-gke-usc1"
  gke_backup_kms_key = "projects/example-common-security/locations/us-east4/keyRings/bnt-prod-sec-kr-use4/cryptoKeys/backup"

  labels = {
    env         = "prod"
    app         = "web"
    owner       = "plataforma"
    cost_center = "cc-0000"
    managed_by  = "terraform"
  }
}

output "vault_id" {
  description = "Bóveda creada."
  value       = module.backup_dr.vault_id
}

output "plan_ids" {
  description = "Planes creados."
  value       = module.backup_dr.plan_ids
}
