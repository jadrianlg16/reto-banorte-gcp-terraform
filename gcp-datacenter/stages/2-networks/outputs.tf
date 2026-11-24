# Salidas de la interfaz entre etapas (contrato §7.3).

output "hub_project_id" {
  description = "ID del proyecto net-hub."
  value       = local.hub_project_id
}

output "hub_network_name" {
  description = "Nombre de la VPC hub."
  value       = module.hub.network_name
}

output "hub_network_self_link" {
  description = "self_link de la VPC hub, para el peering y las zonas de peering DNS de los spokes."
  value       = module.hub.network_self_link
}

output "firewall_policy_id" {
  description = "ID de la política de firewall jerárquica de la organización (locations/global/firewallPolicies/<id>)."
  value       = module.firewall_org.policy_id
}

# Salidas adicionales (no forman parte del contrato).

output "spoke_supernets" {
  description = "Mapa entorno → /16 del spoke que el hub anuncia a on-premises. Cada spoke comprueba que su spoke_supernet coincida."
  value       = var.spoke_supernets
}

output "firewall_policy_rules" {
  description = "Reglas de la política jerárquica creadas por la raíz, leídas de los recursos (nombre → prioridad, acción, orígenes, VPC destino y protocolos/puertos). Además, el módulo crea la denegación por defecto de la entrada (prioridad 65000)."
  value = {
    for k, r in module.firewall_org.rules : k => {
      priority         = r.priority
      action           = r.action
      src_ip_ranges    = r.src_ip_ranges
      target_resources = r.target_resources
      layer4_configs   = r.layer4_configs
    }
  }
}

output "hub_routers" {
  description = "Mapa región → nombre del Cloud Router del hub."
  value       = module.hub.routers
}

output "bgp_advertised_ranges" {
  description = "Rangos que el hub anuncia a on-premises por BGP, leídos de la sesión if0 de la VPN primaria (ordenados). Todas las sesiones de las dos VPN anuncian los mismos."
  value       = module.vpn_hub.bgp_peers["if0"].advertised_ip_ranges
}

output "vpn_tunnel_names" {
  description = "Mapa interfaz → nombre del túnel HA VPN del hub hacia on-premises."
  value       = module.vpn_hub.tunnel_names
}

output "vpn_gateway_ip_addresses" {
  description = "IP externas del gateway HA VPN del hub, para configurar el equipo on-premises. Se conocen hasta el apply."
  value       = module.vpn_hub.gateway_ip_addresses
}

output "vpn_dr_tunnel_names" {
  description = "Mapa interfaz → nombre del túnel HA VPN de DR del hub hacia on-premises (vacío con enable_vpn_dr = false)."
  value       = var.enable_vpn_dr ? module.vpn_hub_dr[0].tunnel_names : {}
}

output "vpn_dr_gateway_ip_addresses" {
  description = "IP externas del gateway HA VPN de DR del hub, para configurar el equipo on-premises (vacía con enable_vpn_dr = false). Se conocen hasta el apply."
  value       = var.enable_vpn_dr ? module.vpn_hub_dr[0].gateway_ip_addresses : []
}

output "dns_inbound_forwarder_ips" {
  description = "IP de reenvío entrante de Cloud DNS en el hub, a las que on-premises reenvía las zonas de GCP. Se conocen hasta el apply."
  value       = module.dns.inbound_forwarder_ips
}

output "onprem_sim_network_name" {
  description = "Nombre de la VPC onprem-sim, o null con simulate_onprem = false."
  value       = var.simulate_onprem ? module.onprem_sim[0].network_name : null
}

output "onprem_sim_firewall_policy_id" {
  description = "ID de la política de firewall de red de la VPC onprem-sim (DNS desde 35.199.192.0/19 e IAP), o null con simulate_onprem = false."
  value       = var.simulate_onprem ? module.firewall_onprem_sim[0].policy_id : null
}
