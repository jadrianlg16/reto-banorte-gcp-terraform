output "zone_names" {
  description = "Mapa llave de zones → nombre de la zona administrada."
  value       = { for k, z in google_dns_managed_zone.this : k => z.name }
}

output "zone_domains" {
  description = "Mapa llave de zones → dominio DNS."
  value       = { for k, z in var.zones : k => z.domain }
}

output "policy_name" {
  description = "Nombre de la política de servidor DNS, o null si no se creó."
  value       = length(google_dns_policy.this) > 0 ? google_dns_policy.this[0].name : null
}

output "inbound_forwarder_ips" {
  description = "IP de reenvío entrante que on-premises usa para resolver las zonas de Cloud DNS (lista vacía sin reenvío entrante). Se conocen hasta el apply."
  value       = length(data.google_compute_addresses.inbound_forwarders) > 0 ? sort([for a in data.google_compute_addresses.inbound_forwarders[0].addresses : a.address]) : []
}
