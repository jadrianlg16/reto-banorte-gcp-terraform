terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

# Valores de ejemplo: carpeta y cuenta de facturación son marcadores.
locals {
  labels = {
    env         = "dev"
    app         = "example"
    owner       = "example-team"
    cost_center = "example-000"
    managed_by  = "terraform"
  }
}

module "host" {
  source = "../.."

  prefix          = "bnt"
  environment     = "dev"
  name            = "net-spoke"
  folder_id       = "folders/000000000000"
  billing_account = "000000-000000-000000"
  apis            = ["dns.googleapis.com"]
  shared_vpc_host = true
  deletion_policy = "DELETE"
  labels          = local.labels
}

module "service" {
  source = "../.."

  prefix                  = "bnt"
  environment             = "dev"
  name                    = "app"
  folder_id               = "folders/000000000000"
  billing_account         = "000000-000000-000000"
  apis                    = ["container.googleapis.com", "run.googleapis.com"]
  shared_vpc_host_project = module.host.project_id
  deletion_policy         = "DELETE"
  labels                  = local.labels
}

output "project_ids" {
  description = "IDs de los proyectos de ejemplo."
  value       = { host = module.host.project_id, service = module.service.project_id }
}
