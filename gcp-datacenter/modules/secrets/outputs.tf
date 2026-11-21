output "secret_ids" {
  description = "Mapa nombre corto → ID del secreto (projects/<proyecto>/secrets/<id>)."
  value       = { for name, s in google_secret_manager_secret.this : name => s.id }
}

output "secret_names" {
  description = "Mapa nombre corto → secret_id (<prefix>-<environment>-sec-<nombre>)."
  value       = { for name, s in google_secret_manager_secret.this : name => s.secret_id }
}
