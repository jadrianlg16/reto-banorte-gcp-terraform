output "policy_id" {
  description = "ID de la política de firewall de red (projects/<proyecto>/global/firewallPolicies/<nombre>)."
  value       = google_compute_network_firewall_policy.this.id
}

output "policy_name" {
  description = "Nombre corto de la política de firewall de red."
  value       = google_compute_network_firewall_policy.this.name
}

output "network_id" {
  description = "VPC a la que quedó asociada la política (projects/<proyecto>/global/networks/<nombre>), leída del recurso de asociación."
  value       = google_compute_network_firewall_policy_association.this.attachment_target
}

output "rules" {
  description = "Reglas creadas por el llamador, leídas de los recursos de regla (no de la variable rules): nombre → { priority, action, direction, enable_logging, src_ip_ranges, dest_ip_ranges, target_secure_tags (llaves lógicas de secure_tags), layer4_configs }. No incluye las denegaciones por defecto del módulo (ver default_deny_rules)."
  value = {
    for k, r in google_compute_network_firewall_policy_rule.this : k => {
      priority       = r.priority
      action         = r.action
      direction      = r.direction
      enable_logging = r.enable_logging
      src_ip_ranges  = r.match[0].src_ip_ranges == null ? [] : tolist(r.match[0].src_ip_ranges)
      dest_ip_ranges = r.match[0].dest_ip_ranges == null ? [] : tolist(r.match[0].dest_ip_ranges)
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

output "default_deny_rules" {
  description = "Denegaciones por defecto que crea el módulo, leídas de los recursos: ingress (siempre) y egress (solo con enable_egress_default_deny) → { priority, action, direction, enable_logging, src_ip_ranges, dest_ip_ranges }."
  value = {
    for k, r in merge(
      { ingress = google_compute_network_firewall_policy_rule.default_deny_ingress },
      { for r in google_compute_network_firewall_policy_rule.default_deny_egress : "egress" => r },
      ) : k => {
      priority       = r.priority
      action         = r.action
      direction      = r.direction
      enable_logging = r.enable_logging
      src_ip_ranges  = r.match[0].src_ip_ranges == null ? [] : tolist(r.match[0].src_ip_ranges)
      dest_ip_ranges = r.match[0].dest_ip_ranges == null ? [] : tolist(r.match[0].dest_ip_ranges)
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
