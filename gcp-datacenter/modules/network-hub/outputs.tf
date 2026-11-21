output "network_self_link" {
  description = "self_link de la VPC (para peering, zonas de peering DNS y VPN)."
  value       = google_compute_network.this.self_link
}

output "network_name" {
  description = "Nombre de la VPC."
  value       = google_compute_network.this.name
}

output "network_id" {
  description = "ID de la VPC (projects/<proyecto>/global/networks/<nombre>)."
  value       = google_compute_network.this.id
}

output "routers" {
  description = "Mapa región → nombre del Cloud Router."
  value       = { for r, router in google_compute_router.this : r => router.name }
}

output "subnets" {
  description = "Mapa llave de subnets → { self_link, name, region, cidr }."
  value = {
    for k, s in google_compute_subnetwork.this : k => {
      self_link = s.self_link
      name      = s.name
      region    = s.region
      cidr      = s.ip_cidr_range
    }
  }
}
