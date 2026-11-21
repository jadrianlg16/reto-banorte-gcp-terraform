output "bucket_name" {
  description = "Nombre del bucket de logs."
  value       = google_storage_bucket.this.name
}

output "bucket_url" {
  description = "URL gs:// del bucket de logs."
  value       = google_storage_bucket.this.url
}

output "destination" {
  description = "Destino de Logging del bucket (storage.googleapis.com/<bucket>), para un sink creado fuera del módulo."
  value       = local.destination
}

output "sink_name" {
  description = "Nombre del sink creado, o null si parent es null."
  value       = local.parent_type == "none" ? null : local.sink_name
}

output "writer_identity" {
  description = "Identidad que escribe el sink (\"serviceAccount:...\"), o null si parent es null."
  value       = local.writer_identity
}
