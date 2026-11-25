# Fixture de integración del módulo gke (TEST_ALLOW_EXPENSIVE=true): clúster privado de dev
# con un pool de un nodo, Workload Identity, Binary Authorization y secretos de etcd cifrados
# con CMEK, sobre una VPC de la prueba con rangos secundarios.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google      = { source = "hashicorp/google", version = "~> 6.0" }
    google-beta = { source = "hashicorp/google-beta", version = "~> 6.0" }
  }
}

provider "google" {}
provider "google-beta" {}

variable "project_id" {
  description = "Proyecto de la prueba."
  type        = string
}

variable "project_number" {
  description = "Número del proyecto (correos de los agentes de GKE y Compute Engine)."
  type        = string
}

variable "prefix" {
  description = "Prefijo único de la ejecución."
  type        = string
}

variable "region" {
  description = "Región del clúster."
  type        = string
}

variable "authenticator_security_group" {
  description = "Grupo gke-security-groups@<dominio> de Google Groups for RBAC."
  type        = string
}

variable "labels" {
  description = "Etiquetas obligatorias de la prueba."
  type        = map(string)
}

module "network" {
  source = "../support/network"

  project_id = var.project_id
  name       = "${var.prefix}-gke"
  region     = var.region
  cidr       = "10.10.0.0/20"
  secondary_ranges = {
    pods     = "10.10.64.0/18"
    services = "10.10.128.0/20"
  }
}

# GKE cifra etcd con el agente container-engine-robot y los discos de nodo con compute-system.
module "cmek" {
  source = "../support/cmek"

  project_id = var.project_id
  location   = var.region
  name       = "${var.prefix}-gke"
  members = [
    "serviceAccount:service-${var.project_number}@container-engine-robot.iam.gserviceaccount.com",
    "serviceAccount:service-${var.project_number}@compute-system.iam.gserviceaccount.com",
  ]
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.prefix}-gke-nodes"
  display_name = "Terratest: nodos de GKE"
}

resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

module "gke" {
  source = "../../../modules/gke"

  project_id  = var.project_id
  prefix      = var.prefix
  environment = "dev"
  location    = var.region

  network        = module.network.network_id
  subnet         = module.network.subnet_id
  pods_range     = "pods"
  services_range = "services"
  master_cidr    = "10.10.38.0/28"

  gke_node_pools = {
    general = {
      machine_type   = "e2-standard-2"
      min_node_count = 1
      max_node_count = 1
    }
  }

  node_service_account         = google_service_account.nodes.email
  kms_key                      = module.cmek.key_id
  authenticator_security_group = var.authenticator_security_group
  labels                       = var.labels

  # Solo para la prueba: permite el destroy.
  deletion_protection = false

  depends_on = [google_project_iam_member.nodes]
}

output "cluster_name" {
  description = "Nombre del clúster."
  value       = module.gke.cluster_name
}

output "location" {
  description = "Ubicación del clúster."
  value       = module.gke.location
}

output "workload_pool" {
  description = "Pool de Workload Identity."
  value       = module.gke.workload_pool
}

output "kms_key_id" {
  description = "Llave de cifrado de etcd."
  value       = module.cmek.key_id
}
