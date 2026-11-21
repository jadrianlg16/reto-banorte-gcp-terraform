output "vault_id" {
  description = "ID de la bóveda de Backup and DR (en dr_region)."
  value       = google_backup_dr_backup_vault.this.id
}

output "vault_service_account" {
  description = "Cuenta de servicio de la bóveda; necesita permisos sobre los recursos protegidos."
  value       = google_backup_dr_backup_vault.this.service_account
}

output "plan_ids" {
  description = "Mapa llave → ID de cada plan: las llaves de backup_plans (Backup and DR) y \"gke\" (Backup for GKE) si enable_gke_backup."
  value = merge(
    { for k, p in google_backup_dr_backup_plan.this : k => p.id },
    { for k, p in google_gke_backup_backup_plan.this : k => p.id },
  )
}

output "plan_association_ids" {
  description = "Mapa llave de protected_resources → ID de la asociación con su plan."
  value       = { for k, a in google_backup_dr_backup_plan_association.this : k => a.id }
}
