# Interfaz con las etapas siguientes (§7.1): nombres y tipos fijos.

output "folder_ids" {
  description = "Mapa carpeta (common, dev, qa, prod) → ID completo \"folders/<número>\"."
  value       = module.folders.ids
}

output "common_project_ids" {
  description = "Mapa net_hub, logging, security, backup → ID del proyecto de common."
  value       = { for k, p in module.common_project : k => p.project_id }
}

output "common_project_numbers" {
  description = "Mapa net_hub, logging, security, backup → número del proyecto de common."
  value       = { for k, p in module.common_project : k => p.project_number }
}

output "log_bucket" {
  description = "Nombre del bucket de logs de auditoría (destino del sink agregado)."
  value       = module.audit_logs.bucket_name
}

# --- Salidas adicionales ------------------------------------------------------------------

output "log_sink_writer_identity" {
  description = "Identidad que escribe el sink agregado de la organización."
  value       = module.org.sink_writer_identity
}

output "org_policy_names" {
  description = "Mapa restricción → nombre completo de las nueve políticas de organización."
  value       = module.org.policy_names
}

output "logging_kms_key_ids" {
  description = "Mapa uso (logs, pubsub) → ID de las llaves KMS del proyecto logging (ADR 0018)."
  value       = module.logging_kms.key_ids
}

output "scc_findings_topic" {
  description = "ID del tema de Pub/Sub que recibe los hallazgos de Security Command Center."
  value       = google_pubsub_topic.scc_findings.id
}

output "budget_name" {
  description = "Nombre completo del presupuesto de la organización."
  value       = google_billing_budget.org.name
}
