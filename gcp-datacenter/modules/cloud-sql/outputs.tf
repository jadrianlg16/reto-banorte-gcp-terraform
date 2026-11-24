output "instance_name" {
  description = "Nombre de la instancia primaria."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Nombre de conexión de la primaria (<proyecto>:<región>:<instancia>) para los conectores de Cloud SQL."
  value       = google_sql_database_instance.this.connection_name
}

output "activation_policy" {
  description = "Política de activación de la primaria según el estado: ALWAYS (encendida) o NEVER (detenida, por ejemplo por el apagado fuera de horario)."
  value       = google_sql_database_instance.this.settings[0].activation_policy
}

output "private_ip" {
  description = "IP privada de la primaria dentro del rango de Private Service Access."
  value       = google_sql_database_instance.this.private_ip_address
}

output "replica_name" {
  description = "Nombre de la réplica de lectura en DR; null si enable_dr = false."
  value       = try(google_sql_database_instance.replica["dr"].name, null)
}

output "replica_connection_name" {
  description = "Nombre de conexión de la réplica en DR; null si enable_dr = false."
  value       = try(google_sql_database_instance.replica["dr"].connection_name, null)
}

output "replica_private_ip" {
  description = "IP privada de la réplica en DR; null si enable_dr = false."
  value       = try(google_sql_database_instance.replica["dr"].private_ip_address, null)
}

output "database_names" {
  description = "Bases de datos creadas."
  value       = sort([for d in google_sql_database.this : d.name])
}

output "iam_user_names" {
  description = "Mapa correo → nombre del usuario de base de datos (las cuentas de servicio van sin .gserviceaccount.com)."
  value       = { for k, u in google_sql_user.iam : k => u.name }
}
