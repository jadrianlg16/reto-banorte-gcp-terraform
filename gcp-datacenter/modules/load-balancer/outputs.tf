output "ip_address" {
  description = "IP del balanceador: pública global en \"external\" (para los registros DNS A de domain_names), interna regional en \"internal\"."
  value = one(concat(
    [for a in google_compute_global_address.this : a.address],
    [for a in google_compute_address.this : a.address],
  ))
}

output "backend_service_ids" {
  description = "Mapa llave de backends → ID del servicio de backend."
  value = merge(
    { for k, b in google_compute_backend_service.this : k => b.id },
    { for k, b in google_compute_region_backend_service.this : k => b.id },
  )
}

output "backend_groups" {
  description = "Mapa llave de backends → grupos (self links o IDs) que el servicio de backend tiene configurados: groups o, con dr_active, dr_groups."
  value = merge(
    { for k, b in google_compute_backend_service.this : k => sort([for be in b.backend : be.group]) },
    { for k, b in google_compute_region_backend_service.this : k => sort([for be in b.backend : be.group]) },
  )
}

output "url_map_id" {
  description = "ID del mapa de URL principal (HTTPS)."
  value = one(concat(
    [for u in google_compute_url_map.this : u.id],
    [for u in google_compute_region_url_map.this : u.id],
  ))
}

output "url_map_name" {
  description = "Nombre del mapa de URL principal; sirve para filtrar métricas del balanceador (resource.label.url_map_name)."
  value = one(concat(
    [for u in google_compute_url_map.this : u.name],
    [for u in google_compute_region_url_map.this : u.name],
  ))
}

output "forwarding_rule_names" {
  description = "Nombres de las reglas de reenvío, llaves https y http."
  value = merge(
    { for r in google_compute_global_forwarding_rule.https : "https" => r.name },
    { for r in google_compute_global_forwarding_rule.http : "http" => r.name },
    { for r in google_compute_forwarding_rule.https : "https" => r.name },
    { for r in google_compute_forwarding_rule.http : "http" => r.name },
  )
}

output "health_check_ids" {
  description = "Mapa llave de backends → ID de la verificación de salud usada (null en backends serverless)."
  value       = local.health_check_ids
}

output "dns_authorization_records" {
  description = "Solo \"internal\" con certificado creado por el módulo: dominio → registro DNS (name, type, data) que hay que crear para emitir el certificado."
  value = {
    for k, a in google_certificate_manager_dns_authorization.this : a.domain => {
      name = a.dns_resource_record[0].name
      type = a.dns_resource_record[0].type
      data = a.dns_resource_record[0].data
    }
  }
}
