output "policy_id" {
  description = "ID de la política (locations/global/firewallPolicies/<id> en hierarchical; projects/<proyecto>/global/firewallPolicies/<nombre> en network)."
  value       = local.is_hierarchical ? google_compute_firewall_policy.this[0].id : google_compute_network_firewall_policy.this[0].id
}

output "policy_name" {
  description = "Nombre de la política: ID numérico en hierarchical, nombre corto en network."
  value       = local.is_hierarchical ? google_compute_firewall_policy.this[0].name : google_compute_network_firewall_policy.this[0].name
}

output "secure_tag_ids" {
  description = "Mapa llave de secure_tags → ID del valor de etiqueta (tagValues/<id>). Quien adjunta la etiqueta a una VM necesita roles/resourcemanager.tagUser sobre el valor."
  value       = { for k, v in google_tags_tag_value.this : k => v.id }
}

output "secure_tag_key_id" {
  description = "ID de la llave de etiqueta (tagKeys/<id>), o null si no hay secure_tags."
  value       = length(google_tags_tag_key.this) > 0 ? google_tags_tag_key.this[0].id : null
}
