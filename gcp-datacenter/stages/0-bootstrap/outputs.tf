# Interfaz con las etapas siguientes (§7.0): nombres y tipos fijos.

output "seed_project_id" {
  description = "ID del proyecto semilla."
  value       = module.seed_project.project_id
}

output "bootstrap_folder_id" {
  description = "ID de la carpeta bootstrap (\"folders/<número>\")."
  value       = module.bootstrap_folder.ids[local.environment]
}

output "state_bucket" {
  description = "Nombre del bucket de estado; las etapas lo reciben como state_bucket y en -backend-config."
  value       = google_storage_bucket.state.name
}

output "state_kms_key_id" {
  description = "ID completo de la llave KMS que cifra el bucket de estado."
  value       = module.state_kms.key_ids["state"]
}

output "stage_service_accounts" {
  description = "Mapa etapa (1-org, 2-security, 3-networks, 4-projects, 5-workloads) → correo de su cuenta de servicio."
  value       = { for k, sa in google_service_account.stage : k => sa.email }
}

output "workload_identity_provider" {
  description = "Nombre completo del proveedor de WIF (projects/<número>/locations/global/workloadIdentityPools/<pool>/providers/<proveedor>), para google-github-actions/auth."
  value       = google_iam_workload_identity_pool_provider.github.name
}

# --- Salidas adicionales ------------------------------------------------------------------

output "seed_project_number" {
  description = "Número del proyecto semilla."
  value       = module.seed_project.project_number
}

output "workload_identity_pool" {
  description = "Nombre completo del pool de WIF."
  value       = google_iam_workload_identity_pool.github.name
}

output "kms_secret_iam_role_id" {
  description = "Rol personalizado de organización (organizations/<n>/roles/<id>) que la etapa 2 asigna a la cuenta de 4-projects sobre el proyecto security."
  value       = google_organization_iam_custom_role.kms_secret_iam_granter.name
}

output "state_iam_conditions" {
  description = "Mapa etapa → { writes, reads } con los prefijos de estado que cada cuenta escribe y lee (tabla de §6.1), para revisión."
  value       = { for k, s in local.stages : k => { writes = s.writes, reads = s.reads } }
}
