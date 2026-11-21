terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

# Ejemplo: balanceador externo global con un MIG (y su equivalente en DR) y un NEG serverless
# de Cloud Run en /api/*, más un balanceador interno regional. Valores de ejemplo únicamente.

locals {
  project_id = "example-prod-app"
  labels = {
    env         = "prod"
    app         = "web"
    owner       = "plataforma"
    cost_center = "cc-0000"
    managed_by  = "terraform"
  }
}

module "external_lb" {
  source = "../.."

  project_id      = local.project_id
  prefix          = "bnt"
  environment     = "prod"
  name            = "web"
  type            = "external"
  labels          = local.labels
  domain_names    = ["app.example.com"]
  security_policy = "projects/example-prod-app/global/securityPolicies/bnt-prod-app-web-armor"
  dr_active       = false

  default_backend = "web"
  backends = {
    web = {
      groups          = [{ group = "projects/example-prod-app/regions/us-central1/instanceGroups/bnt-prod-app-web-mig-usc1" }]
      dr_groups       = [{ group = "projects/example-prod-app/regions/us-east4/instanceGroups/bnt-prod-app-web-mig-use4" }]
      health_check_id = "projects/example-prod-app/global/healthChecks/bnt-prod-app-web-hc"
    }
    api = {
      serverless = true
      protocol   = "HTTPS"
      paths      = ["/api/*"]
      groups     = [{ group = "projects/example-prod-app/regions/us-central1/networkEndpointGroups/bnt-prod-app-api-neg-usc1" }]
      dr_groups  = [{ group = "projects/example-prod-app/regions/us-east4/networkEndpointGroups/bnt-prod-app-api-neg-use4" }]
    }
  }
}

module "internal_lb" {
  source = "../.."

  project_id   = local.project_id
  prefix       = "bnt"
  environment  = "prod"
  name         = "core"
  type         = "internal"
  labels       = local.labels
  region       = "us-central1"
  network      = "projects/example-prod-net-spoke/global/networks/bnt-prod-net-vpc"
  subnet       = "projects/example-prod-net-spoke/regions/us-central1/subnetworks/bnt-prod-net-app-usc1"
  domain_names = ["core.example.com"]

  default_backend = "core"
  backends = {
    core = {
      groups       = [{ group = "projects/example-prod-app/regions/us-central1/instanceGroups/bnt-prod-app-core-mig-usc1" }]
      health_check = { port = 8080, request_path = "/healthz" }
    }
  }
}

output "external_ip_address" {
  description = "IP pública del balanceador externo."
  value       = module.external_lb.ip_address
}

output "internal_ip_address" {
  description = "IP interna del balanceador interno."
  value       = module.internal_lb.ip_address
}
