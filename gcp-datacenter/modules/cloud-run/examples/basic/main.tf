# Ejemplo mínimo: servicio de prod con salida directa a la VPC compartida del spoke. Los
# valores son de ejemplo; en la etapa 5 llegan de las salidas de las etapas 2, 3 y 4.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

module "run" {
  source = "../.."

  project_id  = "example-prod-app"
  prefix      = "bnt"
  environment = "prod"
  region      = "us-central1"

  image   = "us-central1-docker.pkg.dev/example-prod-app/apps/api:1.0.0"
  network = "projects/example-prod-net-spoke/global/networks/bnt-prod-net-vpc"
  subnet  = "projects/example-prod-net-spoke/regions/us-central1/subnetworks/bnt-prod-net-run-usc1"

  service_account = "bnt-prod-app-run@example-prod-app.iam.gserviceaccount.com"
  # La etapa 2 no tiene un uso de llave propio de Cloud Run; el ejemplo usa la de compute.
  kms_key = "projects/example-common-security/locations/us-central1/keyRings/bnt-prod-sec-kr-usc1/cryptoKeys/compute"

  secret_env = {
    DB_CONFIG = { secret = "projects/example-common-security/secrets/bnt-prod-sec-db-config" }
  }
  invokers = ["group:example-app-callers@example.com"]

  labels = {
    env         = "prod"
    app         = "app"
    owner       = "plataforma"
    cost_center = "ti-001"
    managed_by  = "terraform"
  }
}

output "neg_id" {
  description = "NEG sin servidor de ejemplo."
  value       = module.run.neg_id
}
