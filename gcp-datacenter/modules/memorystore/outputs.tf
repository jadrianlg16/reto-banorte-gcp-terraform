output "host" {
  description = "IP privada del nodo primario de Redis."
  value       = google_redis_instance.this.host
}

output "port" {
  description = "Puerto de Redis (6378 con TLS en tránsito)."
  value       = google_redis_instance.this.port
}

output "instance_name" {
  description = "Nombre de la instancia de Redis."
  value       = google_redis_instance.this.name
}

output "instance_id" {
  description = "ID completo de la instancia (projects/<p>/locations/<región>/instances/<nombre>)."
  value       = google_redis_instance.this.id
}

output "server_ca_certs" {
  description = "Certificados públicos de la CA del servidor, para que los clientes validen el TLS (no son secretos)."
  value       = [for c in google_redis_instance.this.server_ca_certs : c.cert]
}
