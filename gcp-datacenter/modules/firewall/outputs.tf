output "policy_id" {
  description = "ID de la política (locations/global/firewallPolicies/<id> en hierarchical; projects/<proyecto>/global/firewallPolicies/<nombre> en network)."
  value       = local.is_hierarchical ? google_compute_firewall_policy.this[0].id : google_compute_network_firewall_policy.this[0].id
}

output "policy_name" {
  description = "Nombre de la política: ID numérico en hierarchical, nombre corto en network."
  value       = local.is_hierarchical ? google_compute_firewall_policy.this[0].name : google_compute_network_firewall_policy.this[0].name
}

output "rules" {
  description = "Reglas creadas por el llamador, leídas de los recursos de regla (no de la variable rules): nombre → { priority, action, direction, enable_logging, src_ip_ranges, dest_ip_ranges, target_resources, target_secure_tags (llaves lógicas de secure_tags), layer4_configs }. No incluye las denegaciones por defecto del módulo."
  value = {
    for k, r in merge(google_compute_firewall_policy_rule.this, google_compute_network_firewall_policy_rule.this) : k => {
      priority         = r.priority
      action           = r.action
      direction        = r.direction
      enable_logging   = r.enable_logging
      src_ip_ranges    = r.match[0].src_ip_ranges == null ? [] : tolist(r.match[0].src_ip_ranges)
      dest_ip_ranges   = r.match[0].dest_ip_ranges == null ? [] : tolist(r.match[0].dest_ip_ranges)
      target_resources = try(r.target_resources == null ? [] : tolist(r.target_resources), [])
      # El recurso guarda el ID del valor (tagValues/…); se traduce a la llave lógica.
      target_secure_tags = [
        for tk, tv in google_tags_tag_value.this : tk if contains([for t in r.target_secure_tags : t.name], tv.id)
      ]
      layer4_configs = [
        for l in r.match[0].layer4_configs : { ip_protocol = l.ip_protocol, ports = l.ports == null ? [] : tolist(l.ports) }
      ]
    }
  }
}

output "secure_tag_ids" {
  description = "Mapa llave de secure_tags → ID del valor de etiqueta (tagValues/<id>). Quien adjunta la etiqueta a una VM necesita roles/resourcemanager.tagUser sobre el valor."
  value       = { for k, v in google_tags_tag_value.this : k => v.id }
}

output "secure_tag_key_ids" {
  description = "Mapa llave de secure_tags → ID de su llave de etiqueta (tagKeys/<id>). Cada entrada es una llave propia con un solo valor (enabled); vacío si no hay secure_tags."
  value       = { for k, v in google_tags_tag_key.this : k => v.id }
}
