# Ejemplo mínimo: clúster regional de prod sobre la VPC compartida del spoke. Los valores
# son de ejemplo; en la etapa 5 llegan de las salidas de las etapas 2, 3 y 4.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

module "gke" {
  source = "../.."

  project_id  = "example-prod-app"
  prefix      = "bnt"
  environment = "prod"
  location    = "us-central1"
  # Nombre por convención del proyecto único (ADR 0029 §4): <prefix>-<env>-<app>-gke[-dr].
  cluster_name = "bnt-prod-app-gke"

  network        = "projects/example-prod-net-spoke/global/networks/bnt-prod-net-vpc"
  subnet         = "projects/example-prod-net-spoke/regions/us-central1/subnetworks/bnt-prod-net-app-usc1"
  pods_range     = "pods"
  services_range = "services"
  master_cidr    = "10.30.38.0/28"

  master_authorized_networks = [
    { cidr_block = "10.30.0.0/20", display_name = "subred-app" },
  ]

  gke_node_pools = {
    general = {
      machine_type   = "e2-standard-4"
      min_node_count = 1
      max_node_count = 3
    }
  }

  node_service_account         = "bnt-prod-app-gke-nodes@example-prod-app.iam.gserviceaccount.com"
  kms_key                      = "projects/example-common-security/locations/us-central1/keyRings/bnt-prod-sec-kr-usc1/cryptoKeys/gke"
  authenticator_security_group = "gke-security-groups@example.com"

  labels = {
    env         = "prod"
    app         = "app"
    owner       = "plataforma"
    cost_center = "ti-001"
    managed_by  = "terraform"
  }
}

output "cluster_name" {
  description = "Nombre del clúster de ejemplo."
  value       = module.gke.cluster_name
}
