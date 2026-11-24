# Interfaz con las etapas siguientes (ADR 0029, "Interfaces entre etapas"): nombres y tipos
# fijos. Una raíz que necesite otra salida lo reporta antes de agregarla.

output "project_id" {
  description = "ID del proyecto único."
  value       = var.project_id
}

output "project_number" {
  description = "Número del proyecto único."
  value       = tostring(local.project_number)
}

output "state_bucket" {
  description = "Nombre del bucket de estado; las raíces lo reciben como state_bucket y en -backend-config."
  value       = google_storage_bucket.state.name
}

output "state_kms_key_id" {
  description = "ID completo de la llave KMS que cifra el bucket de estado."
  value       = module.state_kms.key_ids["state"]
}

output "stage_service_accounts" {
  description = "Mapa raíz (1-base, 2-networks, 2-networks/<env>, 3-workloads/<env>) → correo de la cuenta del pipeline que la aplica."
  value       = { for k, sa in google_service_account.stage : k => sa.email }
}

output "read_service_account" {
  description = "Correo de la cuenta de solo lectura <prefix>-tf-read (plan, drift, prueba de humo y huérfanos; variable GCP_AUDIT_SERVICE_ACCOUNT)."
  value       = google_service_account.read.email
}

output "workload_identity_provider" {
  description = "Nombre completo del proveedor de WIF (projects/<número>/locations/global/workloadIdentityPools/<pool>/providers/<proveedor>), para google-github-actions/auth."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "workload_identity_pool" {
  description = "Nombre completo del pool de WIF."
  value       = google_iam_workload_identity_pool.github.name
}

output "custom_role_ids" {
  description = "Mapa rol → ID completo (projects/<id>/roles/<rol>) de los roles personalizados: secret_container_admin, service_account_manager, network_tag_manager y off_hours_scheduler."
  value       = { for k in keys(google_project_iam_custom_role.this) : k => local.custom_role_ids[k] }
}

output "state_iam_conditions" {
  description = "Mapa raíz → { writes, reads }: prefijos del bucket de estado que escribe y que lee la cuenta de cada raíz (ADR 0029 §3). tf-read lee todo el bucket."
  value       = { for k, r in local.stage_roots : k => { writes = r.writes, reads = r.reads } }
}
