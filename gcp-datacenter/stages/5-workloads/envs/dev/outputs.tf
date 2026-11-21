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
  description = "Dominio → registro DNS (name, type, data) que hay que crear para emitir el certificado del balanceador interno de la región activa."
  value = {
    for k, a in google_certificate_manager_dns_authorization.internal : a.domain => {
      name = a.dns_resource_record[0].name
      type = a.dns_resource_record[0].type
      data = a.dns_resource_record[0].data
    } if local.internal_cert_authorizations[k].region_key == local.active_key
  }
}

output "internal_lb_dns_authorization_records_by_region" {
  description = "Mapa región → dominio → registro DNS de autorización del certificado interno de esa región. Con enable_dr incluye dr_region aunque dr_active sea false: esos registros se crean antes de un incidente."
  value = {
    for region_key, region in local.internal_cert_regions : region => {
      for k, a in google_certificate_manager_dns_authorization.internal : a.domain => {
        name = a.dns_resource_record[0].name
        type = a.dns_resource_record[0].type
        data = a.dns_resource_record[0].data
      } if local.internal_cert_authorizations[k].region_key == region_key
    }
  }
}

output "internal_lb_certificate_ids" {
  description = "Mapa región → ID del certificado de Certificate Manager del balanceador interno (la de DR existe con enable_dr, antes de dr_active). Vacío sin enable_internal_lb."
  value       = { for k, c in google_certificate_manager_certificate.internal : local.regions[k] => c.id }
}

output "internal_lb_dns_records" {
  description = "Registros A que deben existir en el DNS interno (fuera de este repositorio) para internal_domain_names: nombre → type y rrdatas con la IP del balanceador interno de la región activa. Cambia con dr_active; moverlos es el paso manual de DNS del runbook 04. Vacío sin enable_internal_lb."
  value = {
    for d in var.internal_domain_names : d => {
      type    = "A"
      rrdatas = [module.internal_lb[local.active_key].ip_address]
    } if contains(keys(module.internal_lb), local.active_key)
  }
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
