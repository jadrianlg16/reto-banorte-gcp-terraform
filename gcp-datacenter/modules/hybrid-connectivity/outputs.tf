output "gateway_self_link" {
  description = "self_link del gateway HA VPN (la otra punta lo usa como peer.gcp_gateway_self_link en el modo simulado)."
  value       = google_compute_ha_vpn_gateway.this.self_link
}

output "gateway_ip_addresses" {
  description = "IP externas de las interfaces del gateway HA VPN, en orden de interfaz (para configurar el equipo on-premises). Se conocen hasta el apply."
  value       = [for i in google_compute_ha_vpn_gateway.this.vpn_interfaces : i.ip_address]
}

output "tunnel_names" {
  description = "Mapa llave de bgp_sessions → nombre del túnel."
  value       = { for k, t in google_compute_vpn_tunnel.this : k => t.name }
}

output "bgp_peer_names" {
  description = "Mapa llave de bgp_sessions → nombre de la sesión BGP del Cloud Router."
  value       = { for k, p in google_compute_router_peer.vpn : k => p.name }
}

output "bgp_peers" {
  description = "Sesiones BGP creadas, leídas de los recursos: llave de bgp_sessions → { name, router, ip_address, peer_ip_address, peer_asn, advertised_route_priority, advertise_mode, advertised_ip_ranges }."
  value = {
    for k, p in google_compute_router_peer.vpn : k => {
      name                      = p.name
      router                    = p.router
      ip_address                = p.ip_address
      peer_ip_address           = p.peer_ip_address
      peer_asn                  = p.peer_asn
      advertised_route_priority = p.advertised_route_priority
      advertise_mode            = p.advertise_mode
      advertised_ip_ranges      = sort([for r in p.advertised_ip_ranges : r.range])
    }
  }
}

output "external_gateway_self_link" {
  description = "self_link del gateway externo, o null con peer.type = gcp."
  value       = local.is_external ? google_compute_external_vpn_gateway.this[0].self_link : null
}

output "interconnect_attachment_names" {
  description = "Mapa llave de interconnect_attachments → nombre del VLAN attachment (vacío con enable_interconnect = false)."
  value       = { for k, a in google_compute_interconnect_attachment.this : k => a.name }
}
