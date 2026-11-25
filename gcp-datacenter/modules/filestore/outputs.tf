output "instance_name" {
  description = "Nombre de la instancia de Filestore."
  value       = google_filestore_instance.this.name
}

output "ip_address" {
  description = "IP privada del servidor NFS (dentro del rango de Private Service Access)."
  value       = google_filestore_instance.this.networks[0].ip_addresses[0]
}

output "share_name" {
  description = "Nombre del recurso compartido NFS (se monta como <ip_address>:/<share_name>)."
  value       = google_filestore_instance.this.file_shares[0].name
}

output "instance_id" {
  description = "ID completo de la instancia (projects/<p>/locations/<ubicación>/instances/<nombre>)."
  value       = google_filestore_instance.this.id
}
