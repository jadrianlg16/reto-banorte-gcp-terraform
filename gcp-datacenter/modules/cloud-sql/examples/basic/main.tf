terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

# Ejemplo de prod con réplica en DR. Todos los valores son de ejemplo.
module "cloud_sql" {
  source = "../.."

  project_id         = "example-prod-app"
  prefix             = "bnt"
  environment        = "prod"
  region             = "us-central1"
  dr_region          = "us-east4"
  enable_dr          = true
  sql_tier           = "db-custom-2-7680"
  database_version   = "POSTGRES_16"
  network            = "projects/example-prod-net-spoke/global/networks/bnt-prod-net-vpc"
  allocated_ip_range = "bnt-prod-net-psa"
  kms_key            = "projects/example-common-security/locations/us-central1/keyRings/bnt-prod-sec-usc1/cryptoKeys/sql"
  dr_kms_key         = "projects/example-common-security/locations/us-east4/keyRings/bnt-prod-sec-use4/cryptoKeys/sql"
  databases          = ["app"]

  iam_users = [
    { email = "bnt-prod-app-workload@example-prod-app.iam.gserviceaccount.com", type = "CLOUD_IAM_SERVICE_ACCOUNT" },
    { email = "dba-team@example.com", type = "CLOUD_IAM_GROUP" },
  ]

  labels = {
    env         = "prod"
    app         = "app"
    owner       = "example-team"
    cost_center = "example-cc"
    managed_by  = "terraform"
  }
}

output "connection_name" {
  description = "Nombre de conexión de la instancia primaria."
  value       = module.cloud_sql.connection_name
}

output "replica_name" {
  description = "Nombre de la réplica en DR."
  value       = module.cloud_sql.replica_name
}
