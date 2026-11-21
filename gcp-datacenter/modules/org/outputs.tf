output "policy_names" {
  description = "Mapa restricción → nombre completo de la política (<padre>/policies/<restricción>), con las nueve políticas."
  value       = { for k, p in google_org_policy_policy.this : k => p.name }
}

output "policy_parent" {
  description = "Recurso donde se aplicaron las políticas (organizations/<n> o folders/<n>)."
  value       = local.policy_parent
}

output "sink_name" {
  description = "Nombre del sink agregado de la organización."
  value       = google_logging_organization_sink.this.name
}

output "sink_writer_identity" {
  description = "Identidad que escribe el sink agregado (\"serviceAccount:...\"); necesita permiso de escritura en el destino."
  value       = google_logging_organization_sink.this.writer_identity
}
