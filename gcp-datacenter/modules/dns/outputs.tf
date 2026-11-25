output "zone_names" {
  description = "Mapa llave de zones → nombre de la zona administrada."
  value       = { for k, z in google_dns_managed_zone.this : k => z.name }
}

output "zone_domains" {
  description = "Mapa llave de zones → dominio DNS."
  value       = { for k, z in var.zones : k => z.domain }
}

output "zones" {
  description = "Zonas creadas, leídas de los recursos: llave de zones → { name, dns_name, networks (VPC con visibilidad, ordenadas), peer_network (null si no es de peering), forwarding_targets (IP, vacío si no es de reenvío) }."
  value = {
    for k, z in google_dns_managed_zone.this : k => {
      name               = z.name
      dns_name           = z.dns_name
      networks           = sort(flatten([for c in z.private_visibility_config : [for n in c.networks : n.network_url]]))
      peer_network       = try(z.peering_config[0].target_network[0].network_url, null)
      forwarding_targets = sort(flatten([for c in z.forwarding_config : [for t in c.target_name_servers : t.ipv4_address]]))
    }
  }
}

output "records" {
  description = "Registros creados, leídos de los recursos: <zona>/<registro> → { name, type, rrdatas }."
  value = {
    for k, r in google_dns_record_set.this : k => {
      name    = r.name
      type    = r.type
      rrdatas = r.rrdatas
    }
  }
}

output "policy_name" {
  description = "Nombre de la política de servidor DNS, o null si no se creó."
  value       = length(google_dns_policy.this) > 0 ? google_dns_policy.this[0].name : null
}

output "inbound_forwarder_ips" {
  description = "IP de reenvío entrante que on-premises usa para resolver las zonas de Cloud DNS (lista vacía sin reenvío entrante). Se conocen hasta el apply."
  value       = length(data.google_compute_addresses.inbound_forwarders) > 0 ? sort([for a in data.google_compute_addresses.inbound_forwarders[0].addresses : a.address]) : []
}
