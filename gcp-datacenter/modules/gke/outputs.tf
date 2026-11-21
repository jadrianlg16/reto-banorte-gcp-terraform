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

output "subnetwork" {
  description = "Subred del clúster (la configurada en el recurso)."
  value       = google_container_cluster.this.subnetwork
}

output "master_cidr" {
  description = "Rango /28 del plano de control configurado en el clúster (private_cluster_config.master_ipv4_cidr_block)."
  value       = google_container_cluster.this.private_cluster_config[0].master_ipv4_cidr_block
}

output "kms_key" {
  description = "Llave KMS del cifrado de secretos de Kubernetes en la capa de aplicación."
  value       = google_container_cluster.this.database_encryption[0].key_name
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
