# Ejemplo mínimo: MIG regional de prod en la subred compartida del spoke. Los valores son de
# ejemplo; en la etapa 5 llegan de las salidas de las etapas 2, 3 y 4.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

module "mig" {
  source = "../.."

  project_id  = "example-prod-app"
  prefix      = "bnt"
  environment = "prod"
  region      = "us-central1"

  subnet       = "projects/example-prod-net-spoke/regions/us-central1/subnetworks/bnt-prod-net-app-usc1"
  image        = "projects/example-images/global/images/family/example-hardened-linux"
  machine_type = "e2-standard-2"
  min_replicas = 2
  max_replicas = 6

  service_account = "bnt-prod-app-mig@example-prod-app.iam.gserviceaccount.com"
  kms_key         = "projects/example-common-security/locations/us-central1/keyRings/bnt-prod-sec-kr-usc1/cryptoKeys/compute"

  named_ports = { http = 8080 }
  health_check = {
    port         = 8080
    request_path = "/healthz"
  }

  labels = {
    env         = "prod"
    app         = "app"
    owner       = "plataforma"
    cost_center = "ti-001"
    managed_by  = "terraform"
  }
}

output "instance_group" {
  description = "Grupo de instancias de ejemplo."
  value       = module.mig.instance_group
}
