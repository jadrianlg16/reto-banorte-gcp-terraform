# Salidas de §7.6 (interfaz entre etapas: nombres y tipos fijos) y salidas adicionales.

output "lb_ip_address" {
  description = "IP pública global del balanceador HTTPS externo (para los registros DNS A de domain_names). null si no hay ningún backend habilitado."
  value       = try(module.external_lb["external"].ip_address, null)
}

output "gke_cluster_names" {
  description = "Mapa región → nombre del clúster de GKE (vacío con enable_gke = false; con dr_active incluye dr_region)."
  value       = { for k, c in module.gke : local.compute_regions[k] => c.cluster_name }
}

output "sql_instance_connection_name" {
  description = "Nombre de conexión de la instancia primaria de Cloud SQL (<proyecto>:<región>:<instancia>)."
  value       = module.cloud_sql.connection_name
}

output "bucket_names" {
  description = "Mapa uso → nombre del bucket (llave data: el de la aplicación, de doble región con enable_dr)."
  value       = { data = module.storage.bucket_name }
}

# Adicionales.

output "sql_replica_connection_name" {
  description = "Nombre de conexión de la réplica de Cloud SQL en dr_region (null sin enable_dr). Se promueve en el runbook de conmutación."
  value       = module.cloud_sql.replica_connection_name
}

output "cloud_run_service_names" {
  description = "Mapa región → nombre del servicio de Cloud Run (vacío con enable_cloud_run = false)."
  value       = { for k, s in module.cloud_run : local.compute_regions[k] => s.service_name }
}

output "mig_instance_groups" {
  description = "Mapa región → URL del grupo de instancias del MIG (vacío con enable_mig = false)."
  value       = { for k, m in module.mig : local.compute_regions[k] => m.instance_group }
}

output "internal_lb_ip_address" {
  description = "IP interna del balanceador interno de la región activa (active_region): la que debe tener el registro DNS interno. null sin enable_internal_lb."
  value       = try(module.internal_lb[local.active_key].ip_address, null)
}

output "internal_lb_ip_addresses" {
  description = "Mapa región → IP interna del balanceador interno de esa región (la de DR solo con dr_active). Vacío sin enable_internal_lb."
  value       = { for k, lb in module.internal_lb : local.compute_regions[k] => lb.ip_address }
}

output "internal_lb_dns_authorization_records" {
  description = "Registros DNS (name, type, data) que hay que crear para emitir el certificado del balanceador interno de la región activa."
  value       = try(module.internal_lb[local.active_key].dns_authorization_records, {})
}

output "internal_lb_dns_authorization_records_by_region" {
  description = "Mapa región → registros DNS de autorización del certificado de cada balanceador interno (con dr_active incluye dr_region)."
  value       = { for k, lb in module.internal_lb : local.compute_regions[k] => lb.dns_authorization_records }
}

output "gke_workload_identity_member" {
  description = "Miembro serviceAccount:<proyecto>.svc.id.goog[<namespace>/<cuenta>] que actúa como la cuenta workload (null sin enable_gke)."
  value       = try(google_service_account_iam_member.workload_identity["workload"].member, null)
}

output "redis_host" {
  description = "IP privada de Memorystore (null con enable_memorystore = false)."
  value       = try(module.memorystore["primary"].host, null)
}

output "filestore_ip_address" {
  description = "IP privada del servidor NFS de Filestore (null con enable_filestore = false)."
  value       = try(module.filestore["primary"].ip_address, null)
}

output "backup_vault_id" {
  description = "ID de la bóveda de Backup and DR en dr_region (null con enable_backup = false)."
  value       = try(module.backup["this"].vault_id, null)
}

output "backup_plan_ids" {
  description = "Mapa llave → ID de cada plan de respaldo (sql y, con DR y GKE, gke)."
  value       = try(module.backup["this"].plan_ids, {})
}

output "active_region" {
  description = "Región que atiende el tráfico de los balanceadores (dr_region con dr_active)."
  value       = local.active_region
}
