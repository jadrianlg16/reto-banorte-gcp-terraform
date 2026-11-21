output "cluster_name" {
  description = "Nombre del clúster."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "ID del clúster (projects/<p>/locations/<l>/clusters/<nombre>); lo usa backup-dr como gke_cluster_id."
  value       = google_container_cluster.this.id
}

output "workload_pool" {
  description = "Pool de Workload Identity (<proyecto>.svc.id.goog) para enlazar cuentas de Kubernetes con cuentas de servicio."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "location" {
  description = "Ubicación del clúster (región si es regional)."
  value       = google_container_cluster.this.location
}

output "endpoint" {
  description = "IP del plano de control (privada si enable_private_endpoint = true)."
  value       = google_container_cluster.this.endpoint
}

output "node_pool_names" {
  description = "Mapa llave de gke_node_pools → nombre del pool de nodos."
  value       = { for k, p in google_container_node_pool.this : k => p.name }
}
