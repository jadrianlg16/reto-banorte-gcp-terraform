output "bucket_name" {
  description = "Nombre del bucket."
  value       = google_storage_bucket.this.name
}

output "bucket_url" {
  description = "URL gs:// del bucket."
  value       = google_storage_bucket.this.url
}

output "bucket_self_link" {
  description = "Self link del bucket."
  value       = google_storage_bucket.this.self_link
}

output "location" {
  description = "Ubicación del bucket en mayúsculas (región o multirregión)."
  value       = google_storage_bucket.this.location
}

output "data_locations" {
  description = "Regiones de la doble región; lista vacía si el bucket no es de doble región."
  value       = var.dual_region == null ? [] : [for r in var.dual_region.regions : upper(r)]
}
