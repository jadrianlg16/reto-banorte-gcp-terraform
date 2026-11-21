# Ejemplo: llavero de prod en la región primaria con dos llaves. Valores de ejemplo.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

module "kms" {
  source = "../.."

  project_id  = "example-security-project"
  prefix      = "bnt"
  environment = "prod"
  location    = "us-central1"

  keys = {
    sql = {}
    storage = {
      encrypter_decrypters = ["serviceAccount:service-000000000000@gs-project-accounts.iam.gserviceaccount.com"]
    }
  }

  labels = {
    env         = "prod"
    app         = "security"
    owner       = "example-team"
    cost_center = "cc-000"
    managed_by  = "terraform"
  }
}

output "key_ids" {
  description = "IDs de las llaves por uso."
  value       = module.kms.key_ids
}
