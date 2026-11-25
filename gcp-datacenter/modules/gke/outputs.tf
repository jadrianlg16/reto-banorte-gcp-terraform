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
  description = "Mapa llave de gke_node_pools → nombre del pool de nodos (con scheduled_scaling, los pools <prefix>-<env>-app-nps-<llave>)."
  value       = { for k, p in merge(google_container_node_pool.this, google_container_node_pool.scheduled) : k => p.name }
}

output "node_pools" {
  description = "Mapa llave de gke_node_pools → nombre del pool, ubicación y nombre del clúster, autoescalado configurado por zona (min_node_count y max_node_count) y si sus trabajos de apagado lo administran (scheduled). Lo usa el módulo off-hours-shutdown."
  value = {
    for k, p in merge(google_container_node_pool.this, google_container_node_pool.scheduled) : k => {
      name           = p.name
      location       = p.location
      cluster        = p.cluster
      min_node_count = var.gke_node_pools[k].min_node_count
      max_node_count = var.gke_node_pools[k].max_node_count
      scheduled      = var.scheduled_scaling
    }
  }
}

output "deletion_protection" {
  description = "Protección contra borrado efectiva del clúster (true en prod salvo teardown)."
  value       = google_container_cluster.this.deletion_protection
}
