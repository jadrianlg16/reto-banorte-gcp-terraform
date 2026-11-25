# Salidas de la interfaz entre etapas (ADR 0029, tabla de interfaces: network_self_link,
# subnets, psa_range_name, reserved_cidrs, secure_tags y secure_tag_keys, con los tipos de la
# etapa de red anterior). Sin host_project_id ni host_project_number: no hay Shared VPC y todo
# vive en project_id (ADR 0029 §6).

output "network_self_link" {
  description = "self_link de la VPC spoke."
  value       = module.spoke.network_self_link
}

output "subnets" {
  description = "Llave del plan de direccionamiento → { self_link, name, region, cidr, secondary_ranges } (secondary_ranges: nombre → CIDR, llaves pods y services en app y app_dr)."
  value       = module.spoke.subnets
}

output "psa_range_name" {
  description = "Nombre del rango reservado de Private Service Access."
  value       = module.spoke.psa_range_name
}

output "secure_tags" {
  description = "Etiquetas seguras lb_backend e iap_ssh → ID del valor de etiqueta (tagValues/…)."
  value       = module.firewall.secure_tag_ids
}

output "secure_tag_keys" {
  description = "Etiquetas seguras lb_backend e iap_ssh → ID de su llave de etiqueta (tagKeys/…)."
  value       = module.firewall.secure_tag_key_ids
}

output "reserved_cidrs" {
  description = "Rangos reservados sin subred (plano de control de GKE: gke_master y, con enable_dr, gke_master_dr)."
  value       = module.spoke.reserved_cidrs
}

output "lb_backend_ports" {
  description = "Puertos TCP que la política del spoke abre hacia los backends con lb_backend (verificaciones de salud y proxies). La raíz de cargas del entorno comprueba que los puertos de sus backends estén aquí."
  value       = var.lb_backend_ports
}

output "dns_zone_names" {
  description = "Mapa env, onprem, googleapis, gcr, pkg, run → nombre de la zona de Cloud DNS."
  value       = module.dns.zone_names
}

# Salidas adicionales (no forman parte de la interfaz).

output "network_name" {
  description = "Nombre de la VPC spoke."
  value       = module.spoke.network_name
}

output "network_id" {
  description = "ID de la VPC spoke (projects/<proyecto>/global/networks/<nombre>)."
  value       = module.spoke.network_id
}

output "routers" {
  description = "Mapa región → nombre del Cloud Router del spoke."
  value       = module.spoke.routers
}

output "nat_names" {
  description = "Mapa región → nombre del Cloud NAT."
  value       = module.spoke.nat_names
}

output "firewall_policy_id" {
  description = "ID de la política de firewall de red del spoke (projects/<proyecto>/global/firewallPolicies/<nombre>)."
  value       = module.firewall.policy_id
}

output "firewall_policy_rules" {
  description = "Reglas de la política de red creadas por la raíz, leídas de los recursos (nombre → prioridad, acción, orígenes, etiquetas destino y protocolos/puertos). Además, el módulo crea la denegación por defecto de la entrada (prioridad 65000, con registro), que antes daba la política jerárquica."
  value = {
    for k, r in module.firewall.rules : k => {
      priority           = r.priority
      action             = r.action
      src_ip_ranges      = r.src_ip_ranges
      target_secure_tags = r.target_secure_tags
      layer4_configs     = r.layer4_configs
    }
  }
}

output "private_dns_domain" {
  description = "Dominio de la zona privada del entorno (<env>.empresa.internal. por defecto)."
  value       = local.private_dns_domain
}
