# Red de apoyo para los fixtures que necesitan una VPC sin probar los módulos de red: una VPC
# en modo personalizado, una subred con Private Google Access (y rangos secundarios
# opcionales) y, si se pide, Private Service Access para Cloud SQL, Memorystore y Filestore.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

variable "project_id" {
  description = "Proyecto de la prueba."
  type        = string
}

variable "name" {
  description = "Nombre único de la VPC; la subred y el rango de PSA derivan de él."
  type        = string
}

variable "region" {
  description = "Región de la subred."
  type        = string
}

variable "cidr" {
  description = "Rango primario de la subred."
  type        = string
  default     = "10.250.0.0/20"
}

variable "secondary_ranges" {
  description = "Rangos secundarios de la subred (nombre → CIDR), por ejemplo pods y services para GKE."
  type        = map(string)
  default     = {}
}

variable "enable_psa" {
  description = "Si es true, reserva un rango y crea la conexión de Private Service Access."
  type        = bool
  default     = false
}

variable "psa_cidr" {
  description = "Rango reservado para Private Service Access."
  type        = string
  default     = "10.251.0.0/20"
}

resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = var.name
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

resource "google_compute_subnetwork" "this" {
  project                  = var.project_id
  name                     = "${var.name}-subnet"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.cidr
  private_ip_google_access = true

  dynamic "secondary_ip_range" {
    for_each = var.secondary_ranges
    content {
      range_name    = secondary_ip_range.key
      ip_cidr_range = secondary_ip_range.value
    }
  }

  log_config {
    flow_sampling = 0.5
  }
}

resource "google_compute_global_address" "psa" {
  count = var.enable_psa ? 1 : 0

  project       = var.project_id
  name          = "${var.name}-psa"
  network       = google_compute_network.this.id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = split("/", var.psa_cidr)[0]
  prefix_length = tonumber(split("/", var.psa_cidr)[1])
}

resource "google_service_networking_connection" "psa" {
  count = var.enable_psa ? 1 : 0

  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa[0].name]

  # Al destruir, la conexión se abandona si la API todavía la usa (instancias recién
  # borradas); el proyecto efímero se lleva el resto.
  deletion_policy = "ABANDON"
}

output "network_id" {
  description = "ID de la VPC (projects/<p>/global/networks/<n>)."
  value       = google_compute_network.this.id
}

output "network_self_link" {
  description = "self_link de la VPC."
  value       = google_compute_network.this.self_link
}

output "network_name" {
  description = "Nombre de la VPC."
  value       = google_compute_network.this.name
}

output "subnet_id" {
  description = "ID de la subred (projects/<p>/regions/<r>/subnetworks/<n>)."
  value       = google_compute_subnetwork.this.id
}

output "subnet_name" {
  description = "Nombre de la subred."
  value       = google_compute_subnetwork.this.name
}

output "psa_range_name" {
  description = "Nombre del rango de PSA (null si enable_psa = false). Disponible después de la conexión."
  value       = var.enable_psa ? google_compute_global_address.psa[0].name : null

  depends_on = [google_service_networking_connection.psa]
}
