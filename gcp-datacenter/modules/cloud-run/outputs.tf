output "service_name" {
  description = "Nombre del servicio de Cloud Run."
  value       = google_cloud_run_v2_service.this.name
}

output "service_uri" {
  description = "URI del servicio (solo alcanzable desde la red interna o el balanceador)."
  value       = google_cloud_run_v2_service.this.uri
}

output "service_id" {
  description = "ID del servicio (projects/<p>/locations/<región>/services/<nombre>)."
  value       = google_cloud_run_v2_service.this.id
}

output "neg_id" {
  description = "ID del NEG sin servidor; es el backend que recibe el módulo load-balancer."
  value       = google_compute_region_network_endpoint_group.this.id
}

output "neg_self_link" {
  description = "Self link del NEG sin servidor."
  value       = google_compute_region_network_endpoint_group.this.self_link
}

output "location" {
  description = "Región del servicio."
  value       = google_cloud_run_v2_service.this.location
}
