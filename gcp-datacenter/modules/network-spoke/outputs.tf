output "network_name" {
  description = "Nombre de la VPC spoke."
  value       = google_compute_network.this.name
}

output "network_self_link" {
  description = "self_link de la VPC spoke."
  value       = google_compute_network.this.self_link
}

output "network_id" {
  description = "ID de la VPC spoke (projects/<proyecto>/global/networks/<nombre>)."
  value       = google_compute_network.this.id
}

output "subnets" {
  description = "Llave del plan de direccionamiento → { self_link, name, region, cidr, secondary_ranges }. secondary_ranges es un mapa nombre → CIDR con llaves pods y services (vacío en run, run_dr, proxy y proxy_dr)."
  value = merge(
    {
      for k, s in local.regular_subnets : k => {
        self_link        = google_compute_subnetwork.this[k].self_link
        name             = local.subnet_names[k]
        region           = s.region
        cidr             = s.cidr
        secondary_ranges = tomap(s.secondary)
      }
    },
    {
      for k, s in local.proxy_subnets : k => {
        self_link        = google_compute_subnetwork.proxy[k].self_link
        name             = local.subnet_names[k]
        region           = s.region
        cidr             = s.cidr
        secondary_ranges = tomap({})
      }
    },
  )
}

output "psa_range_name" {
  description = "Nombre del rango reservado de Private Service Access."
  value       = google_compute_global_address.psa.name
}

output "psa_connection_id" {
  description = "ID de la conexión de servicenetworking (para depends_on de Cloud SQL, Memorystore y Filestore)."
  value       = google_service_networking_connection.psa.id
}

output "reserved_cidrs" {
  description = "Rangos reservados sin subred: gke_master (y gke_master_dr con enable_dr) para el plano de control de GKE."
  value       = local.reserved_cidrs
}

output "routers" {
  description = "Mapa región → nombre del Cloud Router del spoke."
  value       = { for k, r in google_compute_router.this : local.active_regions[k] => r.name }
}

output "nat_names" {
  description = "Mapa región → nombre del Cloud NAT."
  value       = { for k, n in google_compute_router_nat.this : local.active_regions[k] => n.name }
}
